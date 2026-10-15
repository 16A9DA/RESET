import Foundation

public enum RecoveryBand: String, Codable, Sendable {
    case unknown, low, moderate, good

    public var title: String {
        switch self {
        case .unknown: "Not enough data"
        case .low: "Take it easy"
        case .moderate: "Moderate"
        case .good: "Good to go"
        }
    }
}

public struct RecoveryInput: Sendable {
    /// Hours slept, most recent night first. Up to three are used.
    public var sleepHours: [Double]
    public var sleepTargetHours: Double
    public var sleepQuality: Int?
    public var energy: Int?
    public var fatigue: Int?
    public var workHoursRecent: Double?
    public var strenuousSessionsLast48h: Int
    public var consecutiveTrainingDays: Int
    public var symptomsReported: Bool

    public init(sleepHours: [Double] = [], sleepTargetHours: Double = 8, sleepQuality: Int? = nil, energy: Int? = nil,
                fatigue: Int? = nil, workHoursRecent: Double? = nil, strenuousSessionsLast48h: Int = 0,
                consecutiveTrainingDays: Int = 0, symptomsReported: Bool = false) {
        self.sleepHours = sleepHours; self.sleepTargetHours = sleepTargetHours; self.sleepQuality = sleepQuality
        self.energy = energy; self.fatigue = fatigue; self.workHoursRecent = workHoursRecent
        self.strenuousSessionsLast48h = strenuousSessionsLast48h; self.consecutiveTrainingDays = consecutiveTrainingDays
        self.symptomsReported = symptomsReported
    }
}

public struct RecoveryResult: Sendable, Equatable {
    public var band: RecoveryBand
    /// Why, in plain language. Shown to the user.
    public var reasons: [String]
    public var advice: String
    /// Strain points. Exposed for tests and transparency, not shown as a score.
    public var strainPoints: Int
    public var signalCount: Int
    public static let disclaimer = "A lifestyle indicator built from your own entries. It is not a measurement of your body and not medical advice."
}

/// Transparent, rule based. Every rule adds strain points; bands come from the total.
/// Weights are plain constants so they are easy to adjust. No learned model.
public enum RecoveryEngine {
    public static let sleepWeights: [Double] = [0.5, 0.3, 0.2]
    public static let minSignals = 2

    public static func assess(_ i: RecoveryInput) -> RecoveryResult {
        var points = 0
        var strainSources = 0
        var reasons: [String] = []
        var signals = 0

        func add(_ p: Int, _ reason: String) {
            points += p
            if p > 0 { strainSources += 1; reasons.append(reason) }
            else if p < 0 { reasons.append(reason) }
        }

        // Sleep: weighted average of up to three nights against the target. One short night counts for less.
        let nights = Array(i.sleepHours.prefix(3))
        if !nights.isEmpty {
            signals += 1
            let w = Array(sleepWeights.prefix(nights.count))
            let avg = zip(nights, w).reduce(0) { $0 + $1.0 * $1.1 } / w.reduce(0, +)
            let deficit = i.sleepTargetHours - avg
            let hours = String(format: "%.1f", avg)
            switch deficit {
            case ...0.5: reasons.append("Sleep is close to your target (about \(hours) h recently).")
            case ...1.5: add(1, "Sleep was a little short (about \(hours) h against \(String(format: "%g", i.sleepTargetHours)) h).")
            case ...2.5: add(2, "Sleep was clearly short (about \(hours) h against \(String(format: "%g", i.sleepTargetHours)) h).")
            default: add(3, "Sleep was very short (about \(hours) h against \(String(format: "%g", i.sleepTargetHours)) h).")
            }
        }
        if let q = i.sleepQuality { signals += 1; if q <= 2 { add(1, "You rated your sleep quality low.") } }
        if let e = i.energy {
            signals += 1
            if e <= 2 { add(2, "You reported low energy.") } else if e >= 4 { add(-1, "You reported good energy.") }
        }
        if let f = i.fatigue {
            signals += 1
            if f >= 4 { add(2, "You reported high fatigue.") }
        }
        if let h = i.workHoursRecent { signals += 1; if h >= 10 { add(1, "A long workday (\(String(format: "%.0f", h)) h) adds load.") } }
        signals += 1 // training history is always known, even when it is zero
        if i.strenuousSessionsLast48h >= 2 { add(1, "Two or more hard sessions in the last two days.") }
        if i.consecutiveTrainingDays >= 3 { add(1, "Three or more training days in a row.") }

        if i.symptomsReported {
            return RecoveryResult(band: .low, reasons: ["You reported symptoms. Rest and see a clinician if they persist or worry you."] + reasons,
                                  advice: "Skip hard training today. If symptoms are severe or include chest pain, fainting or trouble breathing, get medical help.",
                                  strainPoints: points, signalCount: signals)
        }

        // Training history alone is not enough to say anything about recovery.
        if signals - 1 < minSignals {
            return RecoveryResult(band: .unknown, reasons: ["Log sleep and a quick energy or fatigue check-in to get a read."],
                                  advice: "No strong recommendation yet. Do what feels right today.", strainPoints: points, signalCount: signals)
        }

        var band: RecoveryBand = points <= 1 ? .good : (points <= 3 ? .moderate : .low)
        // A single strained signal never pushes you to low. Avoids overreacting to one data point.
        if band == .low && strainSources < 2 { band = .moderate; reasons.append("Only one signal is strained, so this stays moderate.") }

        let advice: String
        switch band {
        case .good: advice = "Your inputs look fine. A planned workout is reasonable."
        case .moderate: advice = "Keep it lighter or shorter than usual. A brisk walk or a trimmed workout works well."
        case .low: advice = "Consider an easy walk, mobility or full rest today, and aim for an earlier night."
        case .unknown: advice = ""
        }
        return RecoveryResult(band: band, reasons: reasons, advice: advice, strainPoints: points, signalCount: signals)
    }
}
