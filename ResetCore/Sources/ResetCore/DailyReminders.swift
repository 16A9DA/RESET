import Foundation

/// Planners for the lighter reminder categories. All are off by default and respect the waking window.
public enum DailyReminders {
    public static let maxMovementPerDay = 8

    private static func weekday(_ d: Date, _ cal: Calendar) -> Int { cal.component(.weekday, from: d) }

    /// Nudges to stand, walk or stretch during work hours on work days. Spaced `intervalMinutes` apart (45 minimum).
    public static func movement(workStart: Int?, workEnd: Int?, workDays: [Int], intervalMinutes: Int, now: Date,
                                days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        guard let ws = workStart, let we = workEnd, we > ws else { return [] }
        let step = TimeInterval(max(intervalMinutes, 45) * 60)
        var out: [PlannedReminder] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), workDays.contains(weekday(day, calendar)) else { continue }
            let start = Day.date(day, minutes: ws, calendar: calendar), end = Day.date(day, minutes: we, calendar: calendar)
            var t = start.addingTimeInterval(step), n = 0
            while t <= end.addingTimeInterval(-30 * 60), n < maxMovementPerDay {
                if t > now {
                    out.append(PlannedReminder(id: "move.\(Int(t.timeIntervalSince1970))", category: .movement, fireDate: t, title: "Move a little",
                                               body: "A couple of minutes of walking or stretching breaks up a long shift. Skip it if you are already on the move."))
                    n += 1
                }
                t = t.addingTimeInterval(step)
            }
        }
        return out
    }

    /// Time after work for planned exercise reminders. Falls back to late afternoon, and never lands within 3 hours of bed.
    static func afterWork(workEnd: Int?, shape: DayShape, day: Date, offsetMinutes: Int, calendar: Calendar) -> Date? {
        let base = workEnd.map { $0 + offsetMinutes } ?? (17 * 60 + 30)
        let t = Day.date(day, minutes: min(base, 23 * 60), calendar: calendar)
        let w = shape.window(on: day, calendar: calendar)
        return (t > w.start && t < w.end.addingTimeInterval(-3 * 3600)) ? t : nil
    }

    /// A short walk after work. Skipped for today if a walk is already logged.
    public static func walk(shape: DayShape, workEnd: Int?, walkedToday: Bool, minutes: Int = 20, now: Date, days: Int = 2,
                            calendar: Calendar = .current) -> [PlannedReminder] {
        (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), !(offset == 0 && walkedToday),
                  let t = afterWork(workEnd: workEnd, shape: shape, day: day, offsetMinutes: 45, calendar: calendar), t > now else { return nil }
            return PlannedReminder(id: "walk.\(Int(t.timeIntervalSince1970))", category: .walk, fireDate: t, title: "Walk time",
                                   body: "A \(minutes) minute walk now counts as a real session. Start one from the Activity tab.")
        }
    }

    /// Heads up to get ready for a workout, only while the weekly target is not yet met and nothing is logged today.
    public static func workoutPrep(shape: DayShape, workEnd: Int?, sessionsThisWeek: Int, targetPerWeek: Int, doneToday: Bool,
                                   now: Date, days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        guard targetPerWeek > 0, sessionsThisWeek < targetPerWeek else { return [] }
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), !(offset == 0 && doneToday),
                  let t = afterWork(workEnd: workEnd, shape: shape, day: day, offsetMinutes: 15, calendar: calendar), t > now else { return nil }
            return PlannedReminder(id: "workout.\(Int(t.timeIntervalSince1970))", category: .workout, fireDate: t, title: "Workout later?",
                                   body: "Open Today for a workout that fits your recovery. Too tired is a fine reason to walk instead.")
        }
    }

    /// Evening prompt for a quick energy and fatigue check-in when none is logged yet.
    public static func checkIn(shape: DayShape, hasCheckInToday: Bool, now: Date, days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), !(offset == 0 && hasCheckInToday) else { return nil }
            let t = shape.window(on: day, calendar: calendar).end.addingTimeInterval(-2 * 3600)
            guard t > now else { return nil }
            return PlannedReminder(id: "checkin.\(Int(t.timeIntervalSince1970))", category: .checkIn, fireDate: t, title: "Quick check-in",
                                   body: "How is your energy today? Ten seconds helps tomorrow's suggestions.")
        }
    }

    /// Gentle "you have not logged this yet" prompts. Each one only exists while its log is still empty, and the plan
    /// is rebuilt after every log, so logging cancels it. At most three a day.
    public static func missingLogs(shape: DayShape, mealsToday: Int, waterToday: Bool, sleepToday: Bool, now: Date,
                                   days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let w = shape.window(on: day, calendar: calendar)
            let today = offset == 0
            func add(_ key: String, _ t: Date, _ title: String, _ body: String) {
                guard t > now.addingTimeInterval(60), w.contains(t) else { return }
                out.append(PlannedReminder(id: "nolog.\(key).\(Int(t.timeIntervalSince1970))", category: .logNudge, fireDate: t, title: title, body: body))
            }
            if !(today && sleepToday) {
                add("sleep", w.start.addingTimeInterval(90 * 60), "Last night's sleep", "No sleep logged for last night. Open Sleep to add it, or ignore this if you wore nothing to bed.")
            }
            if !(today && mealsToday > 0) {
                add("meal", w.start.addingTimeInterval(w.duration * 0.45), "No food logged yet", "Snap a photo or type what you ate so today's totals stay honest.")
            }
            if !(today && mealsToday >= 2) {
                add("meal2", w.end.addingTimeInterval(-3.5 * 3600), "Log today's meals", "Only \(today ? "\(mealsToday) meal" + (mealsToday == 1 ? "" : "s") : "a few meals") logged so far. Add what you ate before the day ends.")
            }
            if !(today && waterToday) {
                add("water", w.start.addingTimeInterval(w.duration * 0.6), "No water logged", "Nothing logged today. Tap to add a glass.")
            }
        }
        return out
    }
}
