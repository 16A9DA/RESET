import Testing
import Foundation
@testable import ResetCore

private let place = UUID()
private let rule = PlaceRule(id: place, category: .work, breakToleranceMin: 20)
private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func t(_ h: Int, _ m: Int = 0, day: Int = 1) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}
private func ev(_ tr: PlaceTransition, _ at: Date) -> PlaceEventValue { .init(placeID: place, transition: tr, at: at) }
private func run(_ events: [PlaceEventValue]) -> [SessionValue] {
    events.reduce([]) { Reconciler.apply($1, rule: rule, to: $0) }
}

@Test func simpleDay() {
    let s = run([ev(.enter, t(9)), ev(.exit, t(17))])
    #expect(s.count == 1 && s[0].end == t(17))
    let tot = SessionMath.totals(s, category: .work, in: Day.interval(of: t(9), calendar: cal), now: t(18))
    #expect(tot.estimated == 8 * 3600 && tot.confirmed == 0)
}

@Test func lunchBreakWithinToleranceMerges() {
    let s = run([ev(.enter, t(9)), ev(.exit, t(12)), ev(.enter, t(12, 15)), ev(.exit, t(17))])
    #expect(s.count == 1)
    #expect(s[0].breaks == [TimeSpan(start: t(12), end: t(12, 15))])
    let tot = SessionMath.totals(s, category: .work, in: Day.interval(of: t(9), calendar: cal), now: t(18))
    #expect(tot.total == 8 * 3600 - 15 * 60)
}

@Test func longGapIsNewSession() {
    let s = run([ev(.enter, t(9)), ev(.exit, t(12)), ev(.enter, t(13)), ev(.exit, t(17))])
    #expect(s.count == 2)
}

@Test func duplicateEventsIgnored() {
    let s = run([ev(.enter, t(9)), ev(.enter, t(9, 1)), ev(.exit, t(17)), ev(.exit, t(17, 1))])
    #expect(s.count == 1 && s[0].end == t(17))
}

@Test func missedExitFlaggedNotDiscarded() {
    var s = run([ev(.enter, t(9))])
    s = Reconciler.flagStale(s, now: t(9, day: 2))
    #expect(s.count == 1 && s[0].status == .needsReview)
    let tot = SessionMath.totals(s, category: .work, in: Day.interval(of: t(9), calendar: cal), now: t(9, day: 2))
    #expect(tot.total == 0 && tot.needsReviewCount == 1)
}

@Test func enterAfterVeryLongOpenKeepsBoth() {
    let s = run([ev(.enter, t(9)), ev(.enter, t(9, day: 2))])
    #expect(s.count == 2)
    #expect(s.filter { $0.status == .needsReview }.count == 1)
}

@Test func orphanExitKeptForReview() {
    let s = run([ev(.exit, t(17))])
    #expect(s.count == 1 && s[0].status == .needsReview)
}

@Test func openSessionCountsUpToNow() {
    let s = run([ev(.enter, t(9))])
    let tot = SessionMath.totals(s, category: .work, in: Day.interval(of: t(9), calendar: cal), now: t(11))
    #expect(tot.total == 2 * 3600)
}

@Test func midnightSessionSplitsAcrossDays() {
    let s = [SessionValue(category: .work, start: t(22), end: t(6, day: 2))]
    let d1 = SessionMath.seconds(s[0], in: Day.interval(of: t(12), calendar: cal), now: t(12, day: 3))
    let d2 = SessionMath.seconds(s[0], in: Day.interval(of: t(12, day: 2), calendar: cal), now: t(12, day: 3))
    #expect(d1 == 2 * 3600 && d2 == 6 * 3600)
}

@Test func manualCountsAsConfirmed() {
    let s = [SessionValue(category: .university, start: t(10), end: t(12), source: .manual)]
    let tot = SessionMath.totals(s, category: .university, in: Day.interval(of: t(10), calendar: cal), now: t(13))
    #expect(tot.confirmed == 2 * 3600 && tot.estimated == 0)
}

@Test func weekAndMonthWindows() {
    let s = [SessionValue(category: .work, start: t(9), end: t(17), status: .confirmed),
             SessionValue(category: .work, start: t(9, day: 20), end: t(17, day: 20), status: .confirmed)]
    let m = SessionMath.totals(s, category: .work, in: SessionMath.month(of: t(9), calendar: cal), now: t(9, day: 25))
    #expect(m.confirmed == 16 * 3600)
}
