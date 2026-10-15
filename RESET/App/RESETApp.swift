import SwiftUI
import SwiftData

@main
struct RESETApp: App {
    let container = Store.container()
    @State private var tracker = LocationTracker()
    @State private var health = HealthService()
    @State private var notifier = NotificationScheduler()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(tracker)
                .environment(health)
                .environment(notifier)
                .task {
                    notifier.setup(container: container)
                    await tracker.start(context: container.mainContext)
                    await notifier.rebuild(context: container.mainContext)
                }
                .onChange(of: phase) { _, new in
                    if new == .active {
                        Task {
                            await tracker.start(context: container.mainContext)
                            await notifier.rebuild(context: container.mainContext)
                        }
                    }
                }
        }
        .modelContainer(container)
    }
}
