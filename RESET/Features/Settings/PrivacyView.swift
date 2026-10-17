import SwiftUI
import SwiftData
import UserNotifications

struct PrivacyView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationTracker.self) private var tracker
    @Environment(NotificationScheduler.self) private var notifier
    @State private var confirm: Wipe?
    @State private var done: String?
    @State private var exportURLs: [URL] = []

    enum Wipe: String, Identifiable {
        case location, food, chat, everything
        var id: String { rawValue }
        var title: String {
            switch self {
            case .location: "Delete work, university and location history?"
            case .food: "Delete all food, drink and caffeine logs?"
            case .chat: "Delete the coach conversation?"
            case .everything: "Delete everything and start over?"
            }
        }
        var detail: String {
            switch self {
            case .location: "Sessions, place events and saved places are removed. Monitoring stops."
            case .food: "Meals, saved meals, water and caffeine records are removed."
            case .chat: "All coach messages are removed."
            case .everything: "All logs, your profile, API keys, reminders and the copy in Files are removed from this iPhone. This can't be undone. Data in Apple Health is not touched."
            }
        }
    }

    var body: some View {
        Form {
            Section("Where your data lives") {
                text("Everything you log stays on this iPhone in the app's private storage. There is no RE:SET account and no RE:SET server unless you run the optional proxy yourself.")
                text("API keys are kept in the iOS Keychain, only on this device.")
            }
            Section("What leaves the phone") {
                text("Only when you use AI features: the food description or meal photo you submit, the question you type to the coach, and the tool results the coach asks for, such as today's totals. Raw location, place coordinates and location history are never sent.")
                text("Food searches go to USDA FoodData Central and barcode lookups go to Open Food Facts, with only the search text or barcode number.")
                text("Your chosen AI provider has its own data policy. Check it before sending photos.")
            }
            Section("Location") {
                text("RE:SET watches only the circles you save around places. It does not record your route. It keeps arrival and departure events for 30 days and your sessions until you delete them.")
            }
            Section("Health and safety") {
                text("Calorie, energy use, sleep, recovery and food photo values are estimates. They are not medical advice, and nothing here diagnoses or treats a condition. If you feel unwell, get medical help.")
            }
            Section {
                if exportURLs.isEmpty {
                    Button("Export my data") { exportURLs = (try? DataExporter.write(context: context)) ?? [] }
                } else {
                    ShareLink("Share \(exportURLs.count) files", items: exportURLs)
                }
            } header: { Text("Your data") } footer: { Text("A copy is also kept in the Files app under On My iPhone, RE:SET AI, RE-SET Data. It updates when you leave the app.") }
            Section("Delete data") {
                Button("Delete work and location history", role: .destructive) { confirm = .location }
                Button("Delete food, water and caffeine logs", role: .destructive) { confirm = .food }
                Button("Delete coach conversation", role: .destructive) { confirm = .chat }
                Button("Delete everything and reset", role: .destructive) { confirm = .everything }
                if let done { Text(done).font(.footnote).foregroundStyle(Theme.good) }
            }
        }
        .navigationTitle("Privacy and data")
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            if let c = confirm { Button("Delete", role: .destructive) { wipe(c) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(confirm?.detail ?? "") }
    }

    private func text(_ s: String) -> some View { Text(s).font(.subheadline) }

    private func wipe(_ w: Wipe) {
        do {
            switch w {
            case .location:
                try context.delete(model: LocationEvent.self); try context.delete(model: TrackedSession.self); try context.delete(model: Place.self)
            case .food:
                try context.delete(model: MealRecord.self); try context.delete(model: SavedMeal.self)
                try context.delete(model: WaterRecord.self); try context.delete(model: CaffeineRecord.self); try context.delete(model: SavedDrink.self)
                try context.delete(model: PurchaseDraft.self)
            case .chat:
                try context.delete(model: ChatMessage.self)
            case .everything:
                try Store.resetAll(context)
                WidgetBridge.clear()
                [Keychain.usdaKey, Keychain.anthropicKey, Keychain.openAIKey, Keychain.customKey, Keychain.proxyToken].forEach { Keychain.set(nil, for: $0) }
                let d = UserDefaults.standard
                (["walk.start", "health.authRequested", AIConfig.customBaseKey, AIConfig.proxyBaseKey, "appearance"]
                    + AIConfig.Kind.allCases.map { "ai.model.\($0.rawValue)" }).forEach { d.removeObject(forKey: $0) }
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("reset-export"))
                try? FileManager.default.removeItem(at: DataExporter.filesFolder)
            }
            try context.save()
            Task { await tracker.start(context: context); if w != .everything { await notifier.rebuild(context: context) } }
            done = "Deleted."
        } catch {
            done = "Could not delete: \(error.localizedDescription)"
        }
        confirm = nil
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section("How tracking works") {
                Text("Work and university time comes from iOS region monitoring. iOS can deliver arrivals and departures late or miss them, and it cannot give exact clock-in times. Being at a place does not prove you were working, so detected time is labeled an estimate until you confirm it. A manual timer and an editor are always available.").font(.subheadline)
                Text("Steps come from your iPhone through Apple Health or the motion sensor. They can miss activity when the phone is not carried. Sleep is what you enter, or what another device writes to Health. The phone cannot detect sleep on its own.").font(.subheadline)
                Text("Reminders are scheduled ahead of time because iOS does not let apps run code when a notification fires. They are refreshed whenever you open the app or log something.").font(.subheadline)
            }
            Section("About the numbers") {
                Text("Calorie targets use the Mifflin-St Jeor equation and an activity multiplier. The recovery indicator is a rule based summary of your own entries. Insights are patterns, not causes. Food photos cannot reveal exact calories.").font(.subheadline)
            }
            Section("Data sources") {
                Text("Nutrition: USDA FoodData Central (public domain) and Open Food Facts (ODbL).").font(.subheadline)
            }
        }
        .navigationTitle("About")
    }
}
