import Testing
import Foundation
@testable import ResetCore

private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 17))!
private func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }
private func ctx(_ band: RecoveryBand = .good, recent: [PastSession] = [], mins: Int = 45, planned: Bool = true,
                 symptoms: Bool = false, equipment: Equipment = .gym, perWeek: Int = 3, level: TrainingLevel = .returning) -> WorkoutContext {
    WorkoutContext(band: band, symptoms: symptoms, equipment: equipment, level: level, minutesAvailable: mins,
                   gymDaysPerWeek: perWeek, recent: recent, now: now, planned: planned, calendar: cal)
}

@Test func goodDayGivesStrength() {
    let s = WorkoutGenerator.suggest(ctx())
    #expect(s.kind == .strength && s.title == "Full body A" && s.exercises.count == 5 && s.strenuous)
}

@Test func alternatesAandB() {
    let s = WorkoutGenerator.suggest(ctx(recent: [PastSession(kind: .strength, title: "Full body A", day: daysAgo(2))]))
    #expect(s.title == "Full body B")
}

@Test func lowRecoveryGivesEasyWalk() {
    let s = WorkoutGenerator.suggest(ctx(.low))
    #expect(s.kind == .walk && !s.strenuous && s.minutes <= 25)
}

@Test func symptomsNeverGetStrenuousWork() {
    let s = WorkoutGenerator.suggest(ctx(.good, symptoms: true))
    #expect(!s.strenuous && s.reason.contains("clinician"))
}

@Test func moderateTrimsSetsAndTime() {
    let g = WorkoutGenerator.suggest(ctx(.good, level: .regular))
    let m = WorkoutGenerator.suggest(ctx(.moderate, level: .regular))
    #expect(m.exercises[0].sets == g.exercises[0].sets - 1 && m.minutes <= 35)
}

@Test func beginnersGetTwoSets() {
    #expect(WorkoutGenerator.suggest(ctx(level: .beginner)).exercises[0].sets == 2)
}

@Test func equipmentIsRespected() {
    #expect(WorkoutGenerator.suggest(ctx(equipment: .dumbbells)).title.hasPrefix("Dumbbell"))
    #expect(WorkoutGenerator.suggest(ctx(equipment: Equipment.none)).title.hasPrefix("Bodyweight"))
}

@Test func shortTimeGivesWalk() {
    #expect(WorkoutGenerator.suggest(ctx(mins: 15)).kind == .walk)
}

@Test func noGymPlannedGivesWalk() {
    let s = WorkoutGenerator.suggest(ctx(planned: false))
    #expect(s.kind == .walk && s.reason.contains("not a setback"))
}

@Test func weeklyCapAndStreakForceRecovery() {
    let three = (1...3).map { PastSession(kind: .strength, title: "Full body A", day: daysAgo($0)) }
    #expect(WorkoutGenerator.suggest(ctx(recent: three, perWeek: 5)).kind == .walk)
    let week = [2, 4, 6].map { PastSession(kind: .strength, title: "Full body A", day: daysAgo($0)) }
    #expect(WorkoutGenerator.suggest(ctx(recent: week, perWeek: 3)).kind == .walk)
}

@Test func missedSessionsNeverRaiseLoad() {
    let recent = [PastSession(kind: .strength, title: "Full body A", day: daysAgo(3), completed: false)]
    let s = WorkoutGenerator.suggest(ctx(recent: recent))
    #expect(s.reason.contains("Skipped sessions do not mean you should do more"))
}

@Test func progressionOnlyAfterThreeCompleted() {
    let three = [8, 5, 3].map { PastSession(kind: .strength, title: "Full body B", day: daysAgo($0)) }
    #expect(WorkoutGenerator.suggest(ctx(recent: three, perWeek: 5)).reason.contains("add one rep"))
}

@Test func missedGymAlternativeIsKindWalk() {
    let s = WorkoutGenerator.missedSessionAlternative(ctx(.good))
    #expect(s.kind == .walk && s.minutes == 20 && s.reason.contains("fine"))
}

@Test func stepTargetFollowsUsersOwnAverageAndIsCapped() {
    var c = ctx(.good, planned: false); c.avgSteps = 7000
    #expect(WorkoutGenerator.suggest(c).stepTarget == 7500)
    c.avgSteps = 20_000
    #expect(WorkoutGenerator.suggest(c).stepTarget == 10_000)
    c.avgSteps = nil
    #expect(WorkoutGenerator.suggest(c).stepTarget == nil)
}
