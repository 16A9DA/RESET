import SwiftUI
import SwiftData
import Charts
import ResetCore

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query(sort: \ActivityRecord.start, order: .reverse) private var records: [ActivityRecord]
    @State private var recording = false

    private var spans: [ActivitySpan] {
        records.map { ActivitySpan(id: $0.id, kind: $0.kind, start: $0.start, end: $0.end, source: $0.source, steps: $0.steps) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !health.authRequested { healthCard }
                    stepsCard
                    WalkCard()
                    Card(title: "Structured activity today") {
                        let m = ActivityMath.structuredMinutes(spans, in: Day.interval(of: .now))
                        BigMetric(value: m == 0 ? "Not recorded" : "\(Int(m.rounded()))", unit: m == 0 ? "" : "min",
                                  caption: "Walks, runs and workouts only. A day on your feet at work is not counted as training.")
                        Button("Record a workout") { recording = true }
                    }
                    history
                    NavigationLink { TimeTrackingView() } label: {
                        Card(title: "Work and university") {
                            Text("Hours, places and corrections").foregroundStyle(Theme.secondaryText)
                        }
                    }.buttonStyle(.plain)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Activity")
            .task {
                await health.refresh()
                await health.importWorkouts(since: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now, context: context)
            }
            .refreshable { await health.refresh() }
            .sheet(isPresented: $recording) { WorkoutSheet() }
        }
    }

    private var healthCard: some View {
        Card(title: "Apple Health") {
            Text("Connect Health to read steps, distance and workouts from your iPhone and other apps. Without it, RE:SET falls back to the iPhone motion sensor for steps.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Connect Apple Health") { Task { await health.requestAccess() } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            if let m = health.message { Text(m).font(.footnote).foregroundStyle(Theme.low) }
        }
    }

    private var stepsCard: some View {
        Card(title: "Steps today") {
            if let s = health.todaySteps {
                BigMetric(value: s.formatted(), caption: "Source: \(health.stepSource)")
            } else {
                BigMetric(value: "Not recorded", caption: health.authRequested
                          ? "No step data returned. Health access may be off in Settings > Health > Data Access."
                          : "Permission required")
            }
            if let d = health.distanceM, d > 0 {
                Text(String(format: "%.1f km walking and running", d / 1000)).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if !health.week.isEmpty {
                Chart(health.week) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Steps", d.steps))
                        .foregroundStyle(Theme.accent)
                }
                .frame(height: 120)
            }
            Text("Steps come from your iPhone. They can miss activity when the phone is not on you.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var history: some View {
        Card(title: "History") {
            if records.isEmpty {
                EmptyNote(systemImage: "figure.walk", title: "No activity yet",
                          message: "Start a walk or record a workout. Workouts from Apple Health appear here too.")
            }
            ForEach(ActivityMath.dedupe(spans).sorted { $0.start > $1.start }.prefix(20), id: \.id) { s in
                if let r = records.first(where: { $0.id == s.id }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.kind.rawValue.capitalized).font(.headline)
                            Text("\(r.start.formatted(date: .abbreviated, time: .shortened)), \(Int(r.minutes)) min, \(r.source == .imported ? "from Health" : "logged here")")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button(role: .destructive) { context.delete(r); try? context.save() } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete")
                    }
                }
            }
        }
    }
}

struct WalkCard: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @AppStorage("walk.start") private var startTS: Double = 0
    @State private var saving = false

    var body: some View {
        Card(title: "Walk") {
            if startTS > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    BigMetric(value: elapsed(ctx.date), caption: "Walk in progress")
                }
                Button(saving ? "Saving" : "Finish walk") { Task { await finish() } }
                    .buttonStyle(.borderedProminent).tint(Theme.low).disabled(saving)
                Button("Discard", role: .destructive) { startTS = 0 }.font(.footnote)
            } else {
                Text("Time a walk. Steps are read from your iPhone when available.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                Button("Start walk") { startTS = Date.now.timeIntervalSince1970 }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            }
        }
    }

    private func elapsed(_ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince1970 - startTS))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func finish() async {
        saving = true
        let start = Date(timeIntervalSince1970: startTS), end = Date.now
        let steps = await health.motionSteps(from: start, to: end)
        let rec = ActivityRecord(kind: .walk, start: start, end: end, steps: steps, source: .manual)
        context.insert(rec)
        try? context.save()
        await health.saveWalk(start: start, end: end)
        startTS = 0
        saving = false
        await health.refresh()
    }
}

struct WorkoutSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ActivityKind = .strength
    @State private var minutes = 45
    @State private var start = Date.now.addingTimeInterval(-45 * 60)

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(ActivityKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                DatePicker("Started", selection: $start)
                Stepper("Duration: \(minutes) min", value: $minutes, in: 5...240, step: 5)
            }
            .navigationTitle("Record workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(ActivityRecord(kind: kind, start: start, end: start.addingTimeInterval(Double(minutes) * 60), source: .manual))
                        context.insert(WorkoutRecord(title: kind.rawValue.capitalized, start: start, minutes: minutes, completed: true))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
