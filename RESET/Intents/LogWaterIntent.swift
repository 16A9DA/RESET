import AppIntents
import SwiftData
import ResetCore

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
        AppShortcut(intent: AddPurchaseTextIntent(), phrases: ["Add a purchase to \(.applicationName)"],
                    shortTitle: "Add purchase text", systemImageName: "bag")
    }
}

/// Share text from any app (a receipt email or a note) through a Shortcut that runs this action.
/// It only creates drafts to review. Nothing is logged as eaten.
struct AddPurchaseTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Add purchase text"
    static var description = IntentDescription("Finds food and drink items in receipt text and adds them to RE:SET to review. Nothing is logged as eaten until you confirm.")

    @Parameter(title: "Receipt or purchase text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = String(text.prefix(20_000))
        let found = PurchaseParser.parse(trimmed)
        let context = ModelContext(Store.container())
        let n = PurchaseStore.add(found, source: "shortcut", context: context)
        return .result(dialog: n == 0 ? "No new food or drink items found." : "Added \(n) item\(n == 1 ? "" : "s") to review in RE:SET.")
    }
}
