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
    /// Yesterday, as a share of the goal. Nil when there is no goal or nothing was logged.
    public var waterShare: Double?
    public var intakeShare: Double?
    public var yesterdaySteps: Int?

    public init(sleepHours: [Double] = [], sleepTargetHours: Double = 8, sleepQuality: Int? = nil, energy: Int? = nil,
                fatigue: Int? = nil, workHoursRecent: Double? = nil, strenuousSessionsLast48h: Int = 0,
                consecutiveTrainingDays: Int = 0, symptomsReported: Bool = false,
                waterShare: Double? = nil, intakeShare: Double? = nil, yesterdaySteps: Int? = nil) {
        self.sleepHours = sleepHours; self.sleepTargetHours = sleepTargetHours; self.sleepQuality = sleepQuality
        self.energy = energy; self.fatigue = fatigue; self.workHoursRecent = workHoursRecent
        self.strenuousSessionsLast48h = strenuousSessionsLast48h; self.consecutiveTrainingDays = consecutiveTrainingDays
        self.symptomsReported = symptomsReported
        self.waterShare = waterShare; self.intakeShare = intakeShare; self.yesterdaySteps = yesterdaySteps
    }
}

/// One slice of the recovery score. `fraction` is 0 to 1, `detail` is the number behind it in plain words.
public struct RecoveryComponent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case sleep, food, fluids, movement, load }
    public var kind: Kind
    public var fraction: Double
    public var detail: String
    public var id: String { kind.rawValue }
    public var title: String {
        switch kind {
        case .sleep: "Sleep"
        case .food: "Food"
        case .fluids: "Fluids"
        case .movement: "Steps"
        case .load: "Load"
        }
    }
}

public struct RecoveryResult: Sendable, Equatable {
    /// 0 to 100 built from sleep, food, fluids, steps and recent load. Nil until enough signals exist.
    public var score: Int? = nil
    public var components: [RecoveryComponent] = []
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

    /// Weighted blend of the signals that exist. Missing signals are left out and the rest re-weighted, never guessed.
    public static func score(_ i: RecoveryInput) -> (score: Int, parts: [RecoveryComponent])? {
        var parts: [(RecoveryComponent, Double)] = []
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

        let nights = Array(i.sleepHours.prefix(3))
        if !nights.isEmpty, i.sleepTargetHours > 0 {
            let w = Array(sleepWeights.prefix(nights.count))
            let avg = zip(nights, w).reduce(0) { $0 + $1.0 * $1.1 } / w.reduce(0, +)
            parts.append((RecoveryComponent(kind: .sleep, fraction: clamp(pow(avg / i.sleepTargetHours, 2)),
                                            detail: "\(String(format: "%.1f", avg)) of \(String(format: "%g", i.sleepTargetHours)) h"), 0.40))
        }
        if let k = i.intakeShare {
            // Eating a little over is fine, eating well under slows recovery.
            parts.append((RecoveryComponent(kind: .food, fraction: clamp(k > 1.3 ? 1.3 - (k - 1.3) : k),
                                            detail: "\(Int(k * 100))% of guide"), 0.20))
        }
        if let w = i.waterShare {
            parts.append((RecoveryComponent(kind: .fluids, fraction: clamp(w), detail: "\(Int(w * 100))% of goal"), 0.15))
        }
        if let st = i.yesterdaySteps {
            let f: Double = st < 5_000 ? Double(st) / 5_000 * 0.8 + 0.2 : (st <= 15_000 ? 1 : (st <= 25_000 ? 0.75 : 0.5))
            parts.append((RecoveryComponent(kind: .movement, fraction: clamp(f), detail: "\(st.formatted()) yesterday"), 0.10))
        }
        var load = 1.0
        load -= 0.25 * Double(i.strenuousSessionsLast48h)
        load -= 0.10 * Double(max(0, i.consecutiveTrainingDays - 2))
        if let e = i.energy { load += e >= 4 ? 0.1 : (e <= 2 ? -0.3 : 0) }
        if let f = i.fatigue, f >= 4 { load -= 0.3 }
        if let h = i.workHoursRecent, h >= 10 { load -= 0.15 }
        parts.append((RecoveryComponent(kind: .load, fraction: clamp(load),
                                        detail: i.strenuousSessionsLast48h == 0 ? "No hard sessions lately" : "\(i.strenuousSessionsLast48h) hard in 48 h"), 0.15))

        // Training history alone says nothing about recovery.
        guard parts.count >= minSignals else { return nil }
        let total = parts.reduce(0) { $0 + $1.1 }
        var value = parts.reduce(0) { $0 + $1.0.fraction * $1.1 } / total * 100
        if i.symptomsReported { value = min(value, 30) }
        return (Int(value.rounded()), parts.map(\.0))
    }

    public static func assess(_ i: RecoveryInput) -> RecoveryResult {
        var r = assessBand(i)
        if let s = score(i), r.band != .unknown { r.score = s.score; r.components = s.parts }
        return r
    }

    static func assessBand(_ i: RecoveryInput) -> RecoveryResult {
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
        // Fuel and fluids shape recovery, but only when clearly off. Yesterday is used because today is not over.
        if let w = i.waterShare { signals += 1; if w < 0.6 { add(1, "Fluids were low yesterday (\(Int(w * 100))% of your goal).") } }
        if let k = i.intakeShare { signals += 1; if k < 0.6 { add(1, "Food intake was low yesterday (\(Int(k * 100))% of your guide). Under eating slows recovery.") } }
        if let st = i.yesterdaySteps { signals += 1; if st >= 20_000 { add(1, "Very high step count yesterday (\(st.formatted())).") } }
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
