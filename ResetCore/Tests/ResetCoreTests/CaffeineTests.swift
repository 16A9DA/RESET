import Testing
import Foundation
@testable import ResetCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func decayAtHalfLife() {
    let r = Caffeine.remaining([CaffeineDose(at: t0, mg: 160)], at: t0.addingTimeInterval(5 * 3600))
    #expect(abs(r.mid - 80) < 1e-9)
    #expect(r.low < r.mid && r.mid < r.high)
}

@Test func futureDosesIgnored() {
    #expect(Caffeine.remaining([CaffeineDose(at: t0.addingTimeInterval(60), mg: 100)], at: t0).mid == 0)
}

@Test func dailyTotalAndLevels() {
    let cal = Calendar.current
    let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: t0)!
    let doses = [CaffeineDose(at: noon, mg: 160), CaffeineDose(at: noon.addingTimeInterval(3600), mg: 160),
                 CaffeineDose(at: noon.addingTimeInterval(-86_400), mg: 500)]
    #expect(Caffeine.dailyTotal(doses, on: noon) == 320)
    #expect(Caffeine.level(totalMg: 0) == .none && Caffeine.level(totalMg: 320) == .near)
    #expect(Caffeine.level(totalMg: 100) == .moderate && Caffeine.level(totalMg: 450) == .above)
}

@Test func cutoffEightHoursBeforeBed() {
    let bed = t0
    #expect(Caffeine.cutoff(bedtime: bed) == bed.addingTimeInterval(-8 * 3600))
    #expect(Caffeine.isLate(bed.addingTimeInterval(-2 * 3600), bedtime: bed))
    #expect(!Caffeine.isLate(bed.addingTimeInterval(-10 * 3600), bedtime: bed))
}

@Test func catalogMatching() {
    #expect(Caffeine.catalogMatch("I had a Hell energy drink")?.mg == 80)
    #expect(Caffeine.catalogMatch("two Monsters")?.mg == 160)
    #expect(Caffeine.catalogMatch("a red bull")?.mg == 80)
    #expect(Caffeine.catalogMatch("chicken sandwich") == nil)
}

@Test func urgentSymptomsDetected() {
    #expect(Safety.needsUrgentCare("I had chest pain after the energy drink"))
    #expect(Safety.needsUrgentCare("I FAINTED at work"))
    #expect(!Safety.needsUrgentCare("a bit tired after work"))
}
