import Foundation
import SwiftData
import ResetCore

@Model
final class MealRecord {
    @Attribute(.unique) var id: UUID
    var at: Date
    var mealType: MealType
    var originalText: String
    var items: [FoodItem]
    var source: Source
    var confidence: Confidence
    var photoPath: String?
    var createdAt: Date

    init(at: Date, mealType: MealType, originalText: String, items: [FoodItem],
         source: Source, confidence: Confidence = .medium) {
        id = UUID(); self.at = at; self.mealType = mealType; self.originalText = originalText
        self.items = items; self.source = source; self.confidence = confidence; createdAt = .now
    }

    var nutrition: Nutrition { items.reduce(.zero) { $0 + $1.nutrition } }
}

@Model
final class SavedMeal {
    @Attribute(.unique) var id: UUID
    var name: String
    var items: [FoodItem]
    var useCount: Int
    var lastUsed: Date?
    init(name: String, items: [FoodItem]) {
        id = UUID(); self.name = name; self.items = items; useCount = 0
    }
}

@Model
final class WaterRecord {
    @Attribute(.unique) var id: UUID
    var at: Date
    var ml: Double
    var source: Source
    init(at: Date = .now, ml: Double, source: Source = .manual) {
        id = UUID(); self.at = at; self.ml = ml; self.source = source
    }
}

@Model
final class CaffeineRecord {
    @Attribute(.unique) var id: UUID
    var at: Date
    var name: String
    var servingMl: Double?
    var mg: Double
    var count: Int
    /// Label, catalog entry, user entered, or AI estimate. Never blank.
    var mgSource: String
    var source: Source
    init(at: Date = .now, name: String, servingMl: Double? = nil, mg: Double, count: Int = 1,
         mgSource: String, source: Source = .manual) {
        id = UUID(); self.at = at; self.name = name; self.servingMl = servingMl
        self.mg = mg; self.count = count; self.mgSource = mgSource; self.source = source
    }
    var totalMg: Double { mg * Double(count) }
}

@Model
final class SavedDrink {
    @Attribute(.unique) var id: UUID
    var name: String
    var servingMl: Double?
    var mg: Double
    var mgSource: String
    init(name: String, servingMl: Double?, mg: Double, mgSource: String) {
        id = UUID(); self.name = name; self.servingMl = servingMl; self.mg = mg; self.mgSource = mgSource
    }
}

@Model
final class SleepRecord {
    @Attribute(.unique) var id: UUID
    /// Day the sleep ended (wake-up day).
    var day: Date
    var asleepAt: Date
    var wokeAt: Date
    /// 1...5, nil if not reported.
    var quality: Int?
    var source: Source
    /// Time actually asleep, as Health reports it (awake gaps excluded). nil for nights typed in by hand.
    var asleepSeconds: Double?
    init(day: Date, asleepAt: Date, wokeAt: Date, quality: Int? = nil, source: Source = .manual) {
        id = UUID(); self.day = day; self.asleepAt = asleepAt; self.wokeAt = wokeAt
        self.quality = quality; self.source = source
    }
    var hours: Double { asleepSeconds.map { $0 / 3600 } ?? max(0, wokeAt.timeIntervalSince(asleepAt)) / 3600 }
}

@Model
final class ActivityRecord {
    @Attribute(.unique) var id: UUID
    var kind: ActivityKind
    var start: Date
    var end: Date
    var steps: Int?
    var distanceM: Double?
    var source: Source
    /// HealthKit sample UUID, used to avoid importing the same workout twice.
    var externalID: String?
    var note: String
    init(kind: ActivityKind, start: Date, end: Date, steps: Int? = nil, distanceM: Double? = nil,
         source: Source, externalID: String? = nil) {
        id = UUID(); self.kind = kind; self.start = start; self.end = end
        self.steps = steps; self.distanceM = distanceM; self.source = source
        self.externalID = externalID; note = ""
    }
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var planID: UUID?
    var title: String
    var start: Date
    var minutes: Int
    var completed: Bool
    var perceivedEffort: Int?
    var source: Source
    var externalID: String?
    init(planID: UUID? = nil, title: String, start: Date, minutes: Int, completed: Bool,
         source: Source = .manual, externalID: String? = nil) {
        id = UUID(); self.planID = planID; self.title = title; self.start = start; self.minutes = minutes
        self.completed = completed; self.source = source; self.externalID = externalID
    }
}

@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID
    var day: Date
    var title: String
    var kind: ActivityKind
    var minutes: Int
    var exercises: [PlannedExercise]
    var stepTarget: Int?
    var reason: String
    var createdAt: Date
    init(day: Date, title: String, kind: ActivityKind, minutes: Int, exercises: [PlannedExercise],
         stepTarget: Int?, reason: String) {
        id = UUID(); self.day = day; self.title = title; self.kind = kind; self.minutes = minutes
        self.exercises = exercises; self.stepTarget = stepTarget; self.reason = reason; createdAt = .now
    }
}

@Model
final class CheckIn {
    @Attribute(.unique) var id: UUID
    var at: Date
    var kind: CheckInKind
    /// 1...5 for scaled kinds.
    var value: Int
    var note: String
    init(at: Date = .now, kind: CheckInKind, value: Int, note: String = "") {
        id = UUID(); self.at = at; self.kind = kind; self.value = value; self.note = note
    }
}

@Model
final class RecoveryAssessment {
    @Attribute(.unique) var id: UUID
    var day: Date
    var bandRaw: String
    var reasons: [String]
    var createdAt: Date
    init(day: Date, bandRaw: String, reasons: [String]) {
        id = UUID(); self.day = day; self.bandRaw = bandRaw; self.reasons = reasons; createdAt = .now
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var at: Date
    var role: String
    var text: String
    /// JSON of a pending tool call awaiting confirmation, if any.
    var pendingActionJSON: String?
    init(role: String, text: String, pendingActionJSON: String? = nil) {
        id = UUID(); at = .now; self.role = role; self.text = text; self.pendingActionJSON = pendingActionJSON
    }
}

struct BreakInterval: Codable, Hashable {
    var start: Date
    var end: Date
}

struct PlannedExercise: Codable, Hashable {
    var name: String
    var sets: Int
    var reps: String
    var restSec: Int
    var modification: String?
}

/// Something bought, waiting for the user to say whether they ate it. Never counted in food totals.
/// Holds item text only. No prices, totals, merchants' addresses or card details are stored.
@Model
final class PurchaseDraft {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var text: String
    var categoryRaw: String
    var sourceRaw: String
    /// pending, ate, dismissed. Handled drafts are kept briefly so a repeat paste does not re-ask.
    var statusRaw: String
    /// Items read from a receipt photo, already marked not consumed.
    var items: [FoodItem]

    init(text: String, category: PurchaseCategory, source: String, items: [FoodItem] = []) {
        id = UUID(); createdAt = .now; self.text = text; categoryRaw = category.rawValue
        sourceRaw = source; statusRaw = "pending"; self.items = items
    }

    var category: PurchaseCategory { PurchaseCategory(rawValue: categoryRaw) ?? .unknown }
    var pending: Bool { statusRaw == "pending" }
}

@Model
final class PurchaseRuleRecord {
    @Attribute(.unique) var id: UUID
    var keyword: String
    var prefill: String
    init(keyword: String, prefill: String) { id = UUID(); self.keyword = keyword; self.prefill = prefill }
    var rule: PurchaseRule { PurchaseRule(keyword: keyword, prefill: prefill) }
}
