import SwiftUI
import SwiftData
import ResetCore

struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage(CalendarSync.enabledKey) private var calendarOn = false
    @State private var calendarDenied = false
    @State private var pastAdded: Int?
    @Environment(\.modelContext) private var context

    var body: some View {
        if let p = profiles.first {
            Form {
                Section {
                    LabeledRow("Places and location", "mappin.and.ellipse") { PlacesView() }
                    LabeledRow("Reminders", "bell") { RemindersSettingsView() }
                    LabeledRow("AI and data sources", "sparkles") { AISettingsView(profile: p) }
                    LabeledRow("Calories, protein and water", "flame") { TargetsSettingsView(profile: p) }
                } header: { Text("Setup") }
                Section {
                    LabeledRow("About you", "person") { Form { BodySection(profile: p) }.navigationTitle("About you") }
                    LabeledRow("Goal and training", "target") { Form { GoalSection(profile: p) }.navigationTitle("Goal and training") }
                    LabeledRow("Schedule", "calendar") { Form { ScheduleSection(profile: p) }.navigationTitle("Schedule") }
                    LabeledRow("Food and caffeine habits", "cup.and.saucer") { Form { HabitsSection(profile: p) }.navigationTitle("Habits") }
                } header: { Text("Profile") } footer: {
                    Text("Every answer from setup can be changed here. Leaving details blank keeps features working with clearly labeled general estimates.")
                }
                Section {
                    Toggle("Add sessions to Calendar", isOn: Binding(get: { calendarOn }, set: { on in
                        if on {
                            Task {
                                calendarOn = await CalendarSync.enable()
                                calendarDenied = !calendarOn
                                CalendarSync.sync(context: context)
                            }
                        } else { calendarOn = false }
                    }))
                    if calendarOn {
                        Button("Add past sessions now") { pastAdded = CalendarSync.sync(context: context, includePast: true) }
                        if let n = pastAdded {
                            Text(n == 0 ? "No past sessions left to add." : "Added \(n) past session\(n == 1 ? "" : "s") to your calendar.")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    }
                } footer: {
                    Text(calendarDenied ? "Calendar access is off. Allow it in iOS Settings, then try again."
                         : "When a work, university or gym session ends, its start and end time is added to your calendar. The app can only add events. It never reads your calendar.")
                }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("Match system").tag("system")
                    }.pickerStyle(.segmented)
                }
                Section {
                    LabeledRow("Privacy and data", "lock.shield") { PrivacyView() }
                    LabeledRow("Privacy Policy", "hand.raised") { PrivacyPolicyView() }
                    LabeledRow("Terms of Use", "doc.text") { TermsView() }
                    LabeledRow("Consumer Health Data Policy", "heart.text.square") { ConsumerHealthDataPolicyView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackdrop())
            .listRowBackground(Theme.card)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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

/// Settings row: leading icon, title, chevron from the link.
struct LabeledRow<Dest: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var dest: Dest
    init(_ title: String, _ icon: String, @ViewBuilder dest: () -> Dest) { self.title = title; self.icon = icon; self.dest = dest() }
    var body: some View {
        NavigationLink { dest } label: { Label(title, systemImage: icon).foregroundStyle(.primary) }
    }
}
