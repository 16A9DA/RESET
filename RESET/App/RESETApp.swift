import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct RESETApp: App {
    let container = Store.container()
    @State private var tracker = LocationTracker()
    @State private var health = HealthService()
    @State private var notifier = NotificationScheduler()
    @State private var router = AppRouter()
    @State private var coach = CoachModel()
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "dark"

    private var scheme: ColorScheme? {
        switch appearance { case "light": .light; case "system": nil; default: .dark }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(scheme)
                .environment(tracker)
                .environment(health)
                .environment(notifier)
                .environment(router)
                .environment(coach)
                .task {
                    notifier.setup(container: container)
                    coach.configure(container: container, health: health)
                    await tracker.start(context: container.mainContext)
                    await notifier.rebuild(context: container.mainContext)
                }
                .onChange(of: phase) { _, new in
                    if new == .background { Self.scheduleRefresh() }
                    if new == .active {
                        Task {
                            await tracker.start(context: container.mainContext)
                            await notifier.rebuild(context: container.mainContext)
                        }
                    }
                }
        }
        .modelContainer(container)
        // Best effort. iOS decides if and when this runs.
        .backgroundTask(.appRefresh(Self.refreshID)) {
            await notifier.rebuild(context: container.mainContext)
            await MainActor.run { Self.scheduleRefresh() }
        }
    }

    static let refreshID = "com.reset.ai.refresh"

    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshID)
        req.earliestBeginDate = Date.now.addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
}
