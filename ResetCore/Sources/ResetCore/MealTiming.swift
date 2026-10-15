import Foundation

public struct MealSlot: Equatable, Sendable {
    public var type: MealType
    public var time: Date
}

public enum MealTiming {
    /// Gap without a logged meal, during waking hours, before the app gently asks.
    public static let askAfterHours = 5.0
    /// Last big meal ends this long before bed. Snacks are exempt.
    public static let dinnerBeforeBedHours = 3.0

    /// Suggested meal times inside the waking window for the chosen pattern. Patterns are the user's choice:
    /// skipping breakfast, two meals, or extra snacks are all fine.
    public static func slots(pattern: [MealType], shape: DayShape, on day: Date, calendar: Calendar = .current) -> [MealSlot] {
        let w = shape.window(on: day, calendar: calendar)
        let wake = w.start, bed = w.end
        let meals = pattern.filter { $0 != .snack }
        let snacks = pattern.filter { $0 == .snack }.count
        guard !meals.isEmpty || snacks > 0 else { return [] }

        let first = wake.addingTimeInterval(3600) // an hour after waking
        let last = bed.addingTimeInterval(-dinnerBeforeBedHours * 3600)
        var out: [MealSlot] = []
        if !meals.isEmpty {
            let span = max(last.timeIntervalSince(first), 3600)
            for (i, m) in meals.enumerated() {
                let f = meals.count == 1 ? 0.5 : Double(i) / Double(meals.count - 1)
                out.append(MealSlot(type: m, time: first.addingTimeInterval(span * f)))
            }
        }
        // Snacks sit in the largest gap between planned meals.
        for _ in 0..<snacks {
            let marks = ([wake] + out.map(\.time) + [bed]).sorted()
            // <= makes the later gap win a tie, so the default snack lands mid afternoon rather than mid morning.
            if let (a, b) = zip(marks, marks.dropFirst()).max(by: { $0.1.timeIntervalSince($0.0) <= $1.1.timeIntervalSince($1.0) }) {
                out.append(MealSlot(type: .snack, time: a.addingTimeInterval(b.timeIntervalSince(a) / 2)))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// A slot counts as covered when any meal was logged near it, or one of the same type was logged that day.
    public static func isCovered(_ slot: MealSlot, logs: [(at: Date, type: MealType)], window: TimeInterval = 90 * 60) -> Bool {
        logs.contains { abs($0.at.timeIntervalSince(slot.time)) <= window || $0.type == slot.type }
    }

    /// One reminder per uncovered future slot, 10 minutes ahead. Wording makes skipping fine.
    public static func mealReminders(slots: [MealSlot], logsToday: [(at: Date, type: MealType)], now: Date, quietUntil: Date?) -> [PlannedReminder] {
        slots.compactMap { s in
            let fire = s.time.addingTimeInterval(-10 * 60)
            guard fire > now, !isCovered(s, logs: logsToday), fire > (quietUntil ?? .distantPast) else { return nil }
            let body = s.type == .snack ? "Hungry? A snack with protein can help. Skip it if you are not."
                : "Around \(s.type.rawValue) time. Log it when you eat, or ignore this if your day is different."
            return PlannedReminder(id: "meal.\(s.type.rawValue).\(Int(s.time.timeIntervalSince1970))", category: .meal, fireDate: fire,
                                   title: "\(s.type.rawValue.capitalized)?", body: body)
        }
    }

    /// "Have you eaten recently?" Only asks, never assumes. Fires `askAfterHours` after the last log (or waking),
    /// and only if that is inside the waking window with at least two hours to spare before bed.
    public static func hungerCheck(lastMeal: Date?, shape: DayShape, now: Date, quietUntil: Date?, calendar: Calendar = .current) -> PlannedReminder? {
        let w = shape.window(on: now, calendar: calendar)
        let anchor = max(lastMeal ?? w.start, w.start)
        let fire = max(anchor.addingTimeInterval(askAfterHours * 3600), now.addingTimeInterval(60))
        guard fire < w.end.addingTimeInterval(-2 * 3600), fire > (quietUntil ?? .distantPast), w.contains(fire) else { return nil }
        return PlannedReminder(id: "meal.check.\(Int(fire.timeIntervalSince1970))", category: .meal, fireDate: fire,
                               title: "Have you eaten recently?",
                               body: "No log for a while. That may just mean you did not log. Log a meal, or tell me you are fine.")
    }

    /// Fuel idea around a workout. Timing windows are loose, not rules.
    public static func workoutFuel(kind: ActivityKind, minutesUntil: Int?) -> String {
        switch kind {
        case .strength:
            if let m = minutesUntil, m > 0, m <= 120 { return "Before: something light with carbs and some protein, like yogurt and fruit, if it sits well. Training fasted is fine too." }
            return "After: a meal with protein and carbs within a few hours works well. There is no strict window."
        case .run, .walk:
            return "Easy sessions rarely need special fuel. Drink to thirst, and eat normally afterwards."
        default:
            return "No special fuel needed. Normal meals are enough."
        }
    }

    /// Neutral end-of-day note. Incomplete logging is acknowledged, no shaming.
    public static func eveningSummary(kcal: Double, proteinG: Double, targetKcal: Double?, targetProtein: Double, mealsLogged: Int) -> String {
        if mealsLogged == 0 {
            return "Nothing logged today. If you ate, a quick log of the main meals helps tomorrow's suggestions. If you did not track, that is okay."
        }
        var parts = ["You logged \(mealsLogged) meal\(mealsLogged == 1 ? "" : "s") with about \(Int(kcal.rounded())) kcal and \(Int(proteinG.rounded())) g protein."]
        if let t = targetKcal {
            let r = kcal / t
            if r < 0.6 { parts.append("That looks low against your \(Int(t.rounded())) kcal guide. It may be that some food was not logged. If it was a short day, eat something filling and protein rich before bed if you are hungry.") }
            else if r <= 1.1 { parts.append("That is close to your guide of about \(Int(t.rounded())) kcal.") }
            else { parts.append("That is above your guide of about \(Int(t.rounded())) kcal. One day does not change a trend.") }
        }
        if proteinG < targetProtein * 0.7 { parts.append("Protein is on the low side. Tomorrow, anchor each meal with a protein source.") }
        return parts.joined(separator: " ")
    }
}
