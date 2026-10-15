import Foundation
import AppIntents
import WidgetKit

/// Code compiled into both the app and the widget extension. No dependency on SwiftData or ResetCore, so the
/// widget stays tiny. The app publishes a small snapshot, and widget button taps are queued here until the app opens.
enum AppGroup {
    /// Must match the App Groups capability on BOTH targets. If you change the bundle id, change this and both entitlements.
    static let id = "group.com.reset.ai"
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

struct WidgetSnapshot: Codable, Equatable {
    var updated: Date
    var waterMl: Double
    var waterGoalMl: Double?
    var kcal: Double
    var kcalTarget: Double?
    var countCalories: Bool
    var proteinG: Double
    var proteinTargetG: Double
    var steps: Int?
}

struct QueuedWater: Codable, Equatable {
    var id: UUID
    var ml: Double
    var at: Date
}

enum SharedStore {
    private static let snapshotKey = "widget.snapshot"
    private static let queueKey = "widget.waterQueue"
    private static let drainedKey = "widget.drained"

    static func snapshot() -> WidgetSnapshot? {
        guard let d = AppGroup.defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    static func save(_ s: WidgetSnapshot) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        AppGroup.defaults?.set(d, forKey: snapshotKey)
    }

    static func queue() -> [QueuedWater] {
        guard let d = AppGroup.defaults?.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([QueuedWater].self, from: d)) ?? []
    }

    static func enqueue(_ ml: Double) {
        var q = queue()
        q.append(QueuedWater(id: UUID(), ml: ml, at: .now))
        // A stuck queue should not grow forever.
        if let d = try? JSONEncoder().encode(Array(q.suffix(50))) { AppGroup.defaults?.set(d, forKey: queueKey) }
    }

    /// Entries not yet turned into water records. Marks them handled before returning, so a crash cannot double count.
    static func takeQueue() -> [QueuedWater] {
        let q = queue()
        let drained = Set((AppGroup.defaults?.stringArray(forKey: drainedKey) ?? []))
        let fresh = q.filter { !drained.contains($0.id.uuidString) }
        let ids = Array((q.map { $0.id.uuidString } + Array(drained)).prefix(100))
        AppGroup.defaults?.set(ids, forKey: drainedKey)
        AppGroup.defaults?.removeObject(forKey: queueKey)
        return fresh
    }
}

/// Widget button. Runs in the widget process, so it only queues the drink. The app records it the next time it opens.
struct QueueWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Add water"
    static var description = IntentDescription("Adds water from the home screen widget.")

    @Parameter(title: "Amount in ml", default: 250)
    var ml: Int

    init() {}
    init(ml: Int) { self.ml = ml }

    func perform() async throws -> some IntentResult {
        guard (50...3000).contains(ml) else { return .result() }
        SharedStore.enqueue(Double(ml))
        // Show the new total right away without waiting for the app.
        if var s = SharedStore.snapshot() { s.waterMl += Double(ml); s.updated = .now; SharedStore.save(s) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
