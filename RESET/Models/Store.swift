import Foundation
import SwiftData

enum Store {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, Place.self, LocationEvent.self, TrackedSession.self, WeightRecord.self,
        ReminderPreference.self, MealRecord.self, SavedMeal.self, WaterRecord.self, CaffeineRecord.self,
        SavedDrink.self, SleepRecord.self, ActivityRecord.self, WorkoutRecord.self, WorkoutPlan.self,
        CheckIn.self, RecoveryAssessment.self, ChatMessage.self, PurchaseDraft.self, PurchaseRuleRecord.self,
    ]

    static func container(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: Schema(models), configurations: config)
        } catch {
            // Never wipe the store silently. Fall back to memory so the app opens, and surface the error.
            print("SwiftData store failed to open: \(error)")
            let mem = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: Schema(models), configurations: mem)
        }
    }

    static func resetAll(_ context: ModelContext) throws {
        try context.delete(model: UserProfile.self)
        try context.delete(model: Place.self)
        try context.delete(model: LocationEvent.self)
        try context.delete(model: TrackedSession.self)
        try context.delete(model: WeightRecord.self)
        try context.delete(model: ReminderPreference.self)
        try context.delete(model: MealRecord.self)
        try context.delete(model: SavedMeal.self)
        try context.delete(model: WaterRecord.self)
        try context.delete(model: CaffeineRecord.self)
        try context.delete(model: SavedDrink.self)
        try context.delete(model: SleepRecord.self)
        try context.delete(model: ActivityRecord.self)
        try context.delete(model: WorkoutRecord.self)
        try context.delete(model: WorkoutPlan.self)
        try context.delete(model: CheckIn.self)
        try context.delete(model: RecoveryAssessment.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: PurchaseDraft.self)
        try context.delete(model: PurchaseRuleRecord.self)
        try context.save()
    }
}
