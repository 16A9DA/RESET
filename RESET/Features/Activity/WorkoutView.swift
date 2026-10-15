import SwiftUI
import SwiftData
import ResetCore

extension UserProfile {
    var trainingLevel: TrainingLevel {
        get { TrainingLevel(rawValue: trainingLevelRaw) ?? .returning }
        set { trainingLevelRaw = newValue.rawValue }
    }
}

enum WorkoutContextBuilder {
    static func build(context: ModelContext, profile: UserProfile?, minutes: Int, planned: Bool, band: RecoveryBand, symptoms: Bool,
                      avgSteps: Int?) -> WorkoutContext {
        let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let done = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        // Planned sessions without a completed record in the following 12 h count as missed.
        var past: [PastSession] = done.map { r in
            let kind: ActivityKind = r.title.lowercased().contains("walk") ? .walk : (r.title.lowercased().contains("mobility") ? .mobility : .strength)
            return PastSession(kind: kind, title: r.title, day: r.start, completed: r.completed)
        }
        for p in plans where p.kind == .strength && p.day < Date.now.addingTimeInterval(-12 * 3600)
            && !done.contains(where: { $0.planID == p.id && $0.completed }) {
            past.append(PastSession(kind: .strength, title: p.title, day: p.day, completed: false))
        }
        return WorkoutContext(band: band, symptoms: symptoms, equipment: profile?.equipment ?? .gym,
                              level: profile?.trainingLevel ?? .returning, minutesAvailable: minutes,
                              goal: profile?.goal ?? .fatLossKeepMuscle, gymDaysPerWeek: profile?.gymDaysPerWeek ?? 3,
                              recent: past, avgSteps: avgSteps, planned: planned)
    }
}

struct WorkoutCard: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query private var profiles: [UserProfile]
    @Query private var checks: [CheckIn]
    @Query private var plans: [WorkoutPlan]
    @Query private var records: [WorkoutRecord]
    @State private var minutes = 45
    @State private var gymToday = true
    @State private var suggestion: WorkoutSuggestion?
    @State private var showing = false

    var body: some View {
        Card(title: "Today's workout") {
            Stepper("Time available: \(minutes) min", value: $minutes, in: 10...90, step: 5)
            Toggle("Gym or home session planned today", isOn: $gymToday)
            Button("Suggest a workout") { generate() }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            if let todays = plans.filter({ Calendar.current.isDateInToday($0.day) }).max(by: { $0.createdAt < $1.createdAt }) {
                Button { showing = true } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(todays.title).font(.headline)
                            Text("\(todays.minutes) min").font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        if records.contains(where: { $0.planID == todays.id && $0.completed }) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                        } else { Image(systemName: "chevron.right") }
                    }
                }.buttonStyle(.plain)
            }
            Text("Standing and walking through a work shift helps, but it is not counted as a workout.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $showing) {
            if let p = plans.filter({ Calendar.current.isDateInToday($0.day) }).max(by: { $0.createdAt < $1.createdAt }) { WorkoutDetail(plan: p) }
        }
    }

    private func generate() {
        let profile = profiles.first
        let r = RecoverySnapshot.assess(context: context, profile: profile)
        let symptoms = checks.contains { $0.kind == .symptom && $0.at > Date.now.addingTimeInterval(-24 * 3600) }
        let avg = health.week.isEmpty ? nil : health.week.map(\.steps).reduce(0, +) / health.week.count
        let c = WorkoutContextBuilder.build(context: context, profile: profile, minutes: minutes, planned: gymToday, band: r.band, symptoms: symptoms, avgSteps: avg)
        let s = WorkoutGenerator.suggest(c)
        let plan = WorkoutPlan(day: .now, title: s.title, kind: s.kind, minutes: s.minutes,
                               exercises: s.exercises.map { PlannedExercise(name: $0.name, sets: $0.sets, reps: $0.reps, restSec: $0.restSec, modification: $0.modification) },
                               stepTarget: s.stepTarget, reason: s.reason)
        context.insert(plan)
        try? context.save()
        showing = true
    }
}

struct WorkoutDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    @Query private var records: [WorkoutRecord]
    @State private var effort = 3

    private var done: Bool { records.contains { $0.planID == plan.id && $0.completed } }

    var body: some View {
        NavigationStack {
            List {
                Section { Text(plan.reason).font(.subheadline) }
                if let steps = plan.stepTarget { Section { Text("Step target for the day: about \(steps.formatted()). Based on your own recent average, not a fixed goal.") } }
                if !plan.exercises.isEmpty {
                    Section("Exercises") {
                        ForEach(plan.exercises, id: \.name) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).font(.headline)
                                Text("\(e.sets) x \(e.reps), rest \(e.restSec) s").font(.footnote).foregroundStyle(Theme.secondaryText)
                                if let m = e.modification { Text("Easier: \(m)").font(.caption).foregroundStyle(Theme.secondaryText) }
                            }
                        }
                    }
                }
                Section {
                    Picker("How hard was it?", selection: $effort) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                    Button(done ? "Logged" : "Mark as done") { complete() }.disabled(done)
                    Text("Stop if anything hurts or feels wrong. This is general guidance, not a prescription.").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle(plan.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { dismiss() } }
        }
    }

    private func complete() {
        let start = Date.now.addingTimeInterval(-Double(plan.minutes) * 60)
        let w = WorkoutRecord(planID: plan.id, title: plan.title, start: start, minutes: plan.minutes, completed: true)
        w.perceivedEffort = effort
        context.insert(w)
        context.insert(ActivityRecord(kind: plan.kind, start: start, end: .now, source: .manual))
        try? context.save()
        dismiss()
    }
}
