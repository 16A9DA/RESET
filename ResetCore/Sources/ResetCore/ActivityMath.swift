import Foundation

public struct ActivitySpan: Hashable, Sendable {
    public var id: UUID
    public var kind: ActivityKind
    public var start: Date
    public var end: Date
    public var source: Source
    public var steps: Int?

    public init(id: UUID = UUID(), kind: ActivityKind, start: Date, end: Date, source: Source, steps: Int? = nil) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.source = source; self.steps = steps
    }

    public var minutes: Double { max(0, end.timeIntervalSince(start)) / 60 }
}

public enum ActivityMath {
    /// Same movement reported twice (for example a walk timed in the app and the same walk imported from Health)
    /// must count once. Higher ranked source wins when two spans overlap by more than half of the shorter one.
    private static func rank(_ s: Source) -> Int {
        switch s { case .imported: 3; case .confirmed: 3; case .manual: 2; case .auto: 1; case .aiEstimate: 0 }
    }

    public static func dedupe(_ spans: [ActivitySpan]) -> [ActivitySpan] {
        let sorted = spans.sorted { (rank($0.source), $0.start) > (rank($1.source), $1.start) }
        var kept: [ActivitySpan] = []
        for s in sorted {
            let dup = kept.contains { k in
                let overlap = min(k.end, s.end).timeIntervalSince(max(k.start, s.start))
                let shorter = min(k.end.timeIntervalSince(k.start), s.end.timeIntervalSince(s.start))
                return shorter > 0 && overlap / shorter > 0.5
            }
            if !dup { kept.append(s) }
        }
        return kept.sorted { $0.start < $1.start }
    }

    /// Structured movement only (walks, runs, training). Occupational standing is not included.
    public static func structuredMinutes(_ spans: [ActivitySpan], in window: DateInterval) -> Double {
        dedupe(spans).reduce(0) { total, s in
            let o = min(s.end, window.end).timeIntervalSince(max(s.start, window.start))
            return total + max(0, o) / 60
        }
    }

    /// Steps for a day: prefer the system total. Steps from timed walks are already inside it, so they are never added on top.
    public static func dailySteps(system: Int?, fallbackFromSpans spans: [ActivitySpan]) -> Int? {
        if let system { return system }
        let s = spans.compactMap(\.steps)
        return s.isEmpty ? nil : s.reduce(0, +)
    }
}
