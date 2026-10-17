import Foundation
import SwiftData
import ResetCore

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var onboardingDone: Bool

    var age: Int?
    var sex: Sex?
    var heightCm: Double
    var weightKg: Double
    var targetWeightKg: Double?
    var goal: Goal
    var activityLevel: ActivityLevel
    var units: UnitSystem

    /// Minutes after midnight.
    var wakeMinute: Int
    var bedMinute: Int
    var workStartMinute: Int?
    var workEndMinute: Int?
    var uniStartMinute: Int?
    var uniEndMinute: Int?
    /// Calendar weekday numbers, 1 = Sunday.
    var workDays: [Int]
    var uniDays: [Int]
    /// Hours aimed for on each weekday, index 0 = Sunday. 0 means a day off. Days differ, so there is no single "8 hours".
    var workGoalHours: [Double] = [0, 0, 0, 0, 0, 0, 0]
    var uniGoalHours: [Double] = [0, 0, 0, 0, 0, 0, 0]
    var gymDaysPerWeek: Int
    var equipment: Equipment
    var trainingLevelRaw: String

    var dietaryPreferences: [String]
    var allergies: [String]
    var caffeineHabit: String

    var calorieCountingEnabled: Bool
    var maintenanceOverrideKcal: Double?
    var deficitPercent: Double
    var proteinPerKg: Double
    var waterGoalMl: Double?
    var fluidRestriction: Bool
    var quickWaterMl: [Int]
    var sleepTargetHours: Double
    var windDownMinutes: Int
    var mealPattern: [MealType]
    var autoSaveFood: Bool
    var keepConversationHistory: Bool
    var aiProviderRaw: String
    var aiModel: String

    /// Goal in seconds for a category on a given day, nil when that day is off.
    func goalSeconds(_ category: SessionCategory, on day: Date = .now) -> TimeInterval? {
        let hours = category == .university ? uniGoalHours : workGoalHours
        let i = Calendar.current.component(.weekday, from: day) - 1
        guard hours.indices.contains(i), hours[i] > 0 else { return nil }
        return hours[i] * 3600
    }

    /// Keeps the weekday lists other features read in step with the per-day goals.
    func syncDays() {
        workDays = workGoalHours.indices.filter { workGoalHours[$0] > 0 }.map { $0 + 1 }
        uniDays = uniGoalHours.indices.filter { uniGoalHours[$0] > 0 }.map { $0 + 1 }
    }

    init() {
        id = UUID(); createdAt = .now; onboardingDone = false
        heightCm = 188; weightKg = 103
        goal = .fatLossKeepMuscle; activityLevel = .moderate; units = .metric
        wakeMinute = 7 * 60; bedMinute = 23 * 60
        workDays = []; uniDays = []
        gymDaysPerWeek = 3; equipment = .gym; trainingLevelRaw = "returning"
        dietaryPreferences = []; allergies = []; caffeineHabit = ""
        calorieCountingEnabled = true
        deficitPercent = 0.15; proteinPerKg = 1.8
        fluidRestriction = false; quickWaterMl = [150, 250, 500]
        sleepTargetHours = 8; windDownMinutes = 45
        mealPattern = [.breakfast, .lunch, .dinner]
        autoSaveFood = true; keepConversationHistory = true
        aiProviderRaw = "anthropic"; aiModel = "claude-haiku-5-5"
    }
}

@Model
final class Place {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: SessionCategory
    var latitude: Double
    var longitude: Double
    var radiusM: Double
    var enabled: Bool
    var expectedStartMinute: Int?
    var expectedEndMinute: Int?
    var remindOnArrival: Bool
    /// Gap shorter than this between exit and re-enter is treated as a break.
    var breakToleranceMin: Int
    var createdAt: Date

    init(name: String, category: SessionCategory, latitude: Double, longitude: Double, radiusM: Double = 150) {
        id = UUID(); self.name = name; self.category = category
        self.latitude = latitude; self.longitude = longitude; self.radiusM = radiusM
        enabled = true; remindOnArrival = false; breakToleranceMin = 20; createdAt = .now
    }
}

@Model
final class LocationEvent {
    @Attribute(.unique) var id: UUID
    var placeID: UUID
    var transition: PlaceTransition
    var at: Date
    /// True when iOS delivered it after relaunch or late. Timestamp is then approximate.
    var delayed: Bool

    init(placeID: UUID, transition: PlaceTransition, at: Date, delayed: Bool = false) {
        id = UUID(); self.placeID = placeID; self.transition = transition; self.at = at; self.delayed = delayed
    }
}

@Model
final class TrackedSession {
    @Attribute(.unique) var id: UUID
    var category: SessionCategory
    var placeID: UUID?
    var start: Date
    /// Nil while open.
    var end: Date?
    var status: SessionStatus
    var source: Source
    var breaks: [BreakInterval]
    var note: String

    init(category: SessionCategory, placeID: UUID? = nil, start: Date, end: Date? = nil,
         status: SessionStatus = .estimatedPresence, source: Source = .auto) {
        id = UUID(); self.category = category; self.placeID = placeID
        self.start = start; self.end = end; self.status = status; self.source = source
        breaks = []; note = ""
    }
}

@Model
final class WeightRecord {
    @Attribute(.unique) var id: UUID
    var at: Date
    var kg: Double
    var source: Source
    init(at: Date = .now, kg: Double, source: Source = .manual) {
        id = UUID(); self.at = at; self.kg = kg; self.source = source
    }
}

@Model
final class ReminderPreference {
    @Attribute(.unique) var key: String
    var enabled: Bool
    /// Meaning depends on key: interval minutes for water, minutes before bed for caffeine cutoff, etc.
    var value: Int
    var snoozedUntil: Date?
    init(key: String, enabled: Bool, value: Int) {
        self.key = key; self.enabled = enabled; self.value = value
    }
}
