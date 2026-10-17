import Testing
import Foundation
@testable import ResetCore

private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func at(_ h: Int, _ m: Int = 0, day: Int = 10) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
} // 2026-03-10 is a Tuesday (weekday 3), 2026-03-14 a Saturday (7)
private let shape = DayShape(wakeMinute: 7 * 60, bedMinute: 23 * 60)

@Test func movementOnlyInsideWorkHoursOnWorkDays() {
    let r = DailyReminders.movement(workStart: 9 * 60, workEnd: 17 * 60, workDays: [3], intervalMinutes: 60, now: at(6), days: 2, calendar: cal)
    #expect(!r.isEmpty && r.allSatisfy { $0.fireDate > at(9) && $0.fireDate < at(17) })
    #expect(r.allSatisfy { $0.fireDate < at(0, day: 11) }) // Wednesday is not a work day here
}

@Test func movementIntervalHasAFloor() {
    let r = DailyReminders.movement(workStart: 9 * 60, workEnd: 17 * 60, workDays: [3], intervalMinutes: 5, now: at(6), days: 1, calendar: cal)
    for (a, b) in zip(r, r.dropFirst()) { #expect(b.fireDate.timeIntervalSince(a.fireDate) >= 45 * 60) }
}

@Test func movementNeedsAWorkSchedule() {
    #expect(DailyReminders.movement(workStart: nil, workEnd: nil, workDays: [3], intervalMinutes: 60, now: at(6), calendar: cal).isEmpty)
}

@Test func walkSkippedTodayWhenAlreadyWalked() {
    let r = DailyReminders.walk(shape: shape, workEnd: 17 * 60, walkedToday: true, now: at(8), days: 2, calendar: cal)
    #expect(r.count == 1 && r[0].fireDate == at(17, 45, day: 11))
    let r2 = DailyReminders.walk(shape: shape, workEnd: 17 * 60, walkedToday: false, now: at(8), days: 2, calendar: cal)
    #expect(r2.count == 2 && r2[0].fireDate == at(17, 45))
}

@Test func walkNotLateInTheEvening() {
    #expect(DailyReminders.walk(shape: shape, workEnd: 21 * 60, walkedToday: false, now: at(8), days: 1, calendar: cal).isEmpty)
}

@Test func workoutPrepStopsOnceWeeklyTargetIsMet() {
    #expect(DailyReminders.workoutPrep(shape: shape, workEnd: 17 * 60, sessionsThisWeek: 3, targetPerWeek: 3, doneToday: false, now: at(8), calendar: cal).isEmpty)
    #expect(DailyReminders.workoutPrep(shape: shape, workEnd: 17 * 60, sessionsThisWeek: 1, targetPerWeek: 3, doneToday: false, now: at(8), calendar: cal).count == 2)
    #expect(DailyReminders.workoutPrep(shape: shape, workEnd: 17 * 60, sessionsThisWeek: 1, targetPerWeek: 0, doneToday: false, now: at(8), calendar: cal).isEmpty)
}

@Test func checkInOnlyWhenMissing() {
    #expect(DailyReminders.checkIn(shape: shape, hasCheckInToday: true, now: at(8), days: 1, calendar: cal).isEmpty)
    #expect(DailyReminders.checkIn(shape: shape, hasCheckInToday: false, now: at(8), days: 1, calendar: cal).first?.fireDate == at(21))
    #expect(DailyReminders.checkIn(shape: shape, hasCheckInToday: false, now: at(22), days: 1, calendar: cal).isEmpty)
}

@Test func mealSlotMovesToUsualTime() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    func at(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))! }
    let shape = DayShape(wakeMinute: 7 * 60, bedMinute: 23 * 60)
    let planned = [MealSlot(type: .lunch, time: at(10, 14))]
    let hist = [(at: at(5, 12), type: MealType.lunch), (at: at(6, 12), type: .lunch), (at: at(7, 12), type: .lunch)]
    #expect(MealTiming.learned(planned, history: hist, shape: shape, on: day, calendar: cal).first?.time == at(10, 12))
    #expect(MealTiming.learned(planned, history: Array(hist.prefix(2)), shape: shape, on: day, calendar: cal).first?.time == at(10, 14))
}
