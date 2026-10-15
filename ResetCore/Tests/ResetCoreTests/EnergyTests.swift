import Testing
import Foundation
@testable import ResetCore

@Test func bmrKnownValues() {
    #expect(Energy.bmr(weightKg: 103, heightCm: 188, age: 30, sex: .male) == 2060)
    #expect(Energy.bmr(weightKg: 103, heightCm: 188, age: 30, sex: .female) == 1894)
    #expect(Energy.bmr(weightKg: 103, heightCm: 188, age: 30, sex: nil) == 1977)
    #expect(Energy.bmr(weightKg: 103, heightCm: 188, age: nil, sex: .male) == nil)
}

@Test func deficitIsCappedAndModerate() {
    let p = Energy.plan(EnergyInput(weightKg: 103, heightCm: 188, age: 30, sex: .male, activity: .moderate))
    #expect(abs(p.maintenanceKcal! - 2060 * 1.55) < 0.01)
    let delta = p.maintenanceKcal! - p.targetKcal!
    #expect(delta > 0 && delta <= Energy.maxDailyDeficit)
}

@Test func targetNeverBelowBmr() {
    let p = Energy.plan(EnergyInput(weightKg: 60, heightCm: 160, age: 30, sex: .female, activity: .sedentary,
                                    deficitPercent: 0.5, maintenanceOverride: 1500))
    #expect(p.targetKcal! >= max(p.bmr!, Energy.absoluteFloorKcal))
}

@Test func noAgeMeansNoEstimateButOverrideWorks() {
    let a = Energy.plan(EnergyInput(weightKg: 103, heightCm: 188))
    #expect(a.targetKcal == nil && a.maintenanceKcal == nil)
    let b = Energy.plan(EnergyInput(weightKg: 103, heightCm: 188, maintenanceOverride: 2800))
    #expect(b.targetKcal != nil)
}

@Test func proteinUsesTargetWeightWhenSet() {
    let p = Energy.plan(EnergyInput(weightKg: 103, heightCm: 188, targetWeightKg: 90, proteinPerKg: 1.6))
    #expect(p.proteinG == 144)
}

@Test func waterGoalClamped() {
    #expect(Energy.waterGoalMl(weightKg: 40) == 1500)
    #expect(Energy.waterGoalMl(weightKg: 103) == 3100)
    #expect(Energy.waterGoalMl(weightKg: 200) == 3500)
}

@Test func balanceUsesMaintenanceOnly() {
    #expect(Energy.balance(consumedKcal: 2000, maintenanceKcal: 2500) == -500)
    #expect(Energy.balance(consumedKcal: 2000, maintenanceKcal: nil) == nil)
}

@Test func weightTrend() {
    let start = Date(timeIntervalSince1970: 0)
    let pts = (0..<8).map { WeightPoint(at: start.addingTimeInterval(Double($0) * 4 * 86_400), kg: 100 - Double($0) * 0.2) }
    let s = WeightTrend.slopeKgPerDay(pts)!
    #expect(abs(s - (-0.05)) < 1e-9)
    #expect(WeightTrend.slopeKgPerDay(Array(pts.prefix(2))) == nil)
    let m = WeightTrend.impliedMaintenance(avgIntakeKcal: 2400, points: pts)!
    #expect(abs(m - (2400 + 0.05 * 7700)) < 1e-6)
}
