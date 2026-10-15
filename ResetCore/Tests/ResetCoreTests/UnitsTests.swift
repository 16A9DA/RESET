import Testing
@testable import ResetCore

@Test func unitRoundTrips() {
    #expect(abs(Units.kgToLb(Units.lbToKg(227)) - 227) < 1e-9)
    #expect(abs(Units.cmToIn(188) - 74.0157) < 1e-3)
    #expect(abs(Units.flOzToMl(8) - 236.588) < 1e-3)
}
