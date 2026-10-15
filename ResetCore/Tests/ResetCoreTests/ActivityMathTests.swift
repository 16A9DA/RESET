import Testing
import Foundation
@testable import ResetCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func span(_ m0: Double, _ m1: Double, _ src: Source, kind: ActivityKind = .walk) -> ActivitySpan {
    ActivitySpan(kind: kind, start: t0.addingTimeInterval(m0 * 60), end: t0.addingTimeInterval(m1 * 60), source: src)
}

@Test func overlappingWalkCountsOnce() {
    let out = ActivityMath.dedupe([span(0, 30, .manual), span(1, 29, .imported)])
    #expect(out.count == 1 && out[0].source == .imported)
}

@Test func separateActivitiesBothKept() {
    let out = ActivityMath.dedupe([span(0, 30, .manual), span(120, 150, .manual)])
    #expect(out.count == 2)
}

@Test func structuredMinutesNoDoubleCount() {
    let w = DateInterval(start: t0, duration: 86_400)
    #expect(ActivityMath.structuredMinutes([span(0, 30, .manual), span(0, 30, .imported)], in: w) == 30)
}

@Test func systemStepsWinOverSpanSteps() {
    var a = span(0, 30, .manual); a.steps = 3000
    #expect(ActivityMath.dailySteps(system: 8000, fallbackFromSpans: [a]) == 8000)
    #expect(ActivityMath.dailySteps(system: nil, fallbackFromSpans: [a]) == 3000)
    #expect(ActivityMath.dailySteps(system: nil, fallbackFromSpans: []) == nil)
}
