import Foundation

public struct TimeSpan: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

public struct SessionValue: Hashable, Sendable {
    public var id: UUID
    public var category: SessionCategory
    public var placeID: UUID?
    public var start: Date
    /// Nil while open.
    public var end: Date?
    public var status: SessionStatus
    public var source: Source
    public var breaks: [TimeSpan]

    public init(id: UUID = UUID(), category: SessionCategory, placeID: UUID? = nil, start: Date, end: Date? = nil,
                status: SessionStatus = .estimatedPresence, source: Source = .auto, breaks: [TimeSpan] = []) {
        self.id = id; self.category = category; self.placeID = placeID; self.start = start; self.end = end
        self.status = status; self.source = source; self.breaks = breaks
    }
}

public struct PlaceEventValue: Sendable {
    public var placeID: UUID
    public var transition: PlaceTransition
    public var at: Date
    public init(placeID: UUID, transition: PlaceTransition, at: Date) {
        self.placeID = placeID; self.transition = transition; self.at = at
    }
}

public struct PlaceRule: Sendable {
    public var id: UUID
    public var category: SessionCategory
    public var breakToleranceMin: Int
    public init(id: UUID, category: SessionCategory, breakToleranceMin: Int = 20) {
        self.id = id; self.category = category; self.breakToleranceMin = breakToleranceMin
    }
}

public enum Reconciler {
    /// Repeated events for the same place and transition closer than this are one event.
    public static let duplicateWindow: TimeInterval = 120
    /// An open session older than this is assumed to have a missed exit and needs review.
    public static let maxOpen: TimeInterval = 14 * 3600

    /// Apply one geofence event to the sessions of that place. Returns the full updated list.
    /// Pure and order-independent of storage so it is easy to test. Nothing is dropped: odd cases become needsReview.
    public static func apply(_ event: PlaceEventValue, rule: PlaceRule, to sessions: [SessionValue]) -> [SessionValue] {
        var out = sessions
        let mine = out.indices.filter { out[$0].placeID == rule.id && out[$0].source == .auto }
        let open = mine.first { out[$0].end == nil && out[$0].status != .needsReview }

        switch event.transition {
        case .enter:
            if let i = open {
                if event.at.timeIntervalSince(out[i].start) < maxOpen { return out } // duplicate enter
                out[i].status = .needsReview // enter after a very long open session: exit was missed
            }

            let tolerance = TimeInterval(rule.breakToleranceMin * 60)
            let recent = mine
                .filter { out[$0].end != nil && out[$0].status != .needsReview }
                .max { out[$0].end! < out[$1].end! }
            if let r = recent, let end = out[r].end,
               event.at >= end, event.at.timeIntervalSince(end) <= tolerance {
                out[r].breaks.append(TimeSpan(start: end, end: event.at))
                out[r].end = nil
            } else {
                out.append(SessionValue(category: rule.category, placeID: rule.id, start: event.at))
            }

        case .exit:
            if let i = open {
                if event.at < out[i].start { out[i].status = .needsReview } else { out[i].end = event.at }
            } else if mine.contains(where: { out[$0].end.map { abs($0.timeIntervalSince(event.at)) <= duplicateWindow } ?? false }) {
                return out // duplicate exit
            } else {
                // Exit with no arrival (missed enter). Keep it visible for review.
                out.append(SessionValue(category: rule.category, placeID: rule.id, start: event.at, end: event.at,
                                        status: .needsReview))
            }
        }
        return out
    }

    /// Marks stale open sessions as needing review. Call on launch and when the app returns to foreground.
    public static func flagStale(_ sessions: [SessionValue], now: Date) -> [SessionValue] {
        sessions.map { s in
            var s = s
            if s.end == nil, s.status != .needsReview, now.timeIntervalSince(s.start) > maxOpen { s.status = .needsReview }
            return s
        }
    }
}

public struct SessionTotals: Equatable, Sendable {
    public var confirmed: TimeInterval = 0
    public var estimated: TimeInterval = 0
    public var needsReviewCount = 0
    public var total: TimeInterval { confirmed + estimated }
}

public enum SessionMath {
    /// Seconds of a session inside `window`, minus breaks. Open sessions run to `now`. Stale or unresolved sessions give 0.
    public static func seconds(_ s: SessionValue, in window: DateInterval, now: Date) -> TimeInterval {
        if s.status == .needsReview && s.end == nil { return 0 }
        let end = s.end ?? min(now, s.start.addingTimeInterval(Reconciler.maxOpen))
        guard end > s.start else { return 0 }
        func overlap(_ a: Date, _ b: Date) -> TimeInterval {
            max(0, min(b, window.end).timeIntervalSince(max(a, window.start)))
        }
        let gross = overlap(s.start, end)
        let brk = s.breaks.reduce(0) { $0 + overlap($1.start, $1.end) }
        return max(0, gross - brk)
    }

    public static func totals(_ sessions: [SessionValue], category: SessionCategory, in window: DateInterval,
                              now: Date) -> SessionTotals {
        var t = SessionTotals()
        for s in sessions where s.category == category {
            if s.status == .needsReview { t.needsReviewCount += 1 }
            let sec = seconds(s, in: window, now: now)
            if s.status == .confirmed || s.source == .manual { t.confirmed += sec } else { t.estimated += sec }
        }
        return t
    }

    public static func week(of date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? Day.interval(of: date, calendar: calendar)
    }

    public static func month(of date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? Day.interval(of: date, calendar: calendar)
    }
}
