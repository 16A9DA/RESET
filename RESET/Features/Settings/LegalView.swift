import SwiftUI

/// Fill these in before release. Empty values are left out of the text instead of showing a placeholder.
enum LegalInfo {
    static let appName = "RE:SET AI"
    static let publisher = ""
    static let contactEmail = ""
    /// Postal address of the publisher. GDPR Article 13 needs the controller identity and contact details.
    static let address = ""
    static let governingLaw = ""
    static let updated = "October 2026"
    /// Bump when consent wording changes. Everyone is asked again.
    static let version = 1
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
            .init(title: "Who is responsible", body: "\(LegalInfo.publisher.isEmpty ? "The developer of this app" : LegalInfo.publisher)\(LegalInfo.address.isEmpty ? "" : ", \(LegalInfo.address)") (\"we\") is the controller of your data under the GDPR. We run no accounts and no servers that store your data. Most of it never leaves your iPhone. We have not appointed a data protection officer."),
            .init(title: "What the app holds", body: "Only what you enter or allow: your profile (height, weight, age if given, goal), food and drink logs and meal photos you choose to analyze, water, caffeine, sleep, weight, energy and fatigue check-ins, workouts, places you save, and times at work, university and the gym. If you allow it, it also reads steps, distance, workouts, sleep and weight from Apple Health. Food, weight, sleep, activity and Health data are health data. Place and visit data can reveal where you are, so it is treated as sensitive too."),
            .init(title: "Why we use it, and on what basis", body: "To run the app for you: show your day, record time at saved places, plan reminders and give estimates and suggestions. Where the law requires a legal basis (EU and UK), it is your explicit consent, which you give on the first screen and can withdraw at any time. You can also consent separately to AI processing."),
            .init(title: "Where it is stored", body: "On your iPhone, in the app's private storage. A readable copy (CSV and JSON) is kept in the Files app so you can open, share or delete it. Anyone who can unlock your iPhone can open that copy. If you use iCloud Backup or a computer backup, iOS may include this data in the backup under your Apple settings, and we do not control that."),
            .init(title: "Location", body: "With your permission the app watches circles around places you save and records when you arrive and leave. It does not record your route. Coordinates and your location history stay on your iPhone and are never sent anywhere. Arrival and departure events are deleted after 30 days. Saved places and visit times stay until you delete them. Places you save are never used to track you or to send you messages about health care."),
            .init(title: "Apple Health", body: "Health data is read only with your permission. It is used on your device. It is never sold and never used for advertising, marketing or data mining. You can change access at any time in the Health app."),
            .init(title: "Sharing with AI providers (optional)", body: "AI is off. If you turn it on and give permission for a provider (Anthropic, OpenAI, or a service you set up), the app sends that provider: the food text or meal photo you submit; your questions to the coach; and, when the coach looks things up to answer, summary figures such as today's calories, protein, water, caffeine, steps, sleep hours, weight, workouts, and hours at work, university and the gym. It does not send coordinates, place names or raw Apple Health records. The provider processes this under its own privacy policy and may store it, and its servers may be outside your country. Use your own account and read its policy. Withdraw permission in Settings at any time and nothing more is sent. Data already sent is held by the provider and must be deleted with them."),
            .init(title: "Other services", body: "Food searches send your search words to USDA FoodData Central. Barcode lookups send the number to Open Food Facts. Nothing that identifies you is attached. Those services may see your IP address."),
            .init(title: "We do not sell your data", body: "We do not sell or rent your data, do not share it for advertising, and use no advertising or analytics tools."),
            .init(title: "How long we keep it", body: "On your device until you delete it. Delete work and location history, food logs, coach chats or everything in Settings, Privacy and data. Deleting the app removes its data from your iPhone, but copies in backups or in the Files app may remain until you delete them."),
            .init(title: "Your rights", body: "Depending on where you live (for example the EU, UK, California or Washington) you may have the right to access, correct, export, delete and port your data, to withdraw consent, and to complain to a regulator. Because we hold no copy, the tools in Settings, Privacy and data (export, delete, withdraw consent) cover these. For anything else, contact us."),
            .init(title: "No decisions about you", body: "The app gives estimates and suggestions. It makes no automated decision that has legal or similarly significant effect on you."),
            .init(title: "Security and breaches", body: "Data is protected by iOS encryption and your passcode. API keys are in the iOS Keychain on this device only. No system is perfectly secure. If we learn of a breach affecting data we hold, we will tell affected people and regulators as the law requires."),
            .init(title: "Children", body: "The app is not for anyone under 16. We do not knowingly collect data from children. If you think a child has used it, delete the data in Settings and contact us."),
            .init(title: "EU and UK (GDPR)", body: "Legal basis: your explicit consent (GDPR Articles 6(1)(a) and 9(2)(a)), given on the first screen and separately for AI. You may withdraw it at any time without affecting what happened before. You have the rights to access, rectification, erasure, restriction, portability and objection, and to lodge a complaint with your national data protection authority. Providing data is voluntary, but the app cannot work without the data you choose to give it."),
            .init(title: "Transfers outside the EU", body: "Nothing leaves your iPhone unless you turn on AI. If you do, the provider you chose (Anthropic or OpenAI are in the United States) receives the data described above. That country may not give the same level of protection as the EU, and public authorities there may be able to access it. The transfer is based on your explicit consent (GDPR Article 49(1)(a)), given with this warning, or on the provider's own safeguards where it has them. Do not turn AI on if you are not comfortable with this. Everything else works without it."),
            .init(title: "AI chat", body: "The coach is an AI system, not a person or a health professional. Its answers are generated and can be wrong."),
            .init(title: "California", body: "We do not sell or share personal information, and we use sensitive personal information only to provide the app you asked for."),
            .init(title: "Changes", body: "If we change this policy we will show the new version in the app with a new date. If the change needs your consent, we will ask again."),
        ])
    }
}

