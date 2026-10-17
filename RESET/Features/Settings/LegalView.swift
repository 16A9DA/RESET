import SwiftUI

/// Fill these in before release. Empty values are left out of the text instead of showing a placeholder.
enum LegalInfo {
    static let appName = "RE:SET AI"
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
            .init(title: "Summary", body: "\(LegalInfo.appName) keeps your data on your iPhone. We have no account system and no server that stores your information."),
            .init(title: "What we collect", body: "Only what you enter or allow: profile details, food and drink logs, water, sleep, check-ins, work and university times, and Apple Health data you choose to share. All of it is stored on your device."),
            .init(title: "Location", body: "If you allow it, the app watches circles around places you save, such as your office, to note when you arrive and leave. It does not record your route. Coordinates and location history are never sent anywhere."),
            .init(title: "Apple Health", body: "Health data is read only with your permission, used on your device to show steps, sleep and workouts, and never sold or used for advertising."),
            .init(title: "Services that receive data", body: "If you add an AI key, the food text or photo you submit and the questions you ask the coach go to the AI provider you chose, under its own policy. Food searches send your search words to USDA FoodData Central. Barcode lookups send the number to Open Food Facts. Nothing else leaves your phone."),
            .init(title: "Your choices", body: "You can delete work and location history, food logs, coach conversations, or everything, at any time in Settings under Privacy and data. Deleting the app removes its data from your iPhone. Data in Apple Health is managed in the Health app."),
            .init(title: "Children", body: "The app is not intended for anyone under 16."),
            .init(title: "Changes", body: "If this policy changes, the new version is shown in the app with a new date."),
        ])
    }
}

struct TermsView: View {
    var body: some View {
        LegalDocument(title: "Terms of Use", sections: [
            .init(title: "Using the app", body: "By using \(LegalInfo.appName) you agree to these terms. If you do not agree, do not use the app."),
            .init(title: "Not medical advice", body: "The app gives general wellness guidance. Calories, energy use, sleep, recovery and food photo results are estimates. Nothing here is medical advice, diagnosis or treatment. Talk to a doctor or dietitian before changing your diet or exercise, especially with a health condition, pregnancy or an eating disorder history. If you feel unwell, get medical help. In an emergency, call your local emergency number."),
            .init(title: "AI results", body: "AI output can be wrong or incomplete. Check food and nutrition results, allergens and any suggestion before relying on it. Never rely on the app to detect allergens."),
            .init(title: "Automatic tracking", body: "Location based work and university times are estimates. iOS can deliver arrivals late or miss them. Do not use the app as proof of hours worked or for pay, legal or contractual purposes."),
            .init(title: "Your responsibility", body: "You are responsible for the information you enter and for how you use the app. Use it lawfully and do not try to disrupt or reverse engineer it."),
            .init(title: "No warranty", body: "The app is provided as is and as available, without warranties of any kind, to the extent the law allows."),
            .init(title: "Limit of liability", body: "To the extent the law allows, the developer is not liable for indirect or consequential loss, or for any loss arising from reliance on estimates or from data lost on your device. Nothing in these terms limits liability that cannot be limited by law."),
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
