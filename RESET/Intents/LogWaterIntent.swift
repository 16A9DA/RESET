import AppIntents
import SwiftData

/// Shortcuts, Siri and the Action button can log water without opening the app.
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log water"
    static var description = IntentDescription("Adds a glass of water to today's total in RE:SET.")

    @Parameter(title: "Amount in ml", default: 250)
    var ml: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (50...3000).contains(ml) else { return .result(dialog: "Pick an amount between 50 and 3000 ml.") }
        let context = ModelContext(Store.container())
        context.insert(WaterRecord(ml: Double(ml)))
        try context.save()
        return .result(dialog: "Logged \(ml) ml of water.")
    }
}

struct ResetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water in \(.applicationName)", "Add water to \(.applicationName)"],
                    shortTitle: "Log water", systemImageName: "drop")
    }
}
