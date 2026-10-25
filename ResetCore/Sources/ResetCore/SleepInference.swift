import Foundation

/// Best guess at last night's sleep for people with no watch or tracker: the longest stretch overnight with no steps.
/// A phone left on the nightstand records nothing, so this is an estimate and is stored as one (`Source.auto`).
public enum SleepInference {
    public static let minHours = 3.5
    public static let maxHours = 12.0
    /// Time to fall asleep after the last movement.
    public static let settle: TimeInterval = 15 * 60

    /// `stepTimes` are start times of short buckets that had steps. Needs data from the evening before.
    public static func lastNight(stepTimes: [Date], now: Date, calendar: Calendar = .current) -> TimeSpan? {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .hour, value: -4, to: today),   // 20:00 yesterday
              let until = calendar.date(byAdding: .hour, value: 12, to: today) else { return nil }
        let times = stepTimes.filter { $0 >= from.addingTimeInterval(-6 * 3600) && $0 <= now }.sorted()
        guard let first = times.first, first <= from.addingTimeInterval(3600) || times.contains(where: { $0 < until && $0 > from }) else { return nil }

        var best: (start: Date, end: Date)?
        for (a, b) in zip(times, times.dropFirst()) {
            // Bucket length is not known here, so the gap is measured between bucket starts.
            let start = a.addingTimeInterval(300), end = b
            guard end > from, start < until, end <= until.addingTimeInterval(4 * 3600) else { continue }
            if end.timeIntervalSince(start) > (best?.end.timeIntervalSince(best!.start) ?? 0) { best = (start, end) }
        }
        guard let g = best else { return nil }
        let span = g.end.timeIntervalSince(g.start)
        guard span >= minHours * 3600, span <= maxHours * 3600 else { return nil }
        return TimeSpan(start: g.start.addingTimeInterval(settle), end: g.end)
    }
}
