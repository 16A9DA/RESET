import SwiftUI
import SwiftData
import Charts
import ResetCore

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query private var profiles: [UserProfile]
    // Observed so "Your day" refreshes when a night or session changes.
    @Query private var sleeps: [SleepRecord]
    @Query private var sessions: [TrackedSession]

    var body: some View {
        let _ = (sleeps.count, sessions.count)
        let s = DaySummaryBuilder.build(context: context, profile: profiles.first, health: health)
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if !health.authRequested { healthCard }
                    stepsCard
                    WalkCard()
                    yourDay(s)
                }
                .padding(.horizontal).padding(.top, 8)
            }
            .background(GlassBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await health.refresh()
                await health.importWorkouts(since: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now, context: context)
            }
            .refreshable { await health.refresh() }
        }
    }

    private var header: some View {
        PageHeader(title: "Activity", subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) { EmptyView() }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Steps").font(.headline)
                Spacer()
                Image(systemName: "shoeprints.fill").font(.footnote).foregroundStyle(Theme.steps)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(health.todaySteps.map { $0.formatted() } ?? "None").font(.system(size: 48, weight: .bold)).tracking(-1.2).monospacedDigit()
                Text("/ 8,000").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            ProgressBar(fraction: Double(health.todaySteps ?? 0) / 8000, tint: Theme.steps).frame(height: 6)
            if !health.week.isEmpty {
                let last = health.week.last?.day
                Chart(health.week) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Steps", d.steps), width: .fixed(14))
                        .foregroundStyle(d.day == last ? Theme.steps : Theme.raised).clipShape(Capsule())
                }
                .chartYScale(domain: 0...max(8000, health.week.map(\.steps).max() ?? 0))
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2) } }
                .frame(height: 96)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18).glass(24)
    }

    private func yourDay(_ s: DaySummary) -> some View {
        let w = Day.interval(of: .now)
        func range(_ c: SessionCategory) -> String {
            let day = sessions.filter { $0.category == c && w.contains($0.start) && $0.status != .needsReview }.sorted { $0.start < $1.start }
            guard let first = day.first else { return "Not recorded" }
            let end = day.last?.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? "now"
            return "\(first.start.formatted(date: .omitted, time: .shortened))\u{2013}\(end)"
        }
        return VStack(spacing: 8) {
            HStack {
                Text("YOUR DAY").font(.caption.weight(.semibold)).tracking(0.6)
                Spacer()
                Text("Filled automatically").font(.caption)
            }
            .foregroundStyle(Theme.secondaryText).padding(.horizontal, 4).padding(.top, 6)
            ListGroup {
                NavigationLink { SleepView() } label: {
                    GroupRow(title: "Sleep", icon: "moon", value: s.sleepHours.map { Fmt.hours($0 * 3600) } ?? "Not recorded", tint: Theme.sleep, showChevron: false)
                }.buttonStyle(Press())
                GroupDivider()
                NavigationLink { TimeTrackingView() } label: {
                    GroupRow(title: "Work", icon: "briefcase", value: range(.work), showChevron: false)
                }.buttonStyle(Press())
                GroupDivider()
                NavigationLink { TimeTrackingView() } label: {
                    GroupRow(title: "University", icon: "graduationcap", value: range(.university), showChevron: false)
                }.buttonStyle(Press())
            }
        }
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
                Label("No walk today. That is fine.", systemImage: "leaf").font(.headline).labelStyle(TintedIcon(tint: Theme.good))
                Text("Rest is a valid next step. We'll pick this up another day.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                Button { skipDay = 0 } label: { Text("Undo").font(.headline).frame(maxWidth: .infinity, minHeight: 46) }
                    .buttonStyle(Press()).background(Theme.raised, in: Capsule())
            } else {
                Label(Calendar.current.component(.hour, from: .now) >= 17 ? "A little air after work" : "A little air today", systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold)).symbolRenderingMode(.monochrome)
                Text("A gentle 15-minute walk can help you switch off. Only if you feel up to it.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 10) {
                    Button { startTS = Date.now.timeIntervalSince1970 } label: {
                        Text("Start walk").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(Press())
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
                    Button { skipDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970 } label: {
                        Text("Can't today").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
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
