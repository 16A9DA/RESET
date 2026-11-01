import SwiftUI
import SwiftData
import Charts
import ResetCore

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !health.authRequested { healthCard }
                    stepsCard
                    WalkCard()
                    ListGroup {
                        NavigationLink { SleepView() } label: { GroupRow(title: "Sleep", icon: "moon.fill", tint: Theme.sleep) }.buttonStyle(Press())
                        GroupDivider()
                        NavigationLink { TimeTrackingView() } label: { GroupRow(title: "Work and university", icon: "briefcase", tint: Theme.carbs) }.buttonStyle(Press())
                    }
                }
                .padding()
            }
            .background(GlassBackdrop())
            .navigationTitle("Activity")
            .task {
                await health.refresh()
                await health.importWorkouts(since: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now, context: context)
            }
            .refreshable { await health.refresh() }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Label("Steps", systemImage: "figure.walk").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.steps)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(health.todaySteps.map { $0.formatted() } ?? "None").font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit()
                Text("/ 8,000").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            ProgressBar(fraction: Double(health.todaySteps ?? 0) / 8000, tint: Theme.steps).frame(height: 6)
            if !health.week.isEmpty {
                Chart(health.week) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Steps", d.steps), width: .fixed(10))
                        .foregroundStyle(d.steps >= 8000 ? Theme.steps : Theme.steps.opacity(0.4)).clipShape(Capsule())
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2) } }
                .frame(height: 70)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18).glass(24)
    }
}

struct WalkCard: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @AppStorage("walk.start") private var startTS: Double = 0
    @AppStorage("walk.skipDay") private var skipDay: Double = 0
    @State private var saving = false

    private var skipped: Bool { skipDay == Calendar.current.startOfDay(for: .now).timeIntervalSince1970 }

    var body: some View {
        Card {
            if startTS > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    BigMetric(value: elapsed(ctx.date), caption: "Walk in progress")
                }
                Button(saving ? "Saving" : "Finish walk") { Task { await finish() } }
                    .buttonStyle(.borderedProminent).tint(Theme.low).disabled(saving)
                Button("Discard", role: .destructive) { startTS = 0 }.font(.footnote)
            } else if skipped {
                Text("No walk today. That is fine.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                Button("Undo") { skipDay = 0 }.font(.footnote.weight(.semibold))
            } else {
                HStack(spacing: 10) {
                    Button { startTS = Date.now.timeIntervalSince1970 } label: {
                        Label("Start walk", systemImage: "figure.walk").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(Press())
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
                    Button { skipDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970 } label: {
                        Text("Can't today").font(.headline).padding(.horizontal, 16).frame(minHeight: 46)
                    }
                    .buttonStyle(Press())
                    .background(Theme.raised, in: Capsule())
                }
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
