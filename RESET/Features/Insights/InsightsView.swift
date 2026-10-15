import SwiftUI
import SwiftData
import Charts
import ResetCore

struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query private var profiles: [UserProfile]
    @Query private var sleeps: [SleepRecord]
    @Query private var checks: [CheckIn]
    @Query private var meals: [MealRecord]
    @Query private var caffeine: [CaffeineRecord]
    @Query private var acts: [ActivityRecord]
    @Query private var sessions: [TrackedSession]
    @Query(sort: \WeightRecord.at) private var weights: [WeightRecord]
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?
    @State private var weightText = ""
    @State private var applied = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        let _ = (sleeps.count, checks.count, meals.count, caffeine.count, acts.count, sessions.count)
        let days = InsightData.days(context: context, profile: profile)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    weekCard(days)
                    workChart
                    weightCard
                    patterns(days)
                    exportCard
                }.padding()
            }
            .background(Theme.background)
            .navigationTitle("Insights")
        }
    }

    // MARK: Week

    private func weekCard(_ days: [InsightDay]) -> some View {
        let week = Array(days.suffix(7))
        let sleep = week.compactMap(\.sleepHours)
        let steps = health.week.map(\.steps)
        let workouts = week.filter(\.trained).count
        let daysWithFood = week.filter { $0.firstMealMinute != nil }.count
        return Card(title: "Last 7 days") {
            row("Sleep", sleep.isEmpty ? "Not recorded" : String(format: "%.1f h average over %d night(s)", sleep.reduce(0, +) / Double(sleep.count), sleep.count))
            row("Steps", steps.isEmpty ? (health.authRequested ? "No data" : "Permission required") : "\((steps.reduce(0, +) / steps.count).formatted()) a day")
            row("Strength sessions", "\(workouts)")
            row("Walking", String(format: "%.0f min total", week.reduce(0) { $0 + $1.walkMinutes }))
            row("Days with food logged", "\(daysWithFood) of 7")
            row("Calories", weekCalories)
        }
    }

    private var weekCalories: String {
        let cal = Calendar.current
        let week = Date.now.addingTimeInterval(-7 * 86_400)
        var perDay: [Date: Double] = [:]
        for m in meals where m.at >= week { perDay[cal.startOfDay(for: m.at), default: 0] += m.nutrition.kcal }
        // Days with one small entry are likely incomplete logging, so they are left out of the average.
        let full = perDay.values.filter { $0 >= 800 }
        guard !full.isEmpty else { return "Not enough complete days" }
        return "\(Int((full.reduce(0, +) / Double(full.count)).rounded())) kcal average on \(full.count) well-logged day(s)"
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.trailing) }.font(.subheadline)
    }

    @ViewBuilder private var workChart: some View {
        let vals = sessions.map(\.value)
        let cal = Calendar.current
        let data: [(Date, Double)] = (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: .now)) else { return nil }
            let w = Day.interval(of: d)
            return (d, (SessionMath.totals(vals, category: .work, in: w, now: .now).total + SessionMath.totals(vals, category: .university, in: w, now: .now).total) / 3600)
        }
        if data.contains(where: { $0.1 > 0 }) {
            Card(title: "Work and university hours") {
                Chart(data, id: \.0) { BarMark(x: .value("Day", $0.0, unit: .day), y: .value("Hours", $0.1)).foregroundStyle(Theme.accent) }.frame(height: 130)
                Text("Includes location estimates. Confirm sessions in Work and University for firm numbers.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Weight

    private var weightCard: some View {
        let pts = weights.map { WeightPoint(at: $0.at, kg: $0.kg) }
        let slope = WeightTrend.slopeKgPerDay(pts)
        let imperial = profile?.units == .imperial
        func show(_ kg: Double) -> String { imperial ? String(format: "%.1f lb", Units.kgToLb(kg)) : String(format: "%.1f kg", kg) }
        return Card(title: "Weight") {
            if let last = weights.last { BigMetric(value: show(last.kg), caption: "Logged \(last.at.formatted(date: .abbreviated, time: .omitted))") }
            else { BigMetric(value: "Not recorded", caption: "Weigh in whenever you like. Weekly is plenty.") }
            if let s = slope {
                let perWeek = s * 7
                Text("Trend: \(perWeek >= 0 ? "+" : "")\(imperial ? String(format: "%.1f lb", Units.kgToLb(perWeek)) : String(format: "%.2f kg", perWeek)) a week, from \(pts.count) weigh-ins. Single days bounce around, so watch the trend.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            } else if !weights.isEmpty {
                Text("Needs about four weigh-ins over ten days before a trend is shown.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let p = profile, let target = p.targetWeightKg, let first = weights.first, let last = weights.last, abs(first.kg - target) > 0.1 {
                let done = (first.kg - last.kg) / (first.kg - target)
                ProgressBar(fraction: max(0, done))
                Text("\(Int(max(0, min(1, done)) * 100))% of the way from \(show(first.kg)) to \(show(target)). Fat loss is gradual, and it does not come from one area of the body.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack {
                TextField(imperial ? "lb" : "kg", text: $weightText).keyboardType(.decimalPad)
                Button("Log weight", action: logWeight).disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
            }
            if let m = suggestedMaintenance(pts) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your intake and weight trend suggest maintenance is nearer \(Int(m.rounded())) kcal. This is a suggestion from your own data, not a certainty.").font(.footnote)
                    Button(applied ? "Applied" : "Use this as my maintenance") { profile?.maintenanceOverrideKcal = m; applied = true }.disabled(applied)
                }
            }
        }
    }

    private func suggestedMaintenance(_ pts: [WeightPoint]) -> Double? {
        guard let first = pts.map(\.at).min() else { return nil }
        let cal = Calendar.current
        var perDay: [Date: Double] = [:]
        for m in meals where m.at >= first { perDay[cal.startOfDay(for: m.at), default: 0] += m.nutrition.kcal }
        let full = perDay.values.filter { $0 >= 800 }
        guard full.count >= 10 else { return nil }
        return WeightTrend.impliedMaintenance(avgIntakeKcal: full.reduce(0, +) / Double(full.count), points: pts)
    }

    private func logWeight() {
        guard var v = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return }
        if profile?.units == .imperial { v = Units.lbToKg(v) }
        guard (30...300).contains(v) else { return }
        context.insert(WeightRecord(kg: v))
        profile?.weightKg = v
        try? context.save()
        weightText = ""
    }

    // MARK: Patterns

    private func patterns(_ days: [InsightDay]) -> some View {
        let items = InsightEngine.all(days, sleepTarget: profile?.sleepTargetHours ?? 8)
        return VStack(spacing: 10) {
            ForEach(items) { i in
                Card(title: i.title) {
                    Text(i.text).font(.subheadline)
                    HStack {
                        Image(systemName: i.state == .pattern ? "chart.xyaxis.line" : (i.state == .collecting ? "hourglass" : "equal.circle"))
                        Text("\(i.observations) day(s) of data").font(.caption)
                    }.foregroundStyle(Theme.secondaryText)
                }
            }
            Text(InsightEngine.cautionNote).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Export

    private var exportCard: some View {
        Card(title: "Your data") {
            Text("Export everything you have logged as JSON and CSV files. They are created on this iPhone and go only where you send them.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            if exportURLs.isEmpty {
                Button("Prepare export") {
                    do { exportURLs = try DataExporter.write(context: context); exportError = nil }
                    catch { exportError = "Could not create the export: \(error.localizedDescription)" }
                }
            } else {
                ShareLink("Share \(exportURLs.count) files", items: exportURLs)
            }
            if let e = exportError { Text(e).font(.footnote).foregroundStyle(Theme.low) }
        }
    }
}
