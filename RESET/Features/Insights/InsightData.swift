import Foundation
import SwiftData
import ResetCore

enum InsightData {
    /// One InsightDay per calendar day for the last `days` days, built in a single pass over stored records.
    /// Anything not recorded stays nil so it is skipped by the comparisons.
    @MainActor
    static func days(context: ModelContext, profile: UserProfile?, count: Int = 60) -> [InsightDay] {
        let cal = Calendar.current
        func fetch<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let sleeps = fetch(SleepRecord.self), checks = fetch(CheckIn.self), caffeine = fetch(CaffeineRecord.self)
        let meals = fetch(MealRecord.self), waters = fetch(WaterRecord.self), acts = fetch(ActivityRecord.self)
        let workouts = fetch(WorkoutRecord.self), sessions = fetch(TrackedSession.self)
        let spans = ActivityMath.dedupe(acts.map { ActivitySpan(id: $0.id, kind: $0.kind, start: $0.start, end: $0.end, source: $0.source) })

        let wake = profile?.wakeMinute ?? 420, bed = profile?.bedMinute ?? 1380
        let uniDays = Set(profile?.uniDays ?? [])
        var out: [InsightDay] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: .now)) else { continue }
            let w = Day.interval(of: d, calendar: cal)
            let sleep = sleeps.first { cal.isDate($0.day, inSameDayAs: d) }
            let energy = checks.filter { $0.kind == .energy && w.contains($0.at) }.map { Double($0.value) }
            let fatigue = checks.filter { $0.kind == .fatigue && w.contains($0.at) }.map { Double($0.value) }
            let cDay = caffeine.filter { w.contains($0.at) }
            var bedTime = Day.date(d, minutes: bed, calendar: cal)
            if bed <= wake { bedTime = cal.date(byAdding: .day, value: 1, to: bedTime) ?? bedTime }
            let anyLogging = !cDay.isEmpty || meals.contains { w.contains($0.at) } || waters.contains { w.contains($0.at) }
            let late: Bool? = anyLogging ? cDay.contains { Caffeine.isLate($0.at, bedtime: bedTime) } : nil
            let walk = spans.filter { ($0.kind == .walk || $0.kind == .run) && w.contains($0.start) }.reduce(0) { $0 + $1.minutes }
            let trained = acts.contains { $0.kind == .strength && w.contains($0.start) } || workouts.contains { $0.completed && w.contains($0.start) && $0.title.lowercased().contains("full body") }
            let firstMeal = meals.filter { w.contains($0.at) }.map(\.at).min().map { m -> Double in
                let c = cal.dateComponents([.hour, .minute], from: m); return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
            let weekday = cal.component(.weekday, from: d)
            let isUni = uniDays.contains(weekday) || sessions.contains { $0.category == .university && w.contains($0.start) }
            out.append(InsightDay(date: d, sleepHours: sleep?.hours, sleepQuality: sleep?.quality.map(Double.init),
                                  energy: energy.isEmpty ? nil : energy.reduce(0, +) / Double(energy.count),
                                  fatigue: fatigue.isEmpty ? nil : fatigue.max(), lateCaffeine: late, walkMinutes: walk,
                                  trained: trained, firstMealMinute: firstMeal, isUniversityDay: isUni,
                                  workHours: SessionMath.totals(sessions.map(\.value), category: .work, in: w, now: .now).total / 3600))
        }
        return out
    }
}

/// Writes the user's data as one JSON file plus one CSV per table, for backup or analysis elsewhere.
enum DataExporter {
    struct Table { var name: String; var header: [String]; var rows: [[String]] }

