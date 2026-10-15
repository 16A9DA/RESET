import Foundation
import SwiftData
import ResetCore

/// Builds the one shared picture of a day from stored data. Used by Today, the timeline and the coach tools.
enum DaySummaryBuilder {
    @MainActor
    static func build(context: ModelContext, profile: UserProfile?, health: HealthService?, day: Date = .now) -> DaySummary {
        let cal = Calendar.current
        let w = Day.interval(of: day, calendar: cal)
        let isToday = cal.isDateInToday(day)
        func fetch<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }

        let sleep = fetch(SleepRecord.self).first { cal.isDate($0.day, inSameDayAs: day) }
        let checks = fetch(CheckIn.self).filter { w.contains($0.at) }.sorted { $0.at > $1.at }
        let acts = fetch(ActivityRecord.self).map { ActivitySpan(id: $0.id, kind: $0.kind, start: $0.start, end: $0.end, source: $0.source, steps: $0.steps) }
        let workouts = fetch(WorkoutRecord.self).filter { $0.completed && w.contains($0.start) }.map(\.title)
        let meals = fetch(MealRecord.self)
        let nut = NutritionTotals.day(meals.map { ($0.at, $0.items) }, on: day, calendar: cal)
        let water = fetch(WaterRecord.self).filter { w.contains($0.at) }.reduce(0) { $0 + $1.ml }
        let caffeine = Caffeine.dailyTotal(fetch(CaffeineRecord.self).map(\.dose), on: day, calendar: cal)
        let sessions = fetch(TrackedSession.self).map(\.value)
        func seconds(_ c: SessionCategory) -> Double? {
            let touched = sessions.contains { $0.category == c && SessionMath.seconds($0, in: w, now: .now) > 0 }
            return touched ? SessionMath.totals(sessions, category: c, in: w, now: .now).total : nil
        }
        let plan = profile?.energyPlan
        let r = RecoverySnapshot.assess(context: context, profile: profile)
        let steps = ActivityMath.dailySteps(system: isToday ? health?.todaySteps : nil, fallbackFromSpans: [])

        return DaySummary(
            date: day, sleepHours: sleep?.hours, sleepTargetHours: profile?.sleepTargetHours ?? 8,
            energy: checks.first { $0.kind == .energy }?.value, fatigue: checks.first { $0.kind == .fatigue }?.value,
            steps: steps, stepSource: isToday ? health?.stepSource : nil,
            structuredActivityMinutes: ActivityMath.structuredMinutes(acts, in: w), workouts: workouts,
            kcalConsumed: nut.total.kcal, kcalTarget: plan?.targetKcal, kcalMaintenance: plan?.maintenanceKcal,
            calorieCounting: profile?.calorieCountingEnabled ?? true, proteinG: nut.total.proteinG,
            proteinTargetG: plan?.proteinG ?? 0, mealsLogged: nut.mealCount, estimatedItems: nut.estimatedItemCount,
            waterMl: water, waterGoalMl: profile?.effectiveWaterGoalMl, caffeineMg: caffeine,
            workSeconds: seconds(.work), universitySeconds: seconds(.university),
            recoveryBand: r.band, recoveryReasons: r.reasons)
    }

    @MainActor
    static func timeline(context: ModelContext, day: Date) -> [TimelineEntry] {
        func fetch<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        var out: [TimelineEntry] = []
        for s in fetch(SleepRecord.self) {
            out.append(TimelineEntry(id: "sleep.\(s.id)", kind: .sleep, start: s.asleepAt, end: s.wokeAt, title: "Sleep",
                                     detail: String(format: "%.1f h", s.hours), origin: Origin.from(s.source)))
        }
        for s in fetch(TrackedSession.self) {
            let name = s.category.rawValue.capitalized
            let kind: TimelineKind = s.category == .university ? .university : .work
            out.append(TimelineEntry(id: "session.\(s.id)", kind: kind, start: s.start, end: s.end, title: name,
                                     detail: s.status == .needsReview ? "Needs review" : (s.breaks.isEmpty ? "" : "\(s.breaks.count) break(s)"),
                                     origin: Origin.from(s.source, status: s.status)))
        }
        for m in fetch(MealRecord.self) {
            out.append(TimelineEntry(id: "meal.\(m.id)", kind: .meal, start: m.at, title: m.mealType.title,
                                     detail: "\(Int(m.nutrition.kcal.rounded())) kcal, \(m.items.map(\.name).joined(separator: ", "))",
                                     origin: Origin.from(m.source)))
        }
        for r in fetch(WaterRecord.self) {
            out.append(TimelineEntry(id: "water.\(r.id)", kind: .water, start: r.at, title: "Water", detail: "\(Int(r.ml)) ml", origin: Origin.from(r.source)))
        }
        for c in fetch(CaffeineRecord.self) {
            out.append(TimelineEntry(id: "caf.\(c.id)", kind: .caffeine, start: c.at, title: c.name, detail: "\(Int(c.totalMg)) mg caffeine",
                                     origin: Origin.from(c.source)))
        }
        let spans = fetch(ActivityRecord.self).map { ActivitySpan(id: $0.id, kind: $0.kind, start: $0.start, end: $0.end, source: $0.source) }
        let kept = Set(ActivityMath.dedupe(spans).map(\.id)) // overlapping reports of one walk show once
        for a in fetch(ActivityRecord.self) where kept.contains(a.id) {
            out.append(TimelineEntry(id: "act.\(a.id)", kind: .activity, start: a.start, end: a.end, title: a.kind.rawValue.capitalized,
                                     detail: "\(Int(a.minutes)) min", origin: Origin.from(a.source)))
        }
        for c in fetch(CheckIn.self) where c.kind == .energy || c.kind == .fatigue {
            out.append(TimelineEntry(id: "chk.\(c.id)", kind: .checkIn, start: c.at, title: c.kind == .energy ? "Energy" : "Fatigue",
                                     detail: "\(c.value) of 5", origin: .manual))
        }
        return Timeline.build(out, on: day)
    }
}
