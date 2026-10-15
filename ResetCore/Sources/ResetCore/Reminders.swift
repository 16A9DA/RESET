import Foundation

public enum ReminderCategory: String, Codable, Sendable, CaseIterable {
    case water, meal, bedtime, wake, caffeine, movement, walk, workout, checkIn

    public var title: String {
        switch self {
        case .water: "Water"
        case .meal: "Meals"
        case .bedtime: "Bedtime"
        case .wake: "Wake up"
        case .caffeine: "Late caffeine"
        case .movement: "Movement breaks"
        case .walk: "Planned walk"
        case .workout: "Workout prep"
        case .checkIn: "Daily check-in"
        }
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public var id: String
    public var category: ReminderCategory
    public var fireDate: Date
    public var title: String
    public var body: String
    public init(id: String, category: ReminderCategory, fireDate: Date, title: String, body: String) {
        self.id = id; self.category = category; self.fireDate = fireDate; self.title = title; self.body = body
    }
}

/// The user's day as the planners need it.
public struct DayShape: Sendable {
    public var wakeMinute: Int
    public var bedMinute: Int
    public init(wakeMinute: Int, bedMinute: Int) { self.wakeMinute = wakeMinute; self.bedMinute = bedMinute }

    /// Waking window for the calendar day containing `day`. A bedtime earlier than wake time means after midnight.
    public func window(on day: Date, calendar: Calendar = .current) -> DateInterval {
        let start = Day.date(day, minutes: wakeMinute, calendar: calendar)
        var end = Day.date(day, minutes: bedMinute, calendar: calendar)
        if bedMinute <= wakeMinute { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return DateInterval(start: start, end: max(end, start))
    }
}

public enum Hydration {
    public static let quickDefaults = [150, 250, 500]
    public static let minGapMinutes = 90
    /// Never remind more than this many times a day.
    public static let maxPerDay = 8

    public static func progress(totalMl: Double, goalMl: Double?) -> Double? {
        guard let g = goalMl, g > 0 else { return nil }
        return totalMl / g
    }

    /// Water reminder times inside the waking window, `intervalMinutes` apart. Only future times are returned.
    /// Nothing is scheduled in the first hour after waking or the last hour before bed. A recent log pushes the next
    /// reminder out instead of nagging. Overdue reminders are not back-filled.
    public static func waterReminders(shape: DayShape, now: Date, lastDrink: Date?, todayMl: Double, goalMl: Double?,
                                      intervalMinutes: Int = 120, days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        let interval = TimeInterval(max(intervalMinutes, minGapMinutes) * 60)
        var out: [PlannedReminder] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let w = shape.window(on: day, calendar: calendar)
            var t = w.start.addingTimeInterval(3600 + interval / 2)
            let last = w.end.addingTimeInterval(-3600)
            var count = 0
            while t <= last, count < maxPerDay {
                var fire = t
                // Respect a recent drink: wait a full interval after it.
                if offset == 0, let lastDrink, fire < lastDrink.addingTimeInterval(interval) { fire = lastDrink.addingTimeInterval(interval) }
                if fire > now, fire <= last, !(offset == 0 && goalReached(todayMl, goalMl)) {
                    if out.last.map({ fire.timeIntervalSince($0.fireDate) >= interval }) ?? true {
                        out.append(PlannedReminder(id: "water.\(Int(fire.timeIntervalSince1970))", category: .water, fireDate: fire,
                                                   title: "Water", body: "A glass of water? Tap to log it."))
                        count += 1
                    }
                }
                t = t.addingTimeInterval(interval)
            }
        }
        return out
    }

    static func goalReached(_ ml: Double, _ goal: Double?) -> Bool { goal.map { ml >= $0 } ?? false }

    /// Reminder to replace fluid after hard or sweaty activity. No fixed amount.
    public static func afterStrenuous(minutes: Int, at end: Date) -> PlannedReminder? {
        guard minutes >= 30 else { return nil }
        return PlannedReminder(id: "water.after.\(Int(end.timeIntervalSince1970))", category: .water,
                               fireDate: end.addingTimeInterval(15 * 60), title: "Water after your workout",
                               body: "If you sweated a lot, drink to thirst and consider adding a salty snack. Sip, don't chug.")
    }

    /// Plain-language note shown with the goal.
    public static let goalNote = "A starting point based on body weight. Needs vary with heat, activity and health. If a clinician has limited your fluids, follow their advice instead."
}
