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
                VStack(spacing: 12) {
                    if !health.authRequested { healthCard }
                    stepsCard
                    WalkCard()
                    navRow("Workout", icon: "dumbbell") { ScrollView { WorkoutCard().padding() }.background(Theme.background).navigationTitle("Workout") }
                    navRow("Sleep", icon: "moon") { SleepView() }
                    navRow("Work and university", icon: "briefcase") { TimeTrackingView() }
                    history
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { recording = true } label: { Image(systemName: "plus") }.accessibilityLabel("Record a workout") }
            }
            .task {
                await health.refresh()
                await health.importWorkouts(since: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now, context: context)
            }
            .refreshable { await health.refresh() }
            .sheet(isPresented: $recording) { WorkoutSheet() }
        }
    }

    private func navRow<D: View>(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(Press())
    }

    private var healthCard: some View {
        Card {
            Label("Apple Health", systemImage: "heart").font(.headline)
            Button("Connect for steps and workouts") { Task { await health.requestAccess() } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            if let m = health.message { Text(m).font(.footnote).foregroundStyle(Theme.low) }
        }
    }

    private var stepsCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label("Steps", systemImage: "figure.walk").font(.headline)
                Spacer()
                Text(health.todaySteps.map { $0.formatted() } ?? "None").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            }
            if !health.week.isEmpty {
                Chart(health.week) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Steps", d.steps))
                        .foregroundStyle(Theme.accent)
                }
                .frame(height: 90)
            }
        }
    }

    @ViewBuilder private var history: some View {
        let recent = ActivityMath.dedupe(spans).sorted { $0.start > $1.start }.prefix(5)
        if !recent.isEmpty {
            Card(title: "Recent") {
                ForEach(Array(recent), id: \.id) { s in
                    if let r = records.first(where: { $0.id == s.id }) {
                        HStack {
                            Text(r.kind.rawValue.capitalized).font(.headline)
                            Spacer()
                            Text("\(r.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())), \(Int(r.minutes)) min")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        .contextMenu { Button("Delete", role: .destructive) { context.delete(r); try? context.save() } }
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
        Card {
            if startTS > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    BigMetric(value: elapsed(ctx.date), caption: "Walk in progress")
                }
                Button(saving ? "Saving" : "Finish walk") { Task { await finish() } }
                    .buttonStyle(.borderedProminent).tint(Theme.low).disabled(saving)
                Button("Discard", role: .destructive) { startTS = 0 }.font(.footnote)
            } else {
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
