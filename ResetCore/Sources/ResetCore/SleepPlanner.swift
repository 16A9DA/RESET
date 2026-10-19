import Foundation

public struct SleepNight: Sendable, Equatable {
    public var asleepAt: Date
    public var wokeAt: Date
    public var quality: Int?
    public var hours: Double { max(0, wokeAt.timeIntervalSince(asleepAt)) / 3600 }
    public init(asleepAt: Date, wokeAt: Date, quality: Int? = nil) {
        self.asleepAt = asleepAt; self.wokeAt = wokeAt; self.quality = quality
    }
}

public struct SleepSummary: Sendable, Equatable {
    public var nights: Int
    public var averageHours: Double?
    /// Average minus target. Negative means short of target.
    public var averageVsTarget: Double?
    /// Standard deviation of bedtime in minutes, nil under three nights.
    public var bedtimeVarianceMin: Double?
    public var label: String
}

public enum SleepPlanner {
    public static let defaultTargetHours = 8.0
    public static let allowedTarget: ClosedRange<Double> = 5...10
    public static let fallAsleepMinutes = 15.0

    /// Bedtime that leaves `targetHours` of sleep opportunity plus time to fall asleep.
    public static func bedtime(wake: Date, targetHours: Double) -> Date {
        let t = min(max(targetHours, allowedTarget.lowerBound), allowedTarget.upperBound)
        return wake.addingTimeInterval(-(t * 3600 + fallAsleepMinutes * 60))
    }

    public static func windDownStart(bedtime: Date, minutes: Int) -> Date {
        bedtime.addingTimeInterval(-Double(minutes) * 60)
    }

    /// Latest comfortable wake time that still lets you reach the first commitment of the day.
    public static func wakeTime(firstCommitment: Date, prepMinutes: Int) -> Date {
        firstCommitment.addingTimeInterval(-Double(prepMinutes) * 60)
    }

    /// Dates for a night entered as clock times. Falling asleep after midnight vs before is decided by order:
    /// if the sleep clock time is later than the wake clock time, sleep began the previous evening.
    public static func night(wakeDay: Date, asleepMinute: Int, wokeMinute: Int, quality: Int? = nil, calendar: Calendar = .current) -> SleepNight {
        let woke = Day.date(wakeDay, minutes: wokeMinute, calendar: calendar)
        var asleep = Day.date(wakeDay, minutes: asleepMinute, calendar: calendar)
        if asleep >= woke { asleep = calendar.date(byAdding: .day, value: -1, to: asleep) ?? asleep.addingTimeInterval(-86_400) }
        return SleepNight(asleepAt: asleep, wokeAt: woke, quality: quality)
    }

    /// Merge raw asleep intervals (for example from Health) into nights. Gaps shorter than `gap` stay one night.
    public static func nights(from spans: [TimeSpan], gap: TimeInterval = 2 * 3600) -> [TimeSpan] {
        var out: [TimeSpan] = []
        for s in spans.sorted(by: { $0.start < $1.start }) where s.end > s.start {
            if let last = out.last, s.start.timeIntervalSince(last.end) <= gap {
                out[out.count - 1].end = max(last.end, s.end)
            } else {
                out.append(s)
            }
        }
        return out.filter { $0.end.timeIntervalSince($0.start) >= 2 * 3600 } // naps are not nights
    }

    /// Seconds actually asleep inside a night: the union of asleep spans, so awake gaps and samples that overlap
    /// (watch and phone both writing) are not counted twice. This is the "time asleep" figure Health shows.
    public static func asleepSeconds(in night: TimeSpan, spans: [TimeSpan]) -> TimeInterval {
        var total: TimeInterval = 0
        var cursor = night.start
        for s in spans.sorted(by: { $0.start < $1.start }) {
            let start = max(s.start, night.start, cursor), end = min(s.end, night.end)
            if end > start { total += end.timeIntervalSince(start); cursor = end }
        }
        return total
    }

    public static func summary(_ nights: [SleepNight], targetHours: Double, calendar: Calendar = .current) -> SleepSummary {
        guard !nights.isEmpty else {
            return SleepSummary(nights: 0, averageHours: nil, averageVsTarget: nil, bedtimeVarianceMin: nil,
                                label: "No sleep recorded yet. Log last night to start.")
        }
        let avg = nights.map(\.hours).reduce(0, +) / Double(nights.count)
        let diff = avg - targetHours
        var variance: Double?
        if nights.count >= 3 {
            // Bedtime as minutes from 18:00 so 23:30 and 00:30 sit close together.
            let mins = nights.map { n -> Double in
                let c = calendar.dateComponents([.hour, .minute], from: n.asleepAt)
                let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
                return m < 18 * 60 ? m + 24 * 60 : m
            }
            let mean = mins.reduce(0, +) / Double(mins.count)
            variance = (mins.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(mins.count)).squareRoot()
        }
        let label: String
        switch diff {
        case ..<(-1.5): label = "Well under your target on average."
        case ..<(-0.5): label = "A bit under your target on average."
        case ..<0.5: label = "Close to your target on average."
        default: label = "Above your target on average."
        }
        return SleepSummary(nights: nights.count, averageHours: avg, averageVsTarget: diff, bedtimeVarianceMin: variance, label: label)
    }

    /// Bedtime, wind-down and wake reminders for the next days.
    public static func reminders(shape: DayShape, targetHours: Double, windDownMinutes: Int, now: Date,
                                 bedtimeOn: Bool, wakeOn: Bool, days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let w = shape.window(on: day, calendar: calendar)
            if bedtimeOn {
                let wind = windDownStart(bedtime: w.end, minutes: windDownMinutes)
                if wind > now {
                    out.append(PlannedReminder(id: "bed.wind.\(Int(wind.timeIntervalSince1970))", category: .bedtime, fireDate: wind,
                                               title: "Wind down", body: "Bedtime is in \(windDownMinutes) minutes. Dim the lights, put the phone down, start winding down."))
                }
                if w.end > now {
                    out.append(PlannedReminder(id: "bed.\(Int(w.end.timeIntervalSince1970))", category: .bedtime, fireDate: w.end,
                                               title: "Bedtime", body: "Good time to head to bed for about \(String(format: "%g", targetHours)) hours of sleep."))
                }
            }
            if wakeOn, w.start > now {
                out.append(PlannedReminder(id: "wake.\(Int(w.start.timeIntervalSince1970))", category: .wake, fireDate: w.start,
                                           title: "Good morning", body: "Log last night's sleep and how you feel. This is a notification, not an alarm. Keep your alarm app."))
            }
        }
        return out
    }

    /// Reminder to stop caffeine, at the cutoff before the coming bedtime.
    public static func caffeineReminders(shape: DayShape, hoursBefore: Double, now: Date, days: Int = 2, calendar: Calendar = .current) -> [PlannedReminder] {
        (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            let cutoff = Caffeine.cutoff(bedtime: shape.window(on: day, calendar: calendar).end, hoursBefore: hoursBefore)
            guard cutoff > now else { return nil }
            return PlannedReminder(id: "caffeine.\(Int(cutoff.timeIntervalSince1970))", category: .caffeine, fireDate: cutoff,
                                   title: "Caffeine cutoff", body: "Caffeine this late can cost you sleep. Water or decaf instead?")
        }
    }
}
