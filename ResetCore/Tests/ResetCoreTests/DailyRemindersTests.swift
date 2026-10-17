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

private func food(_ name: String, kcal: Double, caffeine: Double? = nil) -> FoodItem {
    FoodItem(name: name, grams: 100, nutrition: Nutrition(kcal: kcal, proteinG: 5, carbsG: 10, fatG: 5, caffeineMg: caffeine),
             dataSource: "test", verified: true, confidence: .high)
}

@Test func eatCheckVerdicts() {
    #expect(EatCheck.verdict(items: [food("rice", kcal: 300)], remainingKcal: 800, caffeineTodayMg: 0, hoursToBed: 10, allergies: []).level == .yes)
    #expect(EatCheck.verdict(items: [food("cake", kcal: 900)], remainingKcal: 300, caffeineTodayMg: 0, hoursToBed: 10, allergies: []).level == .maybe)
    #expect(EatCheck.verdict(items: [food("peanut bar", kcal: 100)], remainingKcal: 800, caffeineTodayMg: 0, hoursToBed: 10, allergies: ["Peanut"]).level == .no)
    #expect(EatCheck.verdict(items: [food("cola", kcal: 100, caffeine: 40)], remainingKcal: 800, caffeineTodayMg: 0, hoursToBed: 4, allergies: []).level == .maybe)
}

@Test func missedWorkoutAdvice() {
    let under = MissedWorkout.advice(consumedKcal: 1500, targetKcal: 2000, weightKg: 100, mealsLogged: 3, steps: 8000)
    #expect(under.eatLessKcal == 0 && under.walkMinutes == 15)
    let over = MissedWorkout.advice(consumedKcal: 2300, targetKcal: 2000, weightKg: 100, mealsLogged: 3, steps: nil)
    #expect(over.walkMinutes == 50 && over.eatLessKcal == 0) // 300 kcal at about 6.1 kcal/min
    let big = MissedWorkout.advice(consumedKcal: 3500, targetKcal: 2000, weightKg: 100, mealsLogged: 3, steps: nil)
    #expect(big.walkMinutes <= 45 && big.eatLessKcal <= 300 && big.eatLessKcal > 0)
    #expect(MissedWorkout.advice(consumedKcal: 0, targetKcal: 2000, weightKg: 80, mealsLogged: 0, steps: 1000).walkMinutes == 30)
}

@Test func macroCoachAdvice() {
    let carby = Nutrition(kcal: 800, proteinG: 25, carbsG: 130, fatG: 20)
    let a = MacroCoach.advise(consumed: carby, targetKcal: 2400, targetProteinG: 165, weightKg: 100, hour: 13, mealsLogged: 2)
    #expect(a?.headline.contains("Carb heavy") == true)
    #expect(a?.nextMealProteinG == 40) // 0.4 g/kg
    let fatty = Nutrition(kcal: 900, proteinG: 60, carbsG: 40, fatG: 70)
    #expect(MacroCoach.advise(consumed: fatty, targetKcal: 2400, targetProteinG: 165, weightKg: 100, hour: 12, mealsLogged: 2)?.headline.contains("Fat") == true)
    let over = Nutrition(kcal: 2600, proteinG: 150, carbsG: 250, fatG: 80)
    #expect(MacroCoach.advise(consumed: over, targetKcal: 2400, targetProteinG: 165, weightKg: 100, hour: 20, mealsLogged: 4)?.headline.contains("Past") == true)
    #expect(MacroCoach.advise(consumed: .zero, targetKcal: 2400, targetProteinG: 165, weightKg: 100, hour: 12, mealsLogged: 0) == nil)
}
