import Foundation
import SwiftData
import ResetCore

struct FoodDraft: Identifiable {
    let id = UUID()
    var text: String
    var items: [FoodItem]
    var mealType: MealType
    var uncertainties: [String]
}

/// Runs coach tool calls against local data. Reads and writes only the records listed in CoachAction.
/// Nothing here can reach other device data, delete records or change permissions.
final class AppCoachBackend: CoachBackend, @unchecked Sendable {
    private let container: ModelContainer
    private let health: HealthService
    /// Food interpreted by the coach, waiting for the user. Read by the chat screen on the main actor.
    @MainActor var drafts: [FoodDraft] = []

    init(container: ModelContainer, health: HealthService) {
        self.container = container; self.health = health
    }

    @MainActor private var ctx: ModelContext { container.mainContext }
    @MainActor private var profile: UserProfile? { try? ctx.fetch(FetchDescriptor<UserProfile>()).first }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func execute(_ action: CoachAction) async -> CoachToolResult {
        switch action {
        case .logFood(let text): return await logFood(text)
        default: return await MainActor.run { run(action) }
        }
    }

    // MARK: Synchronous actions

    @MainActor private func run(_ action: CoachAction) -> CoachToolResult {
        let p = profile
        switch action {
        case .getTodaySummary:
            return json(DaySummaryBuilder.build(context: ctx, profile: p, health: health))

        case .getHistory(let metric, let days):
            var lines: [String] = []
            let cal = Calendar.current
            if metric == .weight {
                let w = ((try? ctx.fetch(FetchDescriptor<WeightRecord>(sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? [])
                    .filter { $0.at > cal.date(byAdding: .day, value: -days, to: .now) ?? .distantPast }
                lines = w.map { "\(Self.dayFmt.string(from: $0.at)): \(String(format: "%.1f", $0.kg)) kg" }
            } else {
                for back in 0..<days {
                    guard let d = cal.date(byAdding: .day, value: -back, to: .now) else { continue }
                    let s = DaySummaryBuilder.build(context: ctx, profile: p, health: health, day: d)
                    let v: String?
                    switch metric {
                    case .sleep: v = s.sleepHours.map { String(format: "%.1f h", $0) }
                    case .water: v = s.waterMl > 0 ? "\(Int(s.waterMl)) ml" : nil
                    case .steps: v = back == 0 ? s.steps.map { "\($0)" } : health.week.first { cal.isDate($0.day, inSameDayAs: d) }.map { "\($0.steps)" }
                    case .calories: v = s.mealsLogged > 0 ? "\(Int(s.kcalConsumed)) kcal (estimates)" : nil
                    case .protein: v = s.mealsLogged > 0 ? "\(Int(s.proteinG)) g" : nil
                    case .caffeine: v = s.caffeineMg > 0 ? "\(Int(s.caffeineMg)) mg" : nil
                    case .work: v = s.workSeconds.map { String(format: "%.1f h", $0 / 3600) }
                    case .university: v = s.universitySeconds.map { String(format: "%.1f h", $0 / 3600) }
                    case .weight: v = nil
                    }
                    if let v { lines.append("\(Self.dayFmt.string(from: d)): \(v)") }
                }
            }
            return CoachToolResult(text: lines.isEmpty ? "Nothing recorded for \(metric.rawValue) in the last \(days) days." : lines.joined(separator: "\n"))

        case .getWorkTotals(let range):
            let sessions = ((try? ctx.fetch(FetchDescriptor<TrackedSession>())) ?? []).map(\.value)
            let window: DateInterval
            switch range {
            case .today: window = Day.interval(of: .now)
            case .week: window = SessionMath.week(of: .now)
            case .month: window = SessionMath.month(of: .now)
            }
            func line(_ c: SessionCategory) -> String {
                let t = SessionMath.totals(sessions, category: c, in: window, now: .now)
                return "\(c.rawValue): \(String(format: "%.1f", t.total / 3600)) h total (\(String(format: "%.1f", t.confirmed / 3600)) h confirmed or manual, \(String(format: "%.1f", t.estimated / 3600)) h location estimate)\(t.needsReviewCount > 0 ? ", \(t.needsReviewCount) session(s) need review and are not counted" : "")"
            }
            return CoachToolResult(text: "\(range.rawValue)\n" + line(.work) + "\n" + line(.university))

        case .getActivityHistory(let days):
            let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
            let acts = ((try? ctx.fetch(FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []).filter { $0.start >= since }
            let kept = Set(ActivityMath.dedupe(acts.map { ActivitySpan(id: $0.id, kind: $0.kind, start: $0.start, end: $0.end, source: $0.source) }).map(\.id))
            let lines = acts.filter { kept.contains($0.id) }.map { "\(Self.dayFmt.string(from: $0.start)): \($0.kind.rawValue) \(Int($0.minutes)) min" }
            return CoachToolResult(text: lines.isEmpty ? "No activity recorded in the last \(days) days." : lines.joined(separator: "\n"))

        case .logWater(let ml):
            ctx.insert(WaterRecord(ml: ml, source: .manual)); try? ctx.save()
            return CoachToolResult(text: "Logged \(Int(ml)) ml of water.")

        case .logCaffeine(let name, let mg, let count):
            let match = Caffeine.catalogMatch(name)
            guard let each = mg ?? match?.mg else { return CoachToolResult(text: "No caffeine amount known for \(name). Ask the user for it.", isError: true) }
            let src = mg != nil ? "Stated by you" : "Typical value for \(match!.name). Check your can."
            ctx.insert(CaffeineRecord(name: match?.name ?? name, servingMl: match?.servingMl, mg: each, count: count, mgSource: src, source: mg != nil ? .manual : .aiEstimate))
            try? ctx.save()
            return CoachToolResult(text: "Logged \(count) x \(match?.name ?? name), \(Int(each * Double(count))) mg caffeine in total (\(src)).")

        case .recordEnergy(let v): ctx.insert(CheckIn(kind: .energy, value: v)); try? ctx.save(); return CoachToolResult(text: "Energy \(v) of 5 recorded.")
        case .recordFatigue(let v): ctx.insert(CheckIn(kind: .fatigue, value: v)); try? ctx.save(); return CoachToolResult(text: "Fatigue \(v) of 5 recorded.")

        case .recordWeight(let kg):
            ctx.insert(WeightRecord(kg: kg)); p?.weightKg = kg; try? ctx.save()
            return CoachToolResult(text: "Weight \(String(format: "%.1f", kg)) kg recorded.")

        case .createWorkout(let minutes):
            let r = RecoverySnapshot.assess(context: ctx, profile: p)
            let symptoms = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).contains { $0.kind == .symptom && $0.at > Date.now.addingTimeInterval(-86_400) }
            let avg = health.week.isEmpty ? nil : health.week.map(\.steps).reduce(0, +) / health.week.count
            let s = WorkoutGenerator.suggest(WorkoutContextBuilder.build(context: ctx, profile: p, minutes: minutes, planned: true, band: r.band, symptoms: symptoms, avgSteps: avg))
            ctx.insert(WorkoutPlan(day: .now, title: s.title, kind: s.kind, minutes: s.minutes,
                                   exercises: s.exercises.map { PlannedExercise(name: $0.name, sets: $0.sets, reps: $0.reps, restSec: $0.restSec, modification: $0.modification) },
                                   stepTarget: s.stepTarget, reason: s.reason))
            try? ctx.save()
            let list = s.exercises.map { "\($0.name) \($0.sets)x\($0.reps)" }.joined(separator: ", ")
            return CoachToolResult(text: "Created: \(s.title), \(s.minutes) min. \(list.isEmpty ? "" : list + ". ")Why: \(s.reason)")

        case .updatePreference(let key, let value):
            guard let p else { return CoachToolResult(text: "No profile.", isError: true) }
            switch key {
            case .waterGoalMl: p.waterGoalMl = value
            case .sleepTargetHours: p.sleepTargetHours = value
            case .deficitPercent: p.deficitPercent = value
            case .proteinPerKg: p.proteinPerKg = value
            case .calorieCounting: p.calorieCountingEnabled = value >= 0.5
            }
            try? ctx.save()
            return CoachToolResult(text: "Updated \(key.rawValue) to \(String(format: "%g", value)).")

        case .logFood: return CoachToolResult(text: "Handled elsewhere.", isError: true)
        }
    }

    // MARK: Food

    private func logFood(_ text: String) async -> CoachToolResult {
        let (provider, auto, lookup) = await MainActor.run { () -> (AIProvider?, Bool, USDAClient) in
            let p = self.profile
            return (AIConfig.provider(for: p), p?.autoSaveFood ?? false, USDAClient(apiKey: Keychain.get(Keychain.usdaKey)))
        }
        guard let provider else { return CoachToolResult(text: "AI is not set up, so food can't be interpreted. Ask the user to log it in the Nutrition tab.", isError: true) }
        do {
            let a = try await FoodAnalyzer.analyze(text: text, imageJPEG: nil, provider: provider, lookup: lookup)
            return await MainActor.run {
                let meal = a.mealType ?? AddFoodView.guessMealType()
                let total = a.items.filter(\.consumed).reduce(Nutrition.zero) { $0 + $1.nutrition }
                let summary = a.items.map { "\($0.name) \(Int($0.grams)) g, \(Int($0.nutrition.kcal)) kcal\($0.verified ? "" : " (estimate)")" }.joined(separator: "; ")
                if auto && a.canAutoSave {
                    ctx.insert(MealRecord(at: .now, mealType: meal, originalText: text, items: a.items, source: .aiEstimate, confidence: a.items.map(\.confidence).min() ?? .medium))
                    for i in a.items where i.consumed && (i.nutrition.caffeineMg ?? 0) > 0 {
                        ctx.insert(CaffeineRecord(name: i.name, servingMl: i.grams, mg: i.nutrition.caffeineMg!, mgSource: i.dataSource, source: .aiEstimate))
                    }
                    try? ctx.save()
                    return CoachToolResult(text: "Saved automatically as estimates: \(summary). Total about \(Int(total.kcal)) kcal and \(Int(total.proteinG)) g protein.")
                }
                drafts.append(FoodDraft(text: text, items: a.items, mealType: meal, uncertainties: a.uncertainties))
                return CoachToolResult(text: "NOT saved yet. A draft is shown to the user to confirm: \(summary). Total about \(Int(total.kcal)) kcal and \(Int(total.proteinG)) g protein (estimates).\(a.uncertainties.isEmpty ? "" : " Unsure about: " + a.uncertainties.joined(separator: ", ") + ".")")
            }
        } catch {
            return CoachToolResult(text: "Could not interpret the food: \(error.localizedDescription)", isError: true)
        }
    }

    private func json<T: Encodable>(_ v: T) -> CoachToolResult {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        return CoachToolResult(text: (try? e.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }
}
