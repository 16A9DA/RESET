import Foundation

public struct EnergyInput: Sendable {
    public var weightKg: Double
    public var heightCm: Double
    public var age: Int?
    public var sex: Sex?
    public var activity: ActivityLevel
    public var goal: Goal
    public var deficitPercent: Double
    public var maintenanceOverride: Double?
    public var targetWeightKg: Double?
    public var proteinPerKg: Double

    public init(weightKg: Double, heightCm: Double, age: Int? = nil, sex: Sex? = nil,
                activity: ActivityLevel = .moderate, goal: Goal = .fatLossKeepMuscle,
                deficitPercent: Double = 0.15, maintenanceOverride: Double? = nil,
                targetWeightKg: Double? = nil, proteinPerKg: Double = 1.6) {
        self.weightKg = weightKg; self.heightCm = heightCm; self.age = age; self.sex = sex
        self.activity = activity; self.goal = goal; self.deficitPercent = deficitPercent
        self.maintenanceOverride = maintenanceOverride; self.targetWeightKg = targetWeightKg
        self.proteinPerKg = proteinPerKg
    }
}

public struct EnergyPlan: Sendable, Equatable {
    public var bmr: Double?
    public var maintenanceKcal: Double?
    public var targetKcal: Double?
    public var proteinG: Double
    public var carbsG: Double?
    public var fatG: Double?
    public var waterMl: Double
    /// Plain-language caveats shown next to the numbers.
    public var notes: [String]
}

public enum Energy {
    public static let maxDailyDeficit = 500.0
    public static let absoluteFloorKcal = 1200.0
    public static let kcalPerKgFat = 7700.0

    /// Mifflin-St Jeor. Sex unknown uses the midpoint of the two constants. Age unknown gives nil.
    public static func bmr(weightKg: Double, heightCm: Double, age: Int?, sex: Sex?) -> Double? {
        guard let age, weightKg > 0, heightCm > 0 else { return nil }
        let constant: Double
        switch sex {
        case .male: constant = 5
        case .female: constant = -161
        case nil: constant = -78
        }
        return 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + constant
    }

    public static func plan(_ i: EnergyInput) -> EnergyPlan {
        var notes: [String] = ["All values are estimates. Adjust them if your weight trend disagrees."]
        let bmr = bmr(weightKg: i.weightKg, heightCm: i.heightCm, age: i.age, sex: i.sex)
        if i.age == nil { notes.append("Add your age to estimate calories, or enter your own maintenance value.") }
        if i.age != nil && i.sex == nil { notes.append("Sex not set, so a general midpoint equation is used.") }

        // Activity multiplier already covers habitual walking and training. Logged workouts are not added on top.
        let maintenance = i.maintenanceOverride ?? bmr.map { $0 * i.activity.multiplier }
        if i.maintenanceOverride != nil { notes.append("Using your own maintenance value.") }

        var target: Double?
        if let m = maintenance {
            let delta: Double
            switch i.goal {
            case .fatLoss, .fatLossKeepMuscle: delta = -min(m * i.deficitPercent, maxDailyDeficit)
            case .buildMuscle: delta = m * 0.05
            default: delta = 0
            }
            let floor = max(bmr ?? 0, absoluteFloorKcal)
            target = max(m + delta, floor)
            if m + delta < floor { notes.append("Target held at a safe floor. A larger deficit is not recommended.") }
        }

        let protein = (i.targetWeightKg ?? i.weightKg) * i.proteinPerKg
        var carbs: Double?, fat: Double?
        if let t = target {
            fat = t * 0.25 / 9
            carbs = max(0, (t - protein * 4 - fat! * 9) / 4)
        }
        return EnergyPlan(bmr: bmr, maintenanceKcal: maintenance, targetKcal: target, proteinG: protein,
                          carbsG: carbs, fatG: fat, waterMl: waterGoalMl(weightKg: i.weightKg), notes: notes)
    }

    /// General starting point of 30 ml/kg, clamped. The user can override. Not a medical recommendation.
    public static func waterGoalMl(weightKg: Double) -> Double {
        min(3500, max(1500, (weightKg * 30 / 50).rounded() * 50))
    }

    /// Consumed minus expenditure. Expenditure is the maintenance estimate, not maintenance plus logged activity.
    public static func balance(consumedKcal: Double, maintenanceKcal: Double?) -> Double? {
        maintenanceKcal.map { consumedKcal - $0 }
    }
}

public struct WeightPoint: Sendable {
    public var at: Date
    public var kg: Double
    public init(at: Date, kg: Double) { self.at = at; self.kg = kg }
}

public enum WeightTrend {
    /// Least-squares slope in kg per day, or nil when data is too thin to say anything.
    public static func slopeKgPerDay(_ pts: [WeightPoint], minPoints: Int = 4, minSpanDays: Double = 10) -> Double? {
        guard pts.count >= minPoints, let first = pts.map(\.at).min(), let last = pts.map(\.at).max(),
              last.timeIntervalSince(first) / 86_400 >= minSpanDays else { return nil }
        let xs = pts.map { $0.at.timeIntervalSince(first) / 86_400 }
        let ys = pts.map(\.kg)
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return sxy / sxx
    }

    /// Suggestion only: maintenance implied by average intake and the weight slope.
    /// Needs 6+ weigh-ins over 21+ days. Shown to the user, never applied silently.
    public static func impliedMaintenance(avgIntakeKcal: Double, points: [WeightPoint]) -> Double? {
        guard let s = slopeKgPerDay(points, minPoints: 6, minSpanDays: 21) else { return nil }
        return avgIntakeKcal - s * Energy.kcalPerKgFat
    }
}
