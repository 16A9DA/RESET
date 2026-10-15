import SwiftUI
import SwiftData

@main
struct RESETApp: App {
    let container = Store.container()
    @State private var tracker = LocationTracker()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(tracker)
                .task { await tracker.start(context: container.mainContext) }
                .onChange(of: phase) { _, new in
                    if new == .active { Task { await tracker.start(context: container.mainContext) } }
                }
        }
        .modelContainer(container)
    }
}
