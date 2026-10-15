import Foundation

public enum Goal: String, Codable, Sendable, CaseIterable {
    case fatLoss, fatLossKeepMuscle, buildMuscle, generalFitness, sleepAndEnergy, betterHabits
}

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary, light, moderate, high, veryHigh

    /// Multiplier applied to resting energy. Includes habitual activity, so logged walks are not added on top.
    public var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .high: 1.725
        case .veryHigh: 1.9
        }
    }
}

public enum SessionCategory: String, Codable, Sendable, CaseIterable {
    case work, university, gym, other
}

public enum SessionStatus: String, Codable, Sendable {
    /// Phone was inside the region. Not proof of working.
    case estimatedPresence
    case confirmed
    case needsReview
}

public enum PlaceTransition: String, Codable, Sendable {
    case enter, exit
}

public enum CheckInKind: String, Codable, Sendable, CaseIterable {
    /// value 1...5
    case energy, fatigue, sleepQuality, mood, hunger
    /// value ignored, note holds symptom text
    case symptom
}

public enum MealType: String, Codable, Sendable, CaseIterable {
    case breakfast, lunch, dinner, snack
}

public enum ActivityKind: String, Codable, Sendable, CaseIterable {
    case walk, run, strength, mobility, other
}

public enum Confidence: String, Codable, Sendable, Comparable {
    case low, medium, high
    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case none, dumbbells, gym
}

/// Nutrition for a quantity of food. All fields absolute for the stated amount, not per 100 g.
public struct Nutrition: Codable, Sendable, Hashable {
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double?
    public var sugarG: Double?
    public var sodiumMg: Double?
    public var caffeineMg: Double?

    public init(kcal: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
                fiberG: Double? = nil, sugarG: Double? = nil, sodiumMg: Double? = nil, caffeineMg: Double? = nil) {
        self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        self.fiberG = fiberG; self.sugarG = sugarG; self.sodiumMg = sodiumMg; self.caffeineMg = caffeineMg
    }

    public static let zero = Nutrition()

    public static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        func add(_ x: Double?, _ y: Double?) -> Double? {
            (x == nil && y == nil) ? nil : (x ?? 0) + (y ?? 0)
        }
        return Nutrition(kcal: a.kcal + b.kcal, proteinG: a.proteinG + b.proteinG,
                         carbsG: a.carbsG + b.carbsG, fatG: a.fatG + b.fatG,
                         fiberG: add(a.fiberG, b.fiberG), sugarG: add(a.sugarG, b.sugarG),
                         sodiumMg: add(a.sodiumMg, b.sodiumMg), caffeineMg: add(a.caffeineMg, b.caffeineMg))
    }

    public func scaled(_ f: Double) -> Nutrition {
        Nutrition(kcal: kcal * f, proteinG: proteinG * f, carbsG: carbsG * f, fatG: fatG * f,
                  fiberG: fiberG.map { $0 * f }, sugarG: sugarG.map { $0 * f },
                  sodiumMg: sodiumMg.map { $0 * f }, caffeineMg: caffeineMg.map { $0 * f })
    }
}

/// Calendar helpers. Days always use the device calendar and current time zone, so DST and travel follow the phone.
public enum Day {
    public static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func interval(of date: Date, calendar: Calendar = .current) -> DateInterval {
        let s = calendar.startOfDay(for: date)
        // Not +24h: DST days are 23 or 25 hours.
        let e = calendar.date(byAdding: .day, value: 1, to: s) ?? s.addingTimeInterval(86_400)
        return DateInterval(start: s, end: e)
    }

    public static func date(_ base: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: base) ?? base
    }
}
