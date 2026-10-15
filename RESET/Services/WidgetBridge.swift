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
        let old = SharedStore.snapshot()
        SharedStore.publish(snap)
        // Compare without the widget-only feedback fields, which publish keeps from the old snapshot.
        if old.map({ var o = $0; o.updated = snap.updated; return o }) != SharedStore.snapshot().map({ var n = $0; n.updated = snap.updated; return n }) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Turns water and energy check-ins made from widgets into normal records. Called when the app becomes active.
    @MainActor @discardableResult
    static func drain(context: ModelContext) -> Int {
        let water = SharedStore.takeQueue()
        for q in water where (50...3000).contains(q.ml) {
            context.insert(WaterRecord(at: q.at, ml: q.ml, source: .manual))
        }
        let checkIns = SharedStore.takeCheckIns()
        for c in checkIns where (1...5).contains(c.value) && c.kind == "energy" {
            context.insert(CheckIn(at: c.at, kind: .energy, value: c.value, note: "widget"))
        }
        if !water.isEmpty || !checkIns.isEmpty { try? context.save() }
        return water.count + checkIns.count
    }

    /// Removes shared data. Used by the full reset.
    static func clear() {
        AppGroup.defaults?.removePersistentDomain(forName: AppGroup.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