/// Washington My Health My Data Act asks for a standalone notice reached through its own link.
struct ConsumerHealthDataPolicyView: View {
    var body: some View {
        LegalDocument(title: "Consumer Health Data Policy", sections: [
            .init(title: "Categories of consumer health data", body: "Food and drink intake, nutrition estimates, weight, sleep, energy and fatigue check-ins, workouts and physical activity, steps, water and caffeine intake, and data you allow the app to read from Apple Health. Times at gyms, work and university places you save."),
            .init(title: "Purposes", body: "To show your day, estimate calories and protein, plan reminders and workouts, record time at saved places and give wellness suggestions. Only to provide the app you asked for."),
            .init(title: "Sources", body: "You, Apple Health (with your permission), your iPhone's motion sensor, and your iPhone's location services for places you save."),
            .init(title: "What is shared and with whom", body: "Nothing is shared by default. If you turn on AI and give separate permission, the categories in the Privacy Policy section Sharing with AI providers are sent to the provider you chose (Anthropic, OpenAI or a service you configure). Food and barcode lookups send only search words or a barcode number to USDA FoodData Central and Open Food Facts. We share data with no one else and sell none."),
            .init(title: "Consent", body: "You give consent to collect and use this data on the first screen, separately from the Terms of Use. You give a second, separate consent before anything is shared with an AI provider. You can withdraw either at any time in Settings."),
            .init(title: "Your rights", body: "You can confirm what the app holds, see it, export it, withdraw consent and delete it in Settings, Privacy and data. Deleting removes it from the app. Because the data is on your device, requests are met immediately. For help, contact us and we will reply within 45 days."),
            .init(title: "Geofencing", body: "The app never uses a virtual boundary around a health care facility to identify, track or message you. Places are saved by you and stay on your device."),
        ])
    }
}

struct TermsView: View {
    var body: some View {
        LegalDocument(title: "Terms of Use", sections: [
            .init(title: "Agreement", body: "By using \(LegalInfo.appName) you agree to these terms and confirm you are 16 or older. If you do not agree, do not use the app."),
            .init(title: "Not medical advice", body: "The app gives general wellness information and estimates. It is not a medical device and does not diagnose, treat, cure or prevent any condition. Calorie, energy, sleep, recovery, food photo and AI results are estimates and can be wrong. Do not use the app in place of a doctor or dietitian. Talk to one before changing your diet or exercise, especially if you have a health condition, take medicine, are pregnant, are under 18, or have had an eating disorder. Stop and get medical help if you feel unwell. In an emergency call your local emergency number."),
            .init(title: "Allergies and food safety", body: "The app cannot detect allergens or ingredients. A check that finds nothing does not mean a food is safe. Always read the label and ask the maker. Do not rely on the app for any allergy, intolerance or medical diet."),
            .init(title: "AI results", body: "The coach and food analysis are AI systems, not people. AI output can be wrong, incomplete or out of date. Check it before acting. You decide whether to use AI, you supply your own account and key, and you are responsible for charges and for the provider's terms."),
            .init(title: "Automatic tracking", body: "Times from location are estimates. iOS can delay or miss arrivals and departures. Do not use the app as proof of hours worked, for pay, attendance, legal or contractual purposes."),
            .init(title: "Your responsibility", body: "You are responsible for what you enter and for how you use the app and its suggestions. Use it lawfully. Do not copy, reverse engineer or disrupt it."),
            .init(title: "No warranty", body: "The app is provided as is and as available, without warranties of any kind, including fitness for a particular purpose, accuracy or uninterrupted use, to the extent the law allows."),
            .init(title: "Limit of liability", body: "To the extent the law allows, the publisher is not liable for indirect, incidental or consequential loss, for loss of data, or for harm from relying on estimates or suggestions. Nothing here limits liability that cannot be limited by law, including for death or personal injury caused by negligence, or for fraud. Consumer rights you have under local law are not affected."),
            .init(title: "Your data", body: "Your data is yours. How we handle it is explained in the Privacy Policy and the Consumer Health Data Policy."),
            .init(title: "Changes and ending", body: "We may change these terms or the app. If a change matters, we will tell you in the app. Continued use after that means you accept it. You can stop at any time and delete your data in Settings."),
        ] + (LegalInfo.governingLaw.isEmpty ? [] : [.init(title: "Governing law", body: "These terms are governed by the laws of \(LegalInfo.governingLaw). Mandatory consumer protections where you live still apply.")]))
    }
}

/// Shown on the first screen and in Settings so the agreement is visible, not buried.
struct LegalLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            NavigationLink("Terms of Use") { TermsView() }
            NavigationLink("Health Data Policy") { ConsumerHealthDataPolicyView() }
        }
        .font(.footnote)
    }
}

/// Records what you agreed to and when, so it can be shown back to you and asked again if the wording changes.
enum Consent {
    static let dateKey = "consent.health.date", versionKey = "consent.health.version"
    static func record() {
        UserDefaults.standard.set(Date.now, forKey: dateKey)
        UserDefaults.standard.set(LegalInfo.version, forKey: versionKey)
    }
    static var date: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }
    static var current: Bool { UserDefaults.standard.integer(forKey: versionKey) >= LegalInfo.version }
    static func clear() {
        [dateKey, versionKey].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
