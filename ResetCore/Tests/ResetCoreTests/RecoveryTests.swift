import Testing
@testable import ResetCore

@Test func wellRestedIsGood() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [8, 7.5, 8], energy: 4, fatigue: 2))
    #expect(r.band == .good)
}

@Test func shortSleepPlusHighFatigueIsLowWithReasons() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [5, 6, 6], energy: 2, fatigue: 5))
    #expect(r.band == .low)
    #expect(r.reasons.contains { $0.contains("short") } && r.reasons.contains { $0.contains("fatigue") })
}

@Test func oneBadSignalCannotMakeItLow() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [3], sleepTargetHours: 8, energy: 3))
    #expect(r.strainPoints == 3 && r.band == .moderate)
}

@Test func tooLittleDataIsUnknownNotGuessed() {
    #expect(RecoveryEngine.assess(RecoveryInput()).band == .unknown)
    #expect(RecoveryEngine.assess(RecoveryInput(energy: 2)).band == .unknown)
}

@Test func symptomsForceLowAndSafeAdvice() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [8], energy: 4, symptomsReported: true))
    #expect(r.band == .low && r.advice.contains("medical help"))
}

@Test func trainingLoadAdds() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [7.5, 7.5], energy: 3, strenuousSessionsLast48h: 2, consecutiveTrainingDays: 3))
    #expect(r.strainPoints == 2 && r.band == .moderate)
}

@Test func olderNightsWeighLess() {
    let recentBad = RecoveryEngine.assess(RecoveryInput(sleepHours: [4, 8, 8], energy: 3))
    let oldBad = RecoveryEngine.assess(RecoveryInput(sleepHours: [8, 8, 4], energy: 3))
    #expect(recentBad.strainPoints > oldBad.strainPoints)
}

@Test func longWorkdayAddsLoad() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [6.5], energy: 3, workHoursRecent: 11))
    #expect(r.reasons.contains { $0.contains("long workday") })
}

@Test func lowFluidsAndFoodYesterdayStrainRecovery() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [8], energy: 3, waterShare: 0.4, intakeShare: 0.4))
    #expect(r.band == .moderate && r.reasons.contains { $0.contains("Fluids") } && r.reasons.contains { $0.contains("Food intake") })
}

@Test func goodFluidsAndFoodAddNoStrain() {
    let r = RecoveryEngine.assess(RecoveryInput(sleepHours: [8], energy: 4, waterShare: 0.9, intakeShare: 0.95, yesterdaySteps: 9000))
    #expect(r.band == .good)
}
