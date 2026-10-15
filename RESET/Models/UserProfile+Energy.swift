import Foundation
import ResetCore

extension UserProfile {
    var energyInput: EnergyInput {
        EnergyInput(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex, activity: activityLevel,
                    goal: goal, deficitPercent: deficitPercent, maintenanceOverride: maintenanceOverrideKcal,
                    targetWeightKg: targetWeightKg, proteinPerKg: proteinPerKg)
    }

    var energyPlan: EnergyPlan { Energy.plan(energyInput) }

    var effectiveWaterGoalMl: Double? {
        fluidRestriction ? nil : (waterGoalMl ?? Energy.waterGoalMl(weightKg: weightKg))
    }
}

extension Goal {
    var title: String {
        switch self {
        case .fatLoss: "Fat loss"
        case .fatLossKeepMuscle: "Fat loss, keep muscle"
        case .buildMuscle: "Build muscle"
        case .generalFitness: "General fitness"
        case .sleepAndEnergy: "Better sleep and energy"
        case .betterHabits: "Better daily habits"
        }
    }
}

extension ActivityLevel {
    var title: String {
        switch self {
        case .sedentary: "Mostly seated"
        case .light: "Light, some walking"
        case .moderate: "On my feet most of the day"
        case .high: "Active job plus training"
        case .veryHigh: "Very physical"
        }
    }
}

extension Equipment {
    var title: String {
        switch self {
        case .none: "No equipment"
        case .dumbbells: "Dumbbells"
        case .gym: "Full gym"
        }
    }
}

extension MealType {
    var title: String { rawValue.capitalized }
}
