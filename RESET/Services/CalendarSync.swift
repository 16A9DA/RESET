import Foundation
import EventKit
import SwiftData

/// Adds each finished work, university or gym session to the iPhone calendar as one event.
/// Write only access: the app can add events but never reads the calendar.
@MainActor
enum CalendarSync {
    static let enabledKey = "calendar.sync"
    private static let sinceKey = "calendar.since"
    private static let store = EKEventStore()

    /// Asks for permission. Only sessions that finish after this moment are added, so history is not dumped in.
    static func enable() async -> Bool {
        let ok = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        UserDefaults.standard.set(ok, forKey: enabledKey)
        if ok { UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: sinceKey) }
        return ok
    }

    /// Safe to call often. A session gets an event once, then carries its event id.
    static func sync(context: ModelContext) {
        let d = UserDefaults.standard
        guard d.bool(forKey: enabledKey), let calendar = store.defaultCalendarForNewEvents else { return }
        let since = Date(timeIntervalSince1970: d.double(forKey: sinceKey))
        let sessions = (try? context.fetch(FetchDescriptor<TrackedSession>())) ?? []
        for s in sessions where s.calendarEventID == nil && s.status != .needsReview {
            guard let end = s.end, end > since, end.timeIntervalSince(s.start) >= 300 else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = s.category.rawValue.capitalized
            event.startDate = s.start
            event.endDate = end
            event.notes = "Recorded by RE:SET"
            if (try? store.save(event, span: .thisEvent)) != nil { s.calendarEventID = event.eventIdentifier }
        }
        try? context.save()
    }
}
