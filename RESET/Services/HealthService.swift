import Foundation
import HealthKit
import CoreMotion
import SwiftData
import Observation
import ResetCore

struct DaySteps: Identifiable {
    var id: Date { day }
    var day: Date
    var steps: Int
}

/// Steps and workouts. HealthKit first (it already merges sources without double counting),
/// CoreMotion as a fallback when Health access is missing. Both undercount when the phone is not carried.
@MainActor
@Observable
final class HealthService {
    private let store = HKHealthStore()
    private let pedometer = CMPedometer()
    private let activity = CMMotionActivityManager()
    private static let bucket: TimeInterval = 300
    /// No person walks or runs faster than this, so a bucket above it is vehicle vibration.
    private static let maxStepsPerSecond = 4.0
    static let yesterdayStepsKey = "health.yesterdaySteps"
    private let requestedKey = "health.authRequested"

    private(set) var todaySteps: Int?
    private(set) var stepSource = "Not recorded"
    private(set) var distanceM: Double?
    private(set) var week: [DaySteps] = []
    private(set) var message: String?
    private var syncing = false

    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var authRequested: Bool { UserDefaults.standard.bool(forKey: requestedKey) }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in [HKQuantityTypeIdentifier.stepCount, .distanceWalkingRunning, .bodyMass] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    func requestAccess() async {
        guard available else { message = "Health data is not available on this device."; return }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: readTypes)
            UserDefaults.standard.set(true, forKey: requestedKey)
            message = nil
        } catch {
            message = "Health access failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Health only asks for types it has not asked about yet. Without this, a type added in an update
    /// (sleep) is never granted for people who already answered the first prompt, and imports stay empty.
    func ensureAccess() async {
        guard available, authRequested else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: [HKObjectType.workoutType()], read: readTypes)
        if status == .shouldRequest { await requestAccess() }
    }

    func refresh() async {
        let start = Calendar.current.startOfDay(for: .now)
        var steps: Int?
        var source = "Not recorded"

        if available, authRequested {
            let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: start) ?? start
            let vehicle = await vehicleSpans(from: weekStart, to: .now)
            week = await weekSteps(from: weekStart, vehicle: vehicle)
            if let today = week.last, today.steps > 0 { steps = today.steps }
            if week.count >= 2 { UserDefaults.standard.set(week[week.count - 2].steps, forKey: Self.yesterdayStepsKey) }
            distanceM = try? await cleanBuckets(.distanceWalkingRunning, unit: .meter(), from: start, vehicle: vehicle)
                .reduce(0) { $0 + $1.value }
            if steps != nil { source = "Apple Health" }
        }
        if steps == nil, let motion = await motionSteps(from: start, to: .now) {
            steps = motion; source = "iPhone motion sensor"
        }
        todaySteps = steps
        stepSource = source
    }

    /// Health wakes the app when a workout, a night of sleep or new steps arrive, so nothing needs opening.
    func startBackgroundSync(context: ModelContext) {
        guard available, authRequested, !syncing else { return }
        syncing = true
        let types: [(HKSampleType, HKUpdateFrequency)] = [
            (HKObjectType.workoutType(), .immediate),
            (HKObjectType.categoryType(forIdentifier: .sleepAnalysis), .immediate),
            (HKObjectType.quantityType(forIdentifier: .stepCount), .hourly),
        ].compactMap { t, f in t.map { ($0, f) } }
        for (type, freq) in types {
            store.enableBackgroundDelivery(for: type, frequency: freq) { _, _ in }
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, done, _ in
                nonisolated(unsafe) let finish = done
                Task { @MainActor in
                    guard let self else { finish(); return }
                    let since = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
                    await self.importWorkouts(since: since, context: context)
                    await self.importSleep(since: since, context: context)
                    await self.refresh()
                    finish()
                }
            }
            store.execute(q)
        }
    }

    // MARK: HealthKit queries

    /// Health merges sources per bucket. Buckets are cut down by the share spent in a vehicle and dropped
    /// when the rate is impossible on foot, so a scooter or bus ride does not count as walking.
    private func cleanBuckets(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, vehicle: [TimeSpan]) async throws -> [(start: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: .now)
        let desc = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum,
            anchorDate: Calendar.current.startOfDay(for: from), intervalComponents: DateComponents(minute: 5))
        let result = try await desc.result(for: store)
        var out: [(Date, Double)] = []
        result.enumerateStatistics(from: from, to: .now) { stats, _ in
            guard var v = stats.sumQuantity()?.doubleValue(for: unit), v > 0 else { return }
            let end = stats.startDate.addingTimeInterval(Self.bucket)
            let inCar = vehicle.reduce(0.0) {
                $0 + max(0, min(end, $1.end).timeIntervalSince(max(stats.startDate, $1.start)))
            }
            v *= max(0, 1 - inCar / Self.bucket)
            if id == .stepCount, v > Self.maxStepsPerSecond * Self.bucket { return }
            out.append((stats.startDate, v))
        }
        return out
    }

    private func weekSteps(from start: Date, vehicle: [TimeSpan]) async -> [DaySteps] {
        guard let buckets = try? await cleanBuckets(.stepCount, unit: .count(), from: start, vehicle: vehicle) else { return [] }
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map { day in
            let n = buckets.filter { cal.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.value }
            return DaySteps(day: day, steps: Int(n))
        }
    }

    /// Spans CoreMotion classed as driving or cycling. A scooter or bus shows up as one of these.
    private func vehicleSpans(from: Date, to: Date) async -> [TimeSpan] {
        guard CMMotionActivityManager.isActivityAvailable(), CMMotionActivityManager.authorizationStatus() != .denied else { return [] }
        return await withCheckedContinuation { cont in
            activity.queryActivityStarting(from: from, to: to, to: .main) { list, _ in
                let list = list ?? []
                var spans: [TimeSpan] = []
                for (i, a) in list.enumerated() where (a.automotive || a.cycling) && a.confidence != .low {
                    spans.append(TimeSpan(start: a.startDate, end: i + 1 < list.count ? list[i + 1].startDate : to))
                }
                cont.resume(returning: spans)
            }
        }
    }

    /// Workouts recorded by other apps or devices, imported once by HealthKit UUID.
    func importWorkouts(since: Date, context: ModelContext) async {
        guard available, authRequested else { return }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now)
        let desc = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                           sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 100)
        guard let workouts = try? await desc.result(for: store) else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []).compactMap(\.externalID))
        for w in workouts where !existing.contains(w.uuid.uuidString) {
            let kind: ActivityKind
            switch w.workoutActivityType {
            case .walking, .hiking: kind = .walk
            case .running: kind = .run
            case .traditionalStrengthTraining, .functionalStrengthTraining: kind = .strength
            case .flexibility, .yoga: kind = .mobility
            default: kind = .other
            }
            let dist = w.totalDistance?.doubleValue(for: .meter())
            context.insert(ActivityRecord(kind: kind, start: w.startDate, end: w.endDate, distanceM: dist,
                                          source: .imported, externalID: w.uuid.uuidString))
        }
        try? context.save()
    }

    /// Imports nights written to Health by other devices or apps. A night you entered yourself is never replaced.
    func importSleep(since: Date, context: ModelContext) async {
        guard available, authRequested, let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now)
        let desc = HKSampleQueryDescriptor(predicates: [.categorySample(type: type, predicate: predicate)],
                                           sortDescriptors: [SortDescriptor(\.startDate)], limit: HKObjectQueryNoLimit)
        guard let samples = try? await desc.result(for: store) else { return }
        let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        func spans(_ values: Set<Int>) -> [TimeSpan] {
            samples.filter { values.contains($0.value) }.map { TimeSpan(start: $0.startDate, end: $0.endDate) }
        }
        // Like Health: use asleep stages when a source wrote them, otherwise fall back to time in bed.
        var asleep = spans(asleepValues)
        if asleep.isEmpty { asleep = spans([HKCategoryValueSleepAnalysis.inBed.rawValue]) }
        let nights = SleepPlanner.nights(from: asleep)
        let existing = (try? context.fetch(FetchDescriptor<SleepRecord>())) ?? []
        for n in nights {
            let day = Calendar.current.startOfDay(for: n.end)
            let seconds = SleepPlanner.asleepSeconds(in: n, spans: asleep)
            if let record = existing.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
                // Health keeps adding to a night until you wake. Refresh imported nights, never ones typed in by hand.
                if record.source == .imported {
                    record.asleepAt = n.start; record.wokeAt = n.end; record.asleepSeconds = seconds
                }
                continue
            }
            let record = SleepRecord(day: day, asleepAt: n.start, wokeAt: n.end, source: .imported)
            record.asleepSeconds = seconds
            context.insert(record)
        }
        try? context.save()
    }

    /// Saves a timed walk to Health. Only called when the user allowed sharing.
    func saveWalk(start: Date, end: Date) async {
        guard available, store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .walking
        config.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            message = "Could not save the walk to Health: \(error.localizedDescription)"
        }
    }

    // MARK: CoreMotion fallback

    func motionSteps(from: Date, to: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let status = CMPedometer.authorizationStatus()
        guard status == .authorized || status == .notDetermined else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                cont.resume(returning: data.map { $0.numberOfSteps.intValue })
            }
        }
    }
}
