import Foundation
import SwiftData
import WidgetKit
import ResetCore

/// Connects the app to the home screen widget through the App Group. Without the capability the group defaults
/// are unavailable and everything here quietly does nothing, so the app itself is unaffected.
enum WidgetBridge {
    @MainActor
    static func publish(_ s: DaySummary) {
        let snap = WidgetSnapshot(updated: .now, waterMl: s.waterMl, waterGoalMl: s.waterGoalMl, kcal: s.kcalConsumed, kcalTarget: s.kcalTarget,
                                  countCalories: s.calorieCounting, proteinG: s.proteinG, proteinTargetG: s.proteinTargetG, steps: s.steps)
        if SharedStore.snapshot() != snap {
            SharedStore.save(snap)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Turns water added from the widget into normal water records. Called when the app becomes active.
    @MainActor @discardableResult
    static func drain(context: ModelContext) -> Int {
        let taken = SharedStore.takeQueue()
        for q in taken where (50...3000).contains(q.ml) {
            context.insert(WaterRecord(at: q.at, ml: q.ml, source: .manual))
        }
        if !taken.isEmpty { try? context.save() }
        return taken.count
    }

    /// Removes shared data. Used by the full reset.
    static func clear() {
        AppGroup.defaults?.removePersistentDomain(forName: AppGroup.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