    @MainActor
    static func tables(context: ModelContext) -> [Table] {
        func fetch<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let iso = ISO8601DateFormatter()
        func t(_ d: Date) -> String { iso.string(from: d) }
        func n(_ v: Double) -> String { String(format: "%.2f", v) }
        var out: [Table] = []
        out.append(Table(name: "meals", header: ["time", "meal", "item", "grams", "kcal", "protein_g", "carbs_g", "fat_g", "caffeine_mg", "consumed", "verified", "data_source", "entry_source", "original_text"],
            rows: fetch(MealRecord.self).sorted { $0.at < $1.at }.flatMap { m in m.items.map { i in
                [t(m.at), m.mealType.rawValue, i.name, n(i.grams), n(i.nutrition.kcal), n(i.nutrition.proteinG), n(i.nutrition.carbsG), n(i.nutrition.fatG),
                 i.nutrition.caffeineMg.map(n) ?? "", String(i.consumed), String(i.verified), i.dataSource, m.source.rawValue, m.originalText] } }))
        out.append(Table(name: "water", header: ["time", "ml", "source"], rows: fetch(WaterRecord.self).sorted { $0.at < $1.at }.map { [t($0.at), n($0.ml), $0.source.rawValue] }))
        out.append(Table(name: "caffeine", header: ["time", "drink", "mg_each", "count", "mg_source", "source"],
            rows: fetch(CaffeineRecord.self).sorted { $0.at < $1.at }.map { [t($0.at), $0.name, n($0.mg), String($0.count), $0.mgSource, $0.source.rawValue] }))
        out.append(Table(name: "sleep", header: ["wake_day", "asleep", "woke", "hours", "quality", "source"],
            rows: fetch(SleepRecord.self).sorted { $0.day < $1.day }.map { [t($0.day), t($0.asleepAt), t($0.wokeAt), n($0.hours), $0.quality.map(String.init) ?? "", $0.source.rawValue] }))
        out.append(Table(name: "activity", header: ["start", "end", "kind", "steps", "distance_m", "source"],
            rows: fetch(ActivityRecord.self).sorted { $0.start < $1.start }.map { [t($0.start), t($0.end), $0.kind.rawValue, $0.steps.map(String.init) ?? "", $0.distanceM.map(n) ?? "", $0.source.rawValue] }))
        out.append(Table(name: "workouts", header: ["start", "title", "minutes", "completed", "effort"],
            rows: fetch(WorkoutRecord.self).sorted { $0.start < $1.start }.map { [t($0.start), $0.title, String($0.minutes), String($0.completed), $0.perceivedEffort.map(String.init) ?? ""] }))
        out.append(Table(name: "sessions", header: ["category", "start", "end", "status", "source", "breaks", "note"],
            rows: fetch(TrackedSession.self).sorted { $0.start < $1.start }.map { [$0.category.rawValue, t($0.start), $0.end.map(t) ?? "", $0.status.rawValue, $0.source.rawValue, String($0.breaks.count), $0.note] }))
        out.append(Table(name: "checkins", header: ["time", "kind", "value", "note"],
            rows: fetch(CheckIn.self).sorted { $0.at < $1.at }.map { [t($0.at), $0.kind.rawValue, String($0.value), $0.note] }))
        out.append(Table(name: "weight", header: ["time", "kg", "source"], rows: fetch(WeightRecord.self).sorted { $0.at < $1.at }.map { [t($0.at), n($0.kg), $0.source.rawValue] }))
        // Places include coordinates the user chose. Exported because it is their data, and stays on their device.
        out.append(Table(name: "places", header: ["name", "category", "latitude", "longitude", "radius_m", "enabled"],
            rows: fetch(Place.self).map { [$0.name, $0.category.rawValue, String($0.latitude), String($0.longitude), n($0.radiusM), String($0.enabled)] }))
        return out
    }

    /// Copy shown in the Files app under On My iPhone > RE:SET AI. Rewritten whenever the app goes to the background.
    static var filesFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RE-SET Data", isDirectory: true)
    }

    @MainActor
    static func syncToFiles(context: ModelContext) { _ = try? write(context: context, to: filesFolder) }

    /// Returns file URLs ready for ShareLink. Old exports are removed first.
    @MainActor
    static func write(context: ModelContext, to folder: URL? = nil) throws -> [URL] {
        let dir = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent("reset-export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = tables(context: context)
        var urls: [URL] = []
        var json: [String: [[String: String]]] = [:]
        for table in ts {
            let u = dir.appendingPathComponent("\(table.name).csv")
            try CSV.build(header: table.header, rows: table.rows).write(to: u, atomically: true, encoding: .utf8)
            urls.append(u)
            json[table.name] = table.rows.map { Dictionary(uniqueKeysWithValues: zip(table.header, $0)) }
        }
        let ju = dir.appendingPathComponent("reset-export.json")
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: ju, options: .atomic)
        // Encrypted at rest until the first unlock after a restart.
        for u in [dir] + urls + [ju] {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: u.path)
        }
        return [ju] + urls
    }
}
