import SwiftUI
import SwiftData
import ResetCore

struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    @AppStorage("appearance") private var appearance = "dark"

    var body: some View {
        if let p = profiles.first {
            Form {
                Section {
                    NavigationLink("Places and location") { PlacesView() }
                    NavigationLink("Reminders") { RemindersSettingsView() }
                    NavigationLink("AI and data sources") { AISettingsView(profile: p) }
                    NavigationLink("Calories, protein and water") { TargetsSettingsView(profile: p) }
                } header: { Text("Setup") }
                Section {
                    NavigationLink("About you") { Form { BodySection(profile: p) }.navigationTitle("About you") }
                    NavigationLink("Goal and training") { Form { GoalSection(profile: p) }.navigationTitle("Goal and training") }
                    NavigationLink("Schedule") { Form { ScheduleSection(profile: p) }.navigationTitle("Schedule") }
                    NavigationLink("Food and caffeine habits") { Form { HabitsSection(profile: p) }.navigationTitle("Habits") }
                } header: { Text("Profile") } footer: {
                    Text("Every answer from setup can be changed here. Leaving details blank keeps features working with clearly labeled general estimates.")
                }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("Match system").tag("system")
                    }.pickerStyle(.segmented)
                }
                Section {
                    NavigationLink("Privacy and data") { PrivacyView() }
                    NavigationLink("How it works and limits") { AboutView() }
                }
            }
            .navigationTitle("Settings")
        } else {
            EmptyNote(systemImage: "person.crop.circle", title: "No profile", message: "Finish setup to edit your profile.")
        }
    }
}

struct TargetsSettingsView: View {
    @Bindable var profile: UserProfile

    private var maintenanceText: Binding<Double> {
        Binding(get: { profile.maintenanceOverrideKcal ?? 0 }, set: { profile.maintenanceOverrideKcal = $0 > 0 ? $0 : nil })
    }
    private var waterText: Binding<Double> {
        Binding(get: { profile.waterGoalMl ?? 0 }, set: { profile.waterGoalMl = $0 > 0 ? $0 : nil })
    }

    var body: some View {
        let plan = profile.energyPlan
        Form {
            Section {
                Toggle("Count calories", isOn: $profile.calorieCountingEnabled)
            } footer: {
                Text("Turn this off if counting becomes stressful. Protein, meals, water and everything else keep working.")
            }
            if profile.calorieCountingEnabled {
                Section("Estimates") {
                    row("Resting energy", plan.bmr)
                    row("Maintenance", plan.maintenanceKcal)
                    row("Suggested intake", plan.targetKcal)
                    ForEach(plan.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.secondaryText) }
                }
                Section {
                    HStack {
                        Text("My maintenance (kcal)")
                        Spacer()
                        TextField("Auto", value: maintenanceText, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    Stepper("Deficit: \(Int(profile.deficitPercent * 100))% (max 500 kcal)", value: $profile.deficitPercent, in: 0...0.25, step: 0.05)
                } header: { Text("Adjust") } footer: {
                    Text("Start moderate. If your weight trend over several weeks does not move as expected, adjust maintenance rather than cutting harder. Logged workouts are not added on top, because the activity level you chose already includes them. No fast or crash targets are offered, and fat loss cannot be aimed at one area like the stomach.")
                }
            }
            Section("Protein") {
                Stepper("\(String(format: "%.1f", profile.proteinPerKg)) g per kg: about \(Int(plan.proteinG.rounded())) g a day", value: $profile.proteinPerKg, in: 1.0...2.4, step: 0.1)
            }
            Section {
                Toggle("I have a fluid restriction", isOn: $profile.fluidRestriction)
                if !profile.fluidRestriction {
                    HStack {
                        Text("Daily goal (ml)")
                        Spacer()
                        TextField("\(Int(Energy.waterGoalMl(weightKg: profile.weightKg)))", value: waterText, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                }
            } header: { Text("Water") } footer: { Text(Hydration.goalNote) }
        }
        .navigationTitle("Targets")
    }

    private func row(_ title: String, _ v: Double?) -> some View {
        HStack { Text(title); Spacer(); Text(v.map { "\(Int($0.rounded())) kcal" } ?? "Estimate unavailable").foregroundStyle(Theme.secondaryText) }
    }
}
