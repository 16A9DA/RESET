import Testing
import Foundation

private func fresh() -> UserDefaults {
    let d = UserDefaults(suiteName: "reset.widget.test.\(UUID().uuidString)")!
    SharedStore.defaultsOverride = d
    return d
}

private func snap(water: Double = 500) -> WidgetSnapshot {
    WidgetSnapshot(updated: .now, waterMl: water, waterGoalMl: 3000, kcal: 1000, kcalTarget: 2200, countCalories: true, proteinG: 60, proteinTargetG: 150, steps: nil)
}

@Suite(.serialized) struct WidgetSharedTests {
    @Test func waterQueueRoundTripAndDrainOnce() {
        _ = fresh()
        SharedStore.enqueue(250); SharedStore.enqueue(500)
        #expect(SharedStore.queue().count == 2)
        let first = SharedStore.takeQueue()
        #expect(first.map(\.ml) == [250, 500])
        #expect(SharedStore.takeQueue().isEmpty && SharedStore.queue().isEmpty)
    }

    @Test func drainedIdsAreNeverReplayed() {
        let d = fresh()
        SharedStore.enqueue(250)
        let items = SharedStore.takeQueue()
        // Simulate the same entry reappearing after a crash between taking and clearing.
        d.set(try! JSONEncoder().encode(items), forKey: "widget.waterQueue")
        #expect(SharedStore.takeQueue().isEmpty)
    }

    @Test func queueIsCapped() {
        _ = fresh()
        for _ in 0..<80 { SharedStore.enqueue(100) }
        #expect(SharedStore.queue().count == 50)
    }

    @Test func checkInQueueIsSeparateFromWater() {
        _ = fresh()
        SharedStore.enqueue(250)
        SharedStore.enqueueCheckIn(kind: "energy", value: 4)
        let c = SharedStore.takeCheckIns()
        #expect(c.count == 1 && c[0].kind == "energy" && c[0].value == 4)
        #expect(SharedStore.takeQueue().count == 1)
    }

    @Test func publishKeepsWidgetOnlyFeedback() {
        _ = fresh()
        var s = snap(); s.lastEnergy = 4; s.lastEnergyAt = .now
        SharedStore.save(s)
        SharedStore.publish(snap(water: 900))
        let got = SharedStore.snapshot()!
        #expect(got.waterMl == 900 && got.lastEnergy == 4)
    }

    @Test func oldSnapshotWithoutNewFieldsStillDecodes() throws {
        let d = fresh()
        let legacy = #"{"updated":0,"waterMl":100,"kcal":0,"countCalories":true,"proteinG":0,"proteinTargetG":0}"#
        d.set(Data(legacy.utf8), forKey: "widget.snapshot")
        #expect(SharedStore.snapshot()?.waterMl == 100)
    }

    @Test func waterIntentQueuesAndUpdatesSnapshotAndRejectsBadAmounts() async throws {
        _ = fresh()
        SharedStore.save(snap(water: 500))
        _ = try await QueueWaterIntent(ml: 250).perform()
        #expect(SharedStore.snapshot()!.waterMl == 750 && SharedStore.queue().count == 1)
        _ = try await QueueWaterIntent(ml: 99_999).perform()
        _ = try await QueueWaterIntent(ml: 10).perform()
        #expect(SharedStore.queue().count == 1)
    }

    @Test func checkInIntentValidatesAndGivesFeedback() async throws {
        _ = fresh()
        SharedStore.save(snap())
        _ = try await QueueCheckInIntent(value: 5).perform()
        _ = try await QueueCheckInIntent(value: 9).perform()
        _ = try await QueueCheckInIntent(value: 0).perform()
        #expect(SharedStore.takeCheckIns().map(\.value) == [5])
        #expect(SharedStore.snapshot()!.lastEnergy == 5)
    }

    @Test func deepLinksAcceptOnlyKnownScreensWithoutData() {
        for d in DeepLink.allCases { #expect(DeepLink.parse(d.url) == d) }
        #expect(DeepLink.parse(URL(string: "resetai://checkin")!) == .checkIn)
        #expect(DeepLink.parse(URL(string: "resetai://unknown")!) == nil)
        #expect(DeepLink.parse(URL(string: "https://food")!) == nil)
        #expect(DeepLink.parse(URL(string: "resetai://food/../../x")!) == nil)
        #expect(DeepLink.parse(URL(string: "otherapp://food")!) == nil)
    }
}
