import Foundation
import SwiftData
import ResetCore

extension TrackedSession {
    var value: SessionValue {
        SessionValue(id: id, category: category, placeID: placeID, start: start, end: end, status: status,
                     source: source, breaks: breaks.map { TimeSpan(start: $0.start, end: $0.end) })
    }

    func update(from v: SessionValue) {
        category = v.category; placeID = v.placeID; start = v.start; end = v.end; status = v.status
        source = v.source; breaks = v.breaks.map { BreakInterval(start: $0.start, end: $0.end) }
    }
}

enum SessionStore {
    /// Apply one place event to persisted sessions. Updates changed rows and inserts new ones.
    static func apply(_ event: PlaceEventValue, place: Place, context: ModelContext) {
        let pid = place.id
        let descriptor = FetchDescriptor<TrackedSession>(
            predicate: #Predicate { $0.placeID == pid },
            sortBy: [SortDescriptor(\.start, order: .reverse)])
        var d = descriptor
        d.fetchLimit = 10
        let rows = (try? context.fetch(d)) ?? []
        let before = rows.map(\.value)
        let rule = PlaceRule(id: place.id, category: place.category, breakToleranceMin: place.breakToleranceMin)
        let after = Reconciler.apply(event, rule: rule, to: before)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        for v in after {
            if let row = byID[v.id] {
                if row.value != v { row.update(from: v) }
            } else {
                let s = TrackedSession(category: v.category, placeID: v.placeID, start: v.start, end: v.end,
                                       status: v.status, source: v.source)
                s.id = v.id
                s.breaks = v.breaks.map { BreakInterval(start: $0.start, end: $0.end) }
                context.insert(s)
            }
        }
        try? context.save()
    }

    static func flagStale(context: ModelContext, now: Date = .now) {
        let rows = (try? context.fetch(FetchDescriptor<TrackedSession>())) ?? []
        for row in rows where row.end == nil && row.status != .needsReview && row.source == .auto {
            if let v = Reconciler.flagStale([row.value], now: now).first, v.status != row.status { row.status = v.status }
        }
        try? context.save()
    }

    static func pruneEvents(context: ModelContext, olderThanDays days: Int = 30) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        try? context.delete(model: LocationEvent.self, where: #Predicate { $0.at < cutoff })
    }
}
