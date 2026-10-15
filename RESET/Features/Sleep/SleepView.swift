import SwiftUI
import SwiftData
import Charts
import ResetCore

extension SleepRecord {
    var night: SleepNight { SleepNight(asleepAt: asleepAt, wokeAt: wokeAt, quality: quality) }
}

struct SleepView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query(sort: \SleepRecord.day, order: .reverse) private var records: [SleepRecord]
    @Query private var profiles: [UserProfile]
    @State private var logging = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let p = profile { planCard(p) }
                summaryCard
                trendCard
                historyCard
            }.padding()
        }
        .background(Theme.background)
        .navigationTitle("Sleep")
        .toolbar { Button("Log sleep") { logging = true } }
        .sheet(isPresented: $logging) { SleepLogSheet() }
        .task { await health.importSleep(since: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now, context: context) }
    }

    private func planCard(_ p: UserProfile) -> some View {
        let shape = DayShape(wakeMinute: p.wakeMinute, bedMinute: p.bedMinute)
        let wake = shape.window(on: .now).start
        let bed = SleepPlanner.bedtime(wake: wake, targetHours: p.sleepTargetHours)
        return Card(title: "Tonight's plan") {
            HStack(alignment: .top) {
                BigMetric(value: bed.formatted(date: .omitted, time: .shortened), caption: "Lights out for \(String(format: "%g", p.sleepTargetHours)) h before a \(wake.formatted(date: .omitted, time: .shortened)) wake")
                Spacer()
            }
            Text("Wind down from \(SleepPlanner.windDownStart(bedtime: bed, minutes: p.windDownMinutes).formatted(date: .omitted, time: .shortened)).")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Stepper("Target: \(String(format: "%g", p.sleepTargetHours)) h", value: Bindable(p).sleepTargetHours, in: 6...10, step: 0.5)
            Stepper("Wind down: \(p.windDownMinutes) min", value: Bindable(p).windDownMinutes, in: 15...90, step: 15)
            Text("About 7 to 9 hours suits most adults. Your usual bedtime in Settings is \(Fmt.clock(minutes: p.bedMinute)). The suggestion above works backwards from your wake time.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var summaryCard: some View {
        let nights = records.prefix(7).map(\.night)
        let s = SleepPlanner.summary(Array(nights), targetHours: profile?.sleepTargetHours ?? 8)
        return Card(title: "Last 7 nights") {
            if let a = s.averageHours {
                BigMetric(value: String(format: "%.1f", a), unit: "h average", caption: "\(s.label) Based on \(s.nights) night(s).")
                if let v = s.bedtimeVarianceMin {
                    Text("Bedtime varies by about \(Int(v.rounded())) min. Steady times tend to help.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            } else {
                EmptyNote(systemImage: "bed.double", title: "Not recorded", message: s.label, actionTitle: "Log sleep") { logging = true }
            }
            Text("Times you enter are the baseline. The iPhone cannot tell when you fall asleep, so nothing here is detected automatically. Sleep from Apple Health appears only if another device or app wrote it.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var trendCard: some View {
        let data = Array(records.prefix(14).reversed())
        if data.count >= 2 {
            Card(title: "Hours slept") {
                Chart(data) { r in
                    BarMark(x: .value("Day", r.day, unit: .day), y: .value("Hours", r.hours)).foregroundStyle(Theme.accent)
                    if let t = profile?.sleepTargetHours { RuleMark(y: .value("Target", t)).foregroundStyle(.white.opacity(0.4)).lineStyle(StrokeStyle(dash: [4])) }
                }.frame(height: 140)
            }
        }
    }

    private var historyCard: some View {
        Card(title: "History") {
            if records.isEmpty { Text("Nothing yet.").foregroundStyle(Theme.secondaryText) }
            ForEach(records.prefix(14)) { r in
                HStack {
                    VStack(alignment: .leading) {
                        Text(r.day.formatted(.dateTime.weekday(.wide).day().month())).font(.subheadline)
                        Text("\(r.asleepAt.formatted(date: .omitted, time: .shortened)) to \(r.wokeAt.formatted(date: .omitted, time: .shortened)), \(r.source == .imported ? "from Health" : "entered by you")")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text(String(format: "%.1f h", r.hours)).monospacedDigit()
                    Button(role: .destructive) { context.delete(r); try? context.save() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete")
                }
            }
        }
    }
}

struct SleepLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var day = Date.now
    @State private var asleep = 23 * 60
    @State private var woke = 7 * 60
    @State private var quality = 3
    @State private var energy = 3
    @State private var skipQuality = false

    private var night: SleepNight { SleepPlanner.night(wakeDay: day, asleepMinute: asleep, wokeMinute: woke) }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Woke up on", selection: $day, in: ...Date.now, displayedComponents: .date)
                DatePicker("Fell asleep about", selection: $asleep.asTimeOfDay(), displayedComponents: .hourAndMinute)
                DatePicker("Woke up", selection: $woke.asTimeOfDay(), displayedComponents: .hourAndMinute)
                Text("About \(String(format: "%.1f", night.hours)) hours").foregroundStyle(Theme.secondaryText)
                Section("How was it?") {
                    Toggle("Skip rating", isOn: $skipQuality)
                    if !skipQuality {
                        Picker("Sleep quality", selection: $quality) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    }
                    Picker("Energy this morning", selection: $energy) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    Text("1 is low, 5 is high.").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                if night.hours > 14 || night.hours < 1 { Text("That looks unusual. Check the times.").foregroundStyle(Theme.warn) }
            }
            .navigationTitle("Log sleep").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(night.hours < 0.5 || night.hours > 18) }
            }
        }
    }

    private func save() {
        let d = Calendar.current.startOfDay(for: day)
        // One record per wake-up day. Replace an earlier entry instead of stacking duplicates.
        let existing = (try? context.fetch(FetchDescriptor<SleepRecord>())) ?? []
        existing.filter { Calendar.current.isDate($0.day, inSameDayAs: d) }.forEach(context.delete)
        context.insert(SleepRecord(day: d, asleepAt: night.asleepAt, wokeAt: night.wokeAt, quality: skipQuality ? nil : quality))
        context.insert(CheckIn(at: night.wokeAt, kind: .energy, value: energy, note: "morning"))
        try? context.save()
        dismiss()
    }
}
