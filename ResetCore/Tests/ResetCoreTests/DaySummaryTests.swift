import Testing
import Foundation
@testable import ResetCore

private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func at(_ h: Int, _ m: Int = 0, day: Int = 10) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}
private func summary(_ band: RecoveryBand, work: Double? = nil, sleep: Double? = 7, water: Double = 0) -> DaySummary {
    DaySummary(date: at(12), sleepHours: sleep, waterMl: water, waterGoalMl: 3000, workSeconds: work, recoveryBand: band)
}

@Test func demandingWorkdayMessageMatchesSpecExample() {
    let m = Priority.message(summary(.low, work: 10 * 3600), symptoms: false, hour: 20)
    #expect(m == "Your priority today: recover from a demanding workday and get enough sleep.")
}

@Test func symptomsBeatEverything() {
    #expect(Priority.message(summary(.good), symptoms: true, hour: 9).contains("rest"))
}

@Test func unknownAsksForCheckIn() {
    #expect(Priority.message(summary(.unknown), symptoms: false, hour: 9).contains("check-in"))
}

@Test func lowWaterAfternoonNudges() {
    #expect(Priority.message(summary(.good, water: 500), symptoms: false, hour: 16).contains("water"))
    #expect(!Priority.message(summary(.good, water: 500), symptoms: false, hour: 10).contains("water"))
}

@Test func defaultMessageIsBasics() {
    var s = summary(.moderate, water: 2000); s.workouts = ["x"]
    #expect(Priority.message(s, symptoms: false, hour: 10).contains("basics"))
}

@Test func originMapping() {
    #expect(Origin.from(.auto) == .automatic && Origin.from(.imported) == .imported)
    #expect(Origin.from(.auto, status: .confirmed) == .confirmed)
    #expect(Origin.from(.aiEstimate) == .aiEstimate)
}

@Test func timelineSortsFiltersToDayAndGroupsWater() {
    let e = [
        TimelineEntry(id: "m", kind: .meal, start: at(13), title: "Lunch", origin: .manual),
        TimelineEntry(id: "w1", kind: .water, start: at(9), title: "Water", detail: "250 ml", origin: .manual),
        TimelineEntry(id: "w2", kind: .water, start: at(9, 20), title: "Water", detail: "500 ml", origin: .manual),
        TimelineEntry(id: "old", kind: .meal, start: at(13, day: 9), title: "Yesterday", origin: .manual),
        TimelineEntry(id: "w3", kind: .water, start: at(15), title: "Water", detail: "250 ml", origin: .manual),
    ]
    let t = Timeline.build(e, on: at(12), calendar: cal)
    #expect(t.map(\.id) == ["w1", "m", "w3"])
    #expect(t[0].detail == "750 ml")
}

@Test func sleepEndingTodayAppearsToday() {
    let s = TimelineEntry(id: "s", kind: .sleep, start: at(23, day: 9), end: at(7), title: "Sleep", origin: .manual)
    #expect(Timeline.build([s], on: at(12), calendar: cal).count == 1)
}

@Test func balanceIsNilWithoutMaintenance() {
    #expect(DaySummary(date: at(1)).calorieBalance == nil)
    #expect(DaySummary(date: at(1), kcalConsumed: 2000, kcalMaintenance: 2500).calorieBalance == -500)
}
