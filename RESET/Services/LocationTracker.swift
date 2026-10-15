import Foundation
import CoreLocation
import SwiftData
import Observation
import ResetCore

/// Region monitoring only. No continuous GPS. iOS may deliver events late or miss them, so every
/// session created here is an estimate that the user can correct.
@MainActor
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var servicesEnabled = true
    private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var monitor: CLMonitor?
    private var listenTask: Task<Void, Never>?
    private var oneShot: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var context: ModelContext?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAlways: Bool { authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    // MARK: Current location (one shot, for "save my current location")

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        if authorization == .notDetermined { requestWhenInUse() }
        return try await withCheckedThrowingContinuation { cont in
            oneShot = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.oneShot?.resume(returning: c); self.oneShot = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.oneShot?.resume(throwing: error); self.oneShot = nil }
    }

    // MARK: Monitoring

    /// Call at launch and whenever places change. Recreating the monitor with the same name lets iOS
    /// hand over events that happened while the app was not running.
    func start(context: ModelContext) async {
        self.context = context
        servicesEnabled = CLLocationManager.locationServicesEnabled()
        guard servicesEnabled, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }

        let monitor = monitor ?? (await CLMonitor("reset.places"))
        self.monitor = monitor
        await syncPlaces(monitor: monitor, context: context)

        if listenTask == nil {
            listenTask = Task { [weak self] in
                do {
                    for try await event in await monitor.events {
                        await self?.handle(identifier: event.identifier, state: event.state, date: event.date, delayed: false)
                    }
                } catch {
                    await MainActor.run { self?.lastError = error.localizedDescription }
                }
            }
        }
        await catchUp(monitor: monitor, context: context)
        SessionStore.flagStale(context: context)
        SessionStore.pruneEvents(context: context)
    }

    private func syncPlaces(monitor: CLMonitor, context: ModelContext) async {
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let wanted = Dictionary(uniqueKeysWithValues: places.filter(\.enabled).map { ($0.id.uuidString, $0) })
        for id in await monitor.identifiers where wanted[id] == nil { await monitor.remove(id) }
        // iOS allows about 20 regions per app. Places are few, so this is a cap rather than a limit.
        for (id, p) in wanted.prefix(20) {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                radius: max(100, p.radiusM))
            await monitor.add(condition, identifier: id)
        }
    }

    /// Events delivered while the app was closed arrive via the monitor's last recorded state.
    private func catchUp(monitor: CLMonitor, context: ModelContext) async {
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        for p in places where p.enabled {
            guard let record = await monitor.record(for: p.id.uuidString) else { continue }
            let e = record.lastEvent
            await handle(identifier: p.id.uuidString, state: e.state, date: e.date, delayed: true)
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State, date: Date, delayed: Bool) async {
        guard let context, let pid = UUID(uuidString: identifier) else { return }
        let transition: PlaceTransition
        switch state {
        case .satisfied: transition = .enter
        case .unsatisfied: transition = .exit
        default: return
        }
        let descriptor = FetchDescriptor<Place>(predicate: #Predicate { $0.id == pid })
        guard let place = try? context.fetch(descriptor).first else { return }

        // Skip events already stored (catch-up replays the last event on every launch).
        // Filtered in memory: SwiftData predicates on enum properties are unreliable.
        let known = (try? context.fetch(FetchDescriptor<LocationEvent>(predicate: #Predicate { $0.placeID == pid }))) ?? []
        if known.contains(where: { $0.transition == transition && abs($0.at.timeIntervalSince(date)) < 1 }) { return }

        context.insert(LocationEvent(placeID: pid, transition: transition, at: date, delayed: delayed))
        SessionStore.apply(PlaceEventValue(placeID: pid, transition: transition, at: date), place: place, context: context)
    }
}
