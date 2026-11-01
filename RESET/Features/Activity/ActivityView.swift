import SwiftUI
import SwiftData
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
                VStack(spacing: 14) {
                    PageHeader(title: "Activity", subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                        Menu { Button("Refresh steps") { Task { await health.refresh() } } } label: { Icon("ellipsis", size: 22) }
                            .foregroundStyle(Theme.text).accessibilityLabel("More")
                    }
                    if !health.authRequested { healthCard }
                    stepsCard
                    WalkCard()
                    yourDay(s)
                }
                .padding(.horizontal, Theme.screenInset).padding(.bottom, 20)
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

    private var healthCard: some View {
        Card {
            CardHeading(icon: "heart-pulse", title: "Apple Health", tint: Theme.accent)
            PillButton(title: "Connect for steps and workouts") { Task { await health.requestAccess() } }
            if let m = health.message { Text(m).font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.low) }
        }
    }

    private var stepsCard: some View {
        let steps = health.todaySteps ?? 0
        return Card {
            HStack {
                Text("Steps").font(Theme.text(Theme.Size.cardTitle, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Icon("footprints", size: 20).foregroundStyle(Theme.steps)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(health.todaySteps.map { $0.formatted() } ?? "None").font(Theme.number(Theme.Size.stepNumber)).tracking(-0.8).foregroundStyle(Theme.text)
                Text("/ 8,000").font(Theme.text(Theme.Size.cardTitle)).foregroundStyle(Theme.secondaryText)
            }
            ProgressBar(fraction: Double(steps) / 8000, tint: Theme.steps)
            if !health.week.isEmpty { weekBars }
        }
    }

    /// Seven rounded bars, today in lime, the days before in the raised grey. Bar height follows the day's steps.
    private var weekBars: some View {
        let top = Double(max(8000, health.week.map(\.steps).max() ?? 0))
        let lastDay = health.week.last?.day
        return HStack(alignment: .bottom) {
            ForEach(health.week) { d in
                let today = d.day == lastDay
                VStack(spacing: 7) {
                    Capsule().fill(today ? Theme.steps : Theme.raised).frame(width: 13, height: max(8, Double(d.steps) / top * 70))
                    Text(d.day.formatted(.dateTime.weekday(.narrow))).font(Theme.text(Theme.Size.tab))
                        .foregroundStyle(today ? Theme.text : Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 91, alignment: .bottom)
    }

    private func yourDay(_ s: DaySummary) -> some View {
        let w = Day.interval(of: .now)
        func range(_ c: SessionCategory) -> String {
            let day = sessions.filter { $0.category == c && w.contains($0.start) && $0.status != .needsReview }.sorted { $0.start < $1.start }
            guard let first = day.first else { return "Not recorded" }
            let clock = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute()
            return "\(first.start.formatted(clock))\u{2013}\(day.last?.end.map { $0.formatted(clock) } ?? "now")"
        }
        return VStack(spacing: 10) {
            HStack {
                Text("YOUR DAY").font(Theme.text(Theme.Size.caption))
                Spacer()
                Text("Filled automatically").font(Theme.text(Theme.Size.footnote))
            }
            .foregroundStyle(Theme.secondaryText)
            VStack(spacing: 18) {
                row("moon", "Sleep", s.sleepHours.map { Fmt.hours($0 * 3600) } ?? "Not recorded", Theme.sleep) { SleepView() }
                row("briefcase", "Work", range(.work), Theme.secondaryText) { TimeTrackingView() }
                row("graduation-cap", "University", range(.university), Theme.secondaryText) { TimeTrackingView() }
            }
            .padding(Theme.cardPadding).frame(maxWidth: .infinity).glass(Theme.cardRadius)
        }
    }

    private func row<D: View>(_ icon: String, _ title: String, _ value: String, _ tint: Color, @ViewBuilder dest: () -> D) -> some View {
        let d = dest()
        return NavigationLink { d } label: {
            HStack(spacing: 12) {
                Icon(icon, size: 20).foregroundStyle(tint)
                Text(title).font(Theme.text(Theme.Size.cardTitle)).foregroundStyle(Theme.text)
                Spacer()
                Text(value).font(Theme.text(Theme.Size.tileTitle)).foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            .contentShape(Rectangle())
        }.buttonStyle(Press())
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
            if startTS > 0 { running } else if skipped { skippedState } else { idle }
        }
    }

    private var idle: some View {
        Group {
            CardHeading(icon: "person-standing", title: Calendar.current.component(.hour, from: .now) >= 17 ? "A little air after work" : "A little air today", iconSize: 20)
            Text("A gentle 15-minute walk can help you switch off. Only if you feel up to it.")
                .font(Theme.text(Theme.Size.body)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                PillButton(title: "Start walk") { startTS = Date.now.timeIntervalSince1970 }
                PillButton(title: "Can\u{2019}t today", kind: .secondary) { skipDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970 }
            }
        }
    }

    private var skippedState: some View {
        Group {
            CardHeading(icon: "leaf", title: "No walk today. That is fine.", tint: Theme.good, iconSize: 22)
            Text("Rest is a valid next step. We\u{2019}ll pick this up another day.").font(Theme.text(Theme.Size.body)).foregroundStyle(Theme.secondaryText)
            PillButton(title: "Undo", kind: .secondary) { skipDay = 0 }
        }
    }

    private var running: some View {
        Group {
            HStack {
                Text("Walk in progress").font(Theme.text(Theme.Size.cardTitle, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text("Timer running").font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.accent)
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(elapsed(ctx.date)).font(Theme.number(Theme.Size.timer)).tracking(-0.8).foregroundStyle(Theme.text).monospacedDigit()
            }
            PillButton(title: saving ? "Saving" : "Finish walk", icon: "check") { Task { await finish() } }.disabled(saving)
            Button("Discard", role: .destructive) { startTS = 0 }.font(Theme.text(Theme.Size.caption))
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
