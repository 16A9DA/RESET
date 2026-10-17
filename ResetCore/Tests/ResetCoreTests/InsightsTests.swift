import Testing
import Foundation
@testable import ResetCore

private func day(_ i: Int, sleep: Double? = nil, energy: Double? = nil, quality: Double? = nil, late: Bool? = nil, walk: Double = 0,
                 fatigue: Double? = nil, trained: Bool = false, meal: Double? = nil, uni: Bool = false) -> InsightDay {
    InsightDay(date: Date(timeIntervalSince1970: Double(i) * 86_400), sleepHours: sleep, sleepQuality: quality, energy: energy,
               fatigue: fatigue, lateCaffeine: late, walkMinutes: walk, trained: trained, firstMealMinute: meal, isUniversityDay: uni)
}

@Test func oneOrTwoDaysSayNothing() {
    let i = InsightEngine.sleepVsEnergy([day(0, sleep: 5, energy: 2), day(1, sleep: 8, energy: 4)], target: 8)
    #expect(i.state == .collecting && i.text.contains("Still collecting"))
}

@Test func sleepEnergyPatternFoundWithCounts() {
    let short = (0..<4).map { day($0, sleep: 5.5, energy: 2) }
    let long = (4..<8).map { day($0, sleep: 8, energy: 4) }
    let i = InsightEngine.sleepVsEnergy(short + long, target: 8)
    #expect(i.state == .pattern && i.observations == 8)
    #expect(i.text.contains("4 days") && i.text.contains("2.0") && i.text.contains("4.0"))
    #expect(!i.text.lowercased().contains("because") && !i.text.lowercased().contains("causes"))
}

@Test func similarGroupsReportNoDifference() {
    let d = (0..<8).map { day($0, sleep: $0 < 4 ? 5.5 : 8, energy: 3) }
    #expect(InsightEngine.sleepVsEnergy(d, target: 8).state == .noDifference)
}

@Test func unbalancedGroupsStillCollecting() {
    let d = (0..<2).map { day($0, sleep: 5, energy: 1) } + (2..<10).map { day($0, sleep: 8, energy: 5) }
    #expect(InsightEngine.sleepVsEnergy(d, target: 8).state == .collecting)
}

@Test func caffeineIsPairedWithNextNightsSleep() {
    var d: [InsightDay] = []
    for i in 0..<10 {
        let late = i % 2 == 0
        d.append(day(i, quality: i > 0 && (i - 1) % 2 == 0 ? 2 : 4, late: late))
    }
    let i = InsightEngine.caffeineVsSleep(d)
    #expect(i.state == .pattern && i.text.contains("lower"))
}

@Test func missingDataDaysAreSkipped() {
    let d = (0..<20).map { day($0, sleep: nil, energy: nil) }
    #expect(InsightEngine.sleepVsEnergy(d, target: 8).observations == 0)
}

@Test func walkAndFatigueInsights() {
    let walk = (0..<4).map { day($0, energy: 4, walk: 30) } + (4..<8).map { day($0, energy: 2, walk: 0) }
    #expect(InsightEngine.walkVsEnergy(walk).state == .pattern)
    let tired = (0..<4).map { day($0, fatigue: 5, trained: false) } + (4..<8).map { day($0, fatigue: 2, trained: true) }
    let f = InsightEngine.fatigueVsTraining(tired)
    #expect(f.state == .pattern && f.text.contains("0%") && f.text.contains("100%"))
}

@Test func mealTimingVariability() {
    let uni = [480.0, 600, 720, 540].enumerated().map { day($0.offset, meal: $0.element, uni: true) }
    let other = (4..<8).map { day($0, meal: 480) }
    #expect(InsightEngine.mealTiming(uni + other).state == .pattern)
}

@Test func allReturnsSevenInsights() {
    #expect(InsightEngine.all([], sleepTarget: 8).count == 7)
}

@Test func csvEscapingAndFormulaGuard() {
    #expect(CSV.escape("a,b") == "\"a,b\"" && CSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    #expect(CSV.safe("=SUM(A1)") == "'=SUM(A1)" && CSV.safe("-5") == "-5" && CSV.safe("Chicken") == "Chicken")
    #expect(CSV.build(header: ["a", "b"], rows: [["1", "x,y"]]) == "a,b\n1,\"x,y\"\n")
}
