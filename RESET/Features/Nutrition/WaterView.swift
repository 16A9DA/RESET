import SwiftUI
import SwiftData
import ResetCore

struct WaterCard: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationScheduler.self) private var notifier
    @Query(sort: \WaterRecord.at, order: .reverse) private var records: [WaterRecord]
    @Query private var profiles: [UserProfile]
    @State private var custom = false
    @State private var customMl = 330.0

    private var profile: UserProfile? { profiles.first }
    private var todayMl: Double { records.filter { Calendar.current.isDateInToday($0.at) }.reduce(0) { $0 + $1.ml } }

    var body: some View {
        let goal = profile?.effectiveWaterGoalMl
        Card(title: "Water") {
            HStack(alignment: .firstTextBaseline) {
                BigMetric(value: String(format: "%.2f", todayMl / 1000), unit: "L",
                          caption: goal.map { "Goal about \(String(format: "%.1f", $0 / 1000)) L" }
                            ?? (profile?.fluidRestriction == true ? "Fluid limit set, no target shown" : "No goal set"))
                Spacer()
            }
            if let p = Hydration.progress(totalMl: todayMl, goalMl: goal) { ProgressBar(fraction: p, tint: .cyan) }
            HStack {
                ForEach(profile?.quickWaterMl ?? Hydration.quickDefaults, id: \.self) { ml in
                    Button("+\(ml)") { add(Double(ml)) }
                        .buttonStyle(.bordered).tint(.cyan)
                }
                Button("Other") { custom = true }.buttonStyle(.bordered)
            }
            if let last = records.first {
                Text("Last: \(Int(last.ml)) ml at \(last.at.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let next = notifier.nextWater {
                Text("Next reminder about \(next.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            } else if !notifier.canSchedule {
                Text(notifier.status == .denied ? "Notifications are off in iOS Settings, so there are no reminders." : "Reminders need notification permission.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Text(Hydration.goalNote).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $custom) {
            NavigationStack {
                Form {
                    Stepper("Amount: \(Int(customMl)) ml", value: $customMl, in: 50...1500, step: 50)
                }
                .navigationTitle("Log water").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { custom = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") { add(customMl); custom = false } }
                }
            }.presentationDetents([.height(220)])
        }
    }

    private func add(_ ml: Double) {
        context.insert(WaterRecord(ml: ml))
        try? context.save()
        Task { await notifier.rebuild(context: context) }
    }
}

struct RemindersSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationScheduler.self) private var notifier
    @Query private var prefs: [ReminderPreference]
    @Query private var profiles: [UserProfile]

    private func binding(_ cat: ReminderCategory) -> Binding<Bool> {
        Binding(get: { prefs.first { $0.key == cat.rawValue }?.enabled ?? NotificationScheduler.defaultOn.contains(cat) },
                set: { NotificationScheduler.setEnabled(cat, $0, in: context); rebuild() })
    }

    private var master: Binding<Bool> {
        Binding(get: { prefs.first { $0.key == "master" }?.enabled ?? true },
                set: { on in
                    if let m = prefs.first(where: { $0.key == "master" }) { m.enabled = on }
                    else { context.insert(ReminderPreference(key: "master", enabled: on, value: 0)) }
                    try? context.save(); rebuild()
                })
    }

    private var waterInterval: Binding<Int> {
        Binding(get: { prefs.first { $0.key == ReminderCategory.water.rawValue }?.value ?? 120 },
                set: { v in
                    NotificationScheduler.setEnabled(.water, binding(.water).wrappedValue, value: v, in: context); rebuild()
                })
    }

    var body: some View {
        Form {
            Section {
                if notifier.status == .notDetermined {
                    Button("Allow notifications") { Task { await notifier.requestPermission(); rebuild() } }
                } else if !notifier.canSchedule {
                    Text("Notifications are off for RE:SET. Turn them on in iOS Settings to get reminders.")
                    Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                } else {
                    Text("\(notifier.scheduledCount) reminders scheduled").foregroundStyle(Theme.secondaryText)
                }
                Toggle("All reminders", isOn: master)
            } footer: {
                Text("iOS can only deliver notifications scheduled ahead of time, so RE:SET plans the next day or two and refreshes the plan when you open the app or log something. Reminders are never sent while you are asleep, and missed ones are not repeated.")
            }
            Section("Categories") {
                ForEach(ReminderCategory.allCases, id: \.self) { cat in
                    Toggle(cat.title, isOn: binding(cat))
                }
            }
            Section("Water") {
                Stepper("About every \(waterInterval.wrappedValue / 60) h \(waterInterval.wrappedValue % 60) min", value: waterInterval, in: 90...240, step: 30)
                if let p = profiles.first {
                    ForEach(0..<3, id: \.self) { i in
                        Stepper("Quick button \(i + 1): \(p.quickWaterMl[safe: i] ?? 0) ml",
                                value: Binding(get: { p.quickWaterMl[safe: i] ?? 250 }, set: { v in
                                    var q = p.quickWaterMl; while q.count < 3 { q.append(250) }; q[i] = v; p.quickWaterMl = q }),
                                in: 50...1000, step: 50)
                    }
                    Toggle("I have a fluid restriction", isOn: Bindable(p).fluidRestriction)
                }
            }
        }
        .navigationTitle("Reminders")
        .task { await notifier.refreshStatus() }
    }

    private func rebuild() { Task { await notifier.rebuild(context: context) } }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
