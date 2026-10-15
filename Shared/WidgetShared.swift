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

/// Screens a widget can open. Only these fixed names are accepted, and a link carries no data.
enum DeepLink: String, CaseIterable {
    case food, photo, walk, coach
    case checkIn = "checkin"

    static let scheme = "resetai"
    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == scheme, let host = url.host, url.path.isEmpty || url.path == "/" else { return nil }
        return DeepLink(rawValue: host)
    }
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
    /// Last energy check-in made from a widget, so the widget can confirm it right away.
    var lastEnergy: Int?
    var lastEnergyAt: Date?
}

struct QueuedWater: Codable, Equatable, Identifiable {
    var id: UUID
    var ml: Double
    var at: Date
}

struct QueuedCheckIn: Codable, Equatable, Identifiable {
    var id: UUID
    /// "energy" or "fatigue"
    var kind: String
    /// 1 to 5
    var value: Int
    var at: Date
}

enum SharedStore {
    /// Tests point this at a throwaway suite.
    nonisolated(unsafe) static var defaultsOverride: UserDefaults?
    private static var ud: UserDefaults? { defaultsOverride ?? AppGroup.defaults }

    private static let snapshotKey = "widget.snapshot"
    private static let waterKey = "widget.waterQueue"
    private static let checkInKey = "widget.checkInQueue"
    private static let maxQueued = 50

    static func snapshot() -> WidgetSnapshot? {
        guard let d = ud?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    static func save(_ s: WidgetSnapshot) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        ud?.set(d, forKey: snapshotKey)
    }

    /// Keeps widget-only feedback (last check-in) when the app publishes fresh numbers.
    static func publish(_ s: WidgetSnapshot) {
        var s = s
        if let old = snapshot() { s.lastEnergy = old.lastEnergy; s.lastEnergyAt = old.lastEnergyAt }
        save(s)
    }

    // MARK: Generic queue

    private static func read<T: Codable>(_ key: String) -> [T] {
        guard let d = ud?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: d)) ?? []
    }

    private static func append<T: Codable>(_ item: T, key: String) {
        var q: [T] = read(key)
        q.append(item)
        // A stuck queue should not grow forever.
        if let d = try? JSONEncoder().encode(Array(q.suffix(maxQueued))) { ud?.set(d, forKey: key) }
    }

    /// Entries not yet handled. Marks them handled before returning, so a crash cannot double count.
    private static func take<T: Codable & Identifiable>(_ key: String) -> [T] where T.ID == UUID {
        let drainedKey = key + ".drained"
        let q: [T] = read(key)
        let drained = Set(ud?.stringArray(forKey: drainedKey) ?? [])
        let fresh = q.filter { !drained.contains($0.id.uuidString) }
        ud?.set(Array((q.map { $0.id.uuidString } + Array(drained)).prefix(100)), forKey: drainedKey)
        ud?.removeObject(forKey: key)
        return fresh
    }

    static func queue() -> [QueuedWater] { read(waterKey) }
    static func enqueue(_ ml: Double) { append(QueuedWater(id: UUID(), ml: ml, at: .now), key: waterKey) }
    static func takeQueue() -> [QueuedWater] { take(waterKey) }

    static func enqueueCheckIn(kind: String, value: Int) { append(QueuedCheckIn(id: UUID(), kind: kind, value: value, at: .now), key: checkInKey) }
    static func takeCheckIns() -> [QueuedCheckIn] { take(checkInKey) }
}

/// Widget button. Runs in the widget process, so it only queues the drink. The app records it the next time it opens.
struct QueueWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Add water"
    static var description = IntentDescription("Adds water from the home screen or lock screen widget.")

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

/// Widget button for a one tap energy check-in. Queued like water.
struct QueueCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Energy check-in"
    static var description = IntentDescription("Records how your energy is, from a widget.")

    @Parameter(title: "Energy, 1 to 5", default: 3)
    var value: Int

    init() {}
    init(value: Int) { self.value = value }

    func perform() async throws -> some IntentResult {
        guard (1...5).contains(value) else { return .result() }
        SharedStore.enqueueCheckIn(kind: "energy", value: value)
        if var s = SharedStore.snapshot() { s.lastEnergy = value; s.lastEnergyAt = .now; SharedStore.save(s) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
