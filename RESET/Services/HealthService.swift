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

    func refresh() async {
        let start = Calendar.current.startOfDay(for: .now)
        var steps: Int?
        var source = "Not recorded"

        if available, authRequested {
            steps = try? await sumQuantity(.stepCount, unit: .count(), from: start, to: .now).map { Int($0) }
            distanceM = try? await sumQuantity(.distanceWalkingRunning, unit: .meter(), from: start, to: .now)
            if steps != nil { source = "Apple Health" }
            week = await weekSteps()
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

    private func sumQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let desc = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate),
                                               options: .cumulativeSum)
        let stats = try await desc.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: unit)
    }

    private func weekSteps() async -> [DaySteps] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86_400)
        guard let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let desc = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum,
            anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let result = try? await desc.result(for: store) else { return [] }
        var out: [DaySteps] = []
        result.enumerateStatistics(from: start, to: end) { stats, _ in
            out.append(DaySteps(day: stats.startDate, steps: Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
        }
        return out
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
        let spans = samples.filter { asleepValues.contains($0.value) }.map { TimeSpan(start: $0.startDate, end: $0.endDate) }
        let nights = SleepPlanner.nights(from: spans)
        let existing = (try? context.fetch(FetchDescriptor<SleepRecord>())) ?? []
        for n in nights {
            let day = Calendar.current.startOfDay(for: n.end)
            if existing.contains(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) { continue }
            context.insert(SleepRecord(day: day, asleepAt: n.start, wokeAt: n.end, source: .imported))
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
