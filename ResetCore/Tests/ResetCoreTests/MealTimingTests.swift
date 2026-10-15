import Testing
import Foundation
@testable import ResetCore

private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func at(_ h: Int, _ m: Int = 0, day: Int = 10) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}
private let shape = DayShape(wakeMinute: 7 * 60, bedMinute: 23 * 60)

@Test func threeMealsSpreadAcrossDay() {
    let s = MealTiming.slots(pattern: [.breakfast, .lunch, .dinner], shape: shape, on: at(7), calendar: cal)
    #expect(s.map(\.type) == [.breakfast, .lunch, .dinner])
    #expect(s[0].time == at(8) && s[2].time == at(20))
    #expect(s[1].time == at(14))
}

@Test func skippingBreakfastIsRespected() {
    let s = MealTiming.slots(pattern: [.lunch, .dinner], shape: shape, on: at(7), calendar: cal)
    #expect(s.count == 2 && s[0].type == .lunch && s[0].time == at(8))
}

@Test func snackGoesInLargestGap() {
    let s = MealTiming.slots(pattern: [.breakfast, .lunch, .dinner, .snack], shape: shape, on: at(7), calendar: cal)
    #expect(s.count == 4)
    let snack = s.first { $0.type == .snack }!
    #expect(snack.time > at(14) && snack.time < at(23))
}

@Test func emptyPatternGivesNoSlots() {
    #expect(MealTiming.slots(pattern: [], shape: shape, on: at(7), calendar: cal).isEmpty)
}

@Test func loggedMealSuppressesReminder() {
    let slots = MealTiming.slots(pattern: [.breakfast, .lunch, .dinner], shape: shape, on: at(7), calendar: cal)
    let r = MealTiming.mealReminders(slots: slots, logsToday: [(at(13, 30), .lunch)], now: at(7), quietUntil: nil)
    #expect(r.count == 2 && !r.contains { $0.id.contains("lunch") })
}

@Test func quietModeSuppressesEarlyReminders() {
    let slots = MealTiming.slots(pattern: [.breakfast, .lunch, .dinner], shape: shape, on: at(7), calendar: cal)
    let r = MealTiming.mealReminders(slots: slots, logsToday: [], now: at(7), quietUntil: at(15))
    #expect(r.count == 1 && r[0].id.contains("dinner"))
}

@Test func hungerCheckAsksAfterFiveHours() {
    let r = MealTiming.hungerCheck(lastMeal: at(9), shape: shape, now: at(10), quietUntil: nil, calendar: cal)
    #expect(r?.fireDate == at(14) && r?.title == "Have you eaten recently?")
}

@Test func hungerCheckDoesNotFireLateInTheEvening() {
    #expect(MealTiming.hungerCheck(lastMeal: at(17), shape: shape, now: at(18), quietUntil: nil, calendar: cal) == nil)
}

@Test func eveningSummaryIsNeutral() {
    let none = MealTiming.eveningSummary(kcal: 0, proteinG: 0, targetKcal: 2000, targetProtein: 150, mealsLogged: 0)
    #expect(none.contains("okay") && !none.lowercased().contains("failed"))
    let low = MealTiming.eveningSummary(kcal: 900, proteinG: 40, targetKcal: 2000, targetProtein: 150, mealsLogged: 2)
    #expect(low.contains("may be that some food was not logged"))
}
