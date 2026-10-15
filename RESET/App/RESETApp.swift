import SwiftUI
import SwiftData

@main
struct RESETApp: App {
    let container = Store.container()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
