import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile
    @State private var step = 0
    @State private var remindersOn = true

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
            .background(Theme.background)
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
                Text("Your phone collects the data. The app turns it into simple, honest daily guidance.")
                    .font(.title3)
                Card(title: "Good to know") {
                    Text("Calorie needs, energy use, sleep and food photo results are estimates. They are meant to guide habits, not to diagnose or treat anything.")
                    Text("Every question after this one is optional, and you can change any answer later in Settings. Without a detail, RE:SET shows a clearly labeled general estimate.")
                    Text("Your data stays on this iPhone unless you set up an AI service.")
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
        }
        .padding()
    }

    private func finish() {
        profile.onboardingDone = true
        context.insert(ReminderPreference(key: "master", enabled: remindersOn, value: 0))
        try? context.save()
    }
}
