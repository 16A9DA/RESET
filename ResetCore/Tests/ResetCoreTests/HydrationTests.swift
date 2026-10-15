import Testing
import Foundation
@testable import ResetCore

private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func at(_ h: Int, _ m: Int = 0, day: Int = 10) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}
private let shape = DayShape(wakeMinute: 7 * 60, bedMinute: 23 * 60)

@Test func remindersStayInsideWakingWindow() {
    let r = Hydration.waterReminders(shape: shape, now: at(6), lastDrink: nil, todayMl: 0, goalMl: 3000, calendar: cal)
    #expect(!r.isEmpty)
    let w = shape.window(on: at(6), calendar: cal)
    for x in r.filter({ $0.fireDate < at(0, day: 11) }) {
        #expect(x.fireDate > w.start.addingTimeInterval(3600) && x.fireDate < w.end.addingTimeInterval(-3600))
    }
}

@Test func remindersRespectMinimumGapAndDailyCap() {
    let r = Hydration.waterReminders(shape: shape, now: at(6), lastDrink: nil, todayMl: 0, goalMl: 3000, intervalMinutes: 10, calendar: cal)
    for (a, b) in zip(r, r.dropFirst()) { #expect(b.fireDate.timeIntervalSince(a.fireDate) >= 90 * 60) }
    #expect(r.filter { $0.fireDate < at(0, day: 11) }.count <= Hydration.maxPerDay)
}

@Test func pastTimesAreNotBackfilled() {
    let r = Hydration.waterReminders(shape: shape, now: at(18), lastDrink: nil, todayMl: 0, goalMl: 3000, calendar: cal)
    #expect(r.allSatisfy { $0.fireDate > at(18) })
}

@Test func recentDrinkPushesNextReminderOut() {
    let r = Hydration.waterReminders(shape: shape, now: at(12), lastDrink: at(12), todayMl: 250, goalMl: 3000, intervalMinutes: 120, calendar: cal)
    #expect(r.first!.fireDate >= at(14))
}

@Test func goalReachedStopsTodayButNotTomorrow() {
    let r = Hydration.waterReminders(shape: shape, now: at(12), lastDrink: nil, todayMl: 3000, goalMl: 3000, calendar: cal)
    #expect(r.allSatisfy { $0.fireDate >= at(0, day: 11) })
    #expect(!r.isEmpty)
}

@Test func lateBedtimePastMidnight() {
    let late = DayShape(wakeMinute: 9 * 60, bedMinute: 1 * 60)
    let w = late.window(on: at(12), calendar: cal)
    #expect(w.end == at(1, day: 11))
}

@Test func progressNilWithoutGoal() {
    #expect(Hydration.progress(totalMl: 500, goalMl: nil) == nil)
    #expect(Hydration.progress(totalMl: 500, goalMl: 2000) == 0.25)
}

@Test func afterStrenuousOnlyForLongSessions() {
    #expect(Hydration.afterStrenuous(minutes: 20, at: at(10)) == nil)
    #expect(Hydration.afterStrenuous(minutes: 45, at: at(10))?.fireDate == at(10, 15))
}
