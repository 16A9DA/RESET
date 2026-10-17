import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Bindable var profile: UserProfile
    @State private var step = 0
    @State private var remindersOn = true
    @State private var agreed = false
    @State private var healthConsent = false

    private let lastStep = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressBar(fraction: Double(step + 1) / Double(lastStep + 1))
                    .padding(.horizontal).padding(.top, 8)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: Form { BodySection(profile: profile) }
                    case 2: Form { GoalSection(profile: profile) }
                    case 3: Form { ScheduleSection(profile: profile) }
                    default: habits
                    }
                }
                .scrollContentBackground(.hidden)
                footer
            }
            .background(GlassBackdrop())
            .navigationTitle(["Welcome", "About you", "Your goal", "Your schedule", "Habits"][step])
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("RE:SET AI")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("Your phone does the tracking. You get one clear next step.")
                    .font(.title3)
                Text("Estimates only, not medical advice. Your data stays on this iPhone.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("I am 16 or older and agree to the Terms of Use", isOn: $agreed).font(.subheadline)
                    Toggle("I consent to RE:SET AI processing my health data on this iPhone: food, weight, sleep, activity, Apple Health data and visits to places I save. I can withdraw this any time in Settings.", isOn: $healthConsent).font(.subheadline)
                    LegalLinks()
                }
            }
            .padding()
        }
    }

    private var habits: some View {
        Form {
            HabitsSection(profile: profile)
            Section {
                Toggle("Gentle reminders for water, meals and sleep", isOn: $remindersOn)
            } footer: {
                Text("iOS will ask for notification permission when reminders are first scheduled. You can fine tune each category in Settings.")
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Back") { withAnimation { step -= 1 } } }
            Spacer()
            Button(step == lastStep ? "Finish" : "Next") {
                if step == lastStep { finish() } else { withAnimation { step += 1 } }
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            .disabled(step == 0 && !(agreed && healthConsent))
        }
        .padding()
    }

    private func finish() {
        profile.onboardingDone = true
        Consent.record()
        context.insert(ReminderPreference(key: "master", enabled: remindersOn, value: 0))
        try? context.save()
        Task { await health.requestAccess(); health.startBackgroundSync(context: context) }
    }
}
