import SwiftUI

/// Fill these in before release. Empty values are left out of the text instead of showing a placeholder.
enum LegalInfo {
    static let appName = "RE:SET AI"
    static let publisher = ""
    static let contactEmail = ""
    static let governingLaw = ""
    static let updated = "October 2026"
}

private struct LegalSection: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}

private struct LegalDocument: View {
    let title: String
    let sections: [LegalSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Last updated \(LegalInfo.updated)").font(.footnote).foregroundStyle(Theme.secondaryText)
                ForEach(sections) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.title).font(.headline)
                        Text(s.body).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
                if !LegalInfo.contactEmail.isEmpty {
                    Text("Questions: \(LegalInfo.contactEmail)").font(.subheadline)
                }
            }
            .padding()
        }
        .background(GlassBackdrop())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocument(title: "Privacy Policy", sections: [
            .init(title: "Who we are", body: "\(LegalInfo.appName) is published by \(LegalInfo.publisher.isEmpty ? "the developer" : LegalInfo.publisher). We have no accounts and no servers that hold your data."),
            .init(title: "What stays on your iPhone", body: "Everything you enter or allow: profile, food and drink logs, water, sleep, check-ins, places, work, university and gym times, and data read from Apple Health. It is stored on your device. A readable copy is kept in the Files app so you can open, share or delete it. Anyone who can unlock your iPhone can open that copy."),
            .init(title: "Location", body: "With your permission the app watches circles around places you save, to note when you arrive and leave. It does not record your route. Coordinates and location history are never sent anywhere. Arrival and departure events are kept for 30 days."),
            .init(title: "Apple Health", body: "Health data is read only with your permission and used on your device. It is never sent to an AI provider, never sold, and never used for advertising or marketing."),
            .init(title: "AI providers", body: "AI is off until you turn it on in Settings and give permission for the provider you choose. Then the text or photo you submit, your questions to the coach, and the daily totals the coach looks up are sent to that provider (Anthropic, OpenAI or a service you configure) using your own key, to produce an answer. The provider processes it under its own privacy policy. You can withdraw permission at any time."),
            .init(title: "Other services", body: "Food searches send your search words to USDA FoodData Central. Barcode lookups send the number to Open Food Facts. No personal profile is attached."),
            .init(title: "Retention and deletion", body: "Data stays until you delete it. In Settings, Privacy and data you can delete work and location history, food logs, coach chats, or everything, and export your data. Deleting the app removes its data from your iPhone. Data in Apple Health is managed in the Health app."),
            .init(title: "Your rights", body: "Depending on where you live, you may have rights to access, correct, export and delete your data, and to withdraw consent. The export and delete tools in the app cover these because the data is only on your device."),
            .init(title: "Security", body: "Data is protected by iOS file protection and your passcode. API keys are in the iOS Keychain on this device only. No method is perfectly secure."),
            .init(title: "Children", body: "The app is not for anyone under 16."),
            .init(title: "Changes", body: "If this policy changes, the new version is shown in the app with a new date."),
        ])
    }
}

struct TermsView: View {
    var body: some View {
        LegalDocument(title: "Terms of Use", sections: [
            .init(title: "Using the app", body: "By using \(LegalInfo.appName) you agree to these terms and confirm you are 16 or older. If you do not agree, do not use the app."),
            .init(title: "Not medical advice", body: "The app gives general wellness guidance. Calories, energy use, sleep, recovery and food photo results are estimates. Nothing here is medical advice, diagnosis or treatment. Talk to a doctor or dietitian before changing your diet or exercise, especially with a health condition, pregnancy, or a history of eating disorders. If you feel unwell, get medical help. In an emergency, call your local emergency number."),
            .init(title: "AI results", body: "AI output can be wrong or incomplete. Check food and nutrition results and any suggestion before relying on it. Never rely on the app to detect allergens or ingredients."),
            .init(title: "Automatic tracking", body: "Location based work, university and gym times are estimates. iOS can deliver arrivals late or miss them. Do not use the app as proof of hours worked, or for pay, legal or contractual purposes."),
            .init(title: "Your responsibility", body: "You are responsible for the information you enter and for how you use the app. Use it lawfully and do not try to disrupt or reverse engineer it."),
            .init(title: "No warranty", body: "The app is provided as is and as available, without warranties of any kind, to the extent the law allows."),
            .init(title: "Limit of liability", body: "To the extent the law allows, the publisher is not liable for indirect or consequential loss, or for loss arising from reliance on estimates or from data lost on your device. Nothing in these terms limits liability that cannot be limited by law, including for death or personal injury caused by negligence, or for fraud."),
            .init(title: "Changes and ending", body: "We may update these terms or the app. Continued use after an update means you accept it. You can stop using the app at any time."),
        ] + (LegalInfo.governingLaw.isEmpty ? [] : [.init(title: "Governing law", body: "These terms are governed by the laws of \(LegalInfo.governingLaw).")]))
    }
}

/// Shown on the first screen and in Settings so the agreement is visible, not buried.
struct LegalLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            NavigationLink("Terms of Use") { TermsView() }
        }
        .font(.footnote)
    }
}
