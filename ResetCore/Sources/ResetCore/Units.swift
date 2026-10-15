import Foundation

public enum Source: String, Codable, Sendable, CaseIterable {
    case auto, imported, manual, aiEstimate, confirmed
}

public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric, imperial
}

public enum Sex: String, Codable, Sendable, CaseIterable {
    case female, male
}

public enum Units {
    public static let kgPerLb = 0.45359237
    public static let cmPerInch = 2.54
    public static let mlPerFlOz = 29.5735295625

    public static func lbToKg(_ lb: Double) -> Double { lb * kgPerLb }
    public static func kgToLb(_ kg: Double) -> Double { kg / kgPerLb }
    public static func inToCm(_ i: Double) -> Double { i * cmPerInch }
    public static func cmToIn(_ cm: Double) -> Double { cm / cmPerInch }
    public static func flOzToMl(_ oz: Double) -> Double { oz * mlPerFlOz }
    public static func mlToFlOz(_ ml: Double) -> Double { ml / mlPerFlOz }
}
