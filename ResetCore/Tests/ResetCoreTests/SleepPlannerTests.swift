import Testing
import Foundation
@testable import ResetCore

private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func at(_ h: Int, _ m: Int = 0, day: Int = 10) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}

@Test func bedtimeFromWakeAndTarget() {
    #expect(SleepPlanner.bedtime(wake: at(7), targetHours: 8) == at(22, 45, day: 9))
}

@Test func targetIsClamped() {
    #expect(SleepPlanner.bedtime(wake: at(7), targetHours: 2) == SleepPlanner.bedtime(wake: at(7), targetHours: 5))
}

@Test func windDown() {
    #expect(SleepPlanner.windDownStart(bedtime: at(23), minutes: 45) == at(22, 15))
}

@Test func nightCrossingMidnight() {
    let n = SleepPlanner.night(wakeDay: at(12), asleepMinute: 23 * 60 + 30, wokeMinute: 7 * 60, calendar: cal)
    #expect(n.asleepAt == at(23, 30, day: 9) && n.hours == 7.5)
    let after = SleepPlanner.night(wakeDay: at(12), asleepMinute: 60, wokeMinute: 8 * 60, calendar: cal)
    #expect(after.asleepAt == at(1) && after.hours == 7)
}

@Test func healthSpansMergeIntoNightsAndDropNaps() {
    let spans = [TimeSpan(start: at(23, day: 9), end: at(2)), TimeSpan(start: at(2, 30), end: at(7)),
                 TimeSpan(start: at(14), end: at(14, 40))]
    let n = SleepPlanner.nights(from: spans)
    #expect(n.count == 1 && n[0].start == at(23, day: 9) && n[0].end == at(7))
}

@Test func summaryLabelsAndVariance() {
    let nights = (0..<4).map { SleepNight(asleepAt: at(23, day: 1 + $0), wokeAt: at(5, day: 2 + $0)) } // 6 h
    let s = SleepPlanner.summary(nights, targetHours: 8, calendar: cal)
    #expect(s.averageHours == 6 && s.label.contains("Well under") && s.bedtimeVarianceMin == 0)
    #expect(SleepPlanner.summary([], targetHours: 8).averageHours == nil)
}

@Test func bedtimeVarianceHandlesMidnight() {
    let nights = [SleepNight(asleepAt: at(23, 30), wokeAt: at(7, day: 11)),
                  SleepNight(asleepAt: at(0, 30, day: 12), wokeAt: at(8, day: 12)),
                  SleepNight(asleepAt: at(23, 30, day: 12), wokeAt: at(7, day: 13))]
    let v = SleepPlanner.summary(nights, targetHours: 8, calendar: cal).bedtimeVarianceMin!
    #expect(v < 60) // 23:30 and 00:30 are an hour apart, not 23 hours
}

@Test func remindersCoverBedtimeWindDownAndWake() {
    let shape = DayShape(wakeMinute: 7 * 60, bedMinute: 23 * 60)
    let r = SleepPlanner.reminders(shape: shape, targetHours: 8, windDownMinutes: 45, now: at(12), bedtimeOn: true, wakeOn: true, days: 2, calendar: cal)
    #expect(r.contains { $0.category == .bedtime && $0.fireDate == at(22, 15) })
    #expect(r.contains { $0.category == .wake && $0.fireDate == at(7, day: 11) })
    #expect(r.allSatisfy { $0.fireDate > at(12) })
}

@Test func caffeineReminderEightHoursBeforeBed() {
    let r = SleepPlanner.caffeineReminders(shape: DayShape(wakeMinute: 420, bedMinute: 23 * 60), hoursBefore: 8, now: at(8), calendar: cal)
    #expect(r.first?.fireDate == at(15))
}
