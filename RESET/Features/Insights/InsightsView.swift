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
    @State private var weightText = ""

    private var profile: UserProfile? { profiles.first }


    var body: some View {
        let _ = (sleeps.count, checks.count, meals.count, caffeine.count, acts.count, sessions.count)
        let days = InsightData.days(context: context, profile: profile)
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    weekHero(days)
                    standout(days)
                    workChart
                    weightCard
                }.padding()
            }
            .background(GlassBackdrop())
            .navigationTitle("Insights")
        }
    }

    // MARK: Week

    private func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    private func weekHero(_ days: [InsightDay]) -> some View {
        let thisWeek = Array(days.suffix(7)), lastWeek = Array(days.dropLast(7).suffix(7))
        return Card(title: "This week") {
            HStack(alignment: .top, spacing: 12) {
                stat("Sleep", avg(thisWeek.compactMap(\.sleepHours)), avg(lastWeek.compactMap(\.sleepHours)), unit: "h", good: .up)
                stat("Work", thisWeek.contains { $0.workHours > 0 } ? thisWeek.map(\.workHours).reduce(0, +) : nil,
                     lastWeek.contains { $0.workHours > 0 } ? lastWeek.map(\.workHours).reduce(0, +) : nil, unit: "h", good: .none)
                stat("Workouts", Double(thisWeek.filter(\.trained).count), Double(lastWeek.filter(\.trained).count), unit: "", good: .up)
            }
        }
    }

    private enum Good { case up, none }

    private func stat(_ title: String, _ now: Double?, _ before: Double?, unit: String, good: Good) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.map { $0.formatted(.number.precision(.fractionLength(0...1))) + (unit.isEmpty ? "" : " " + unit) } ?? "None")
                .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            if let now, let before, abs(now - before) >= 0.1 {
                let up = now > before
                Label((now - before).magnitude.formatted(.number.precision(.fractionLength(0...1))), systemImage: up ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(good == .none ? Theme.secondaryText : (up ? Theme.good : Theme.warn))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func standout(_ days: [InsightDay]) -> some View {
        let found = InsightEngine.all(days, sleepTarget: profile?.sleepTargetHours ?? 8).filter { $0.state == .pattern }
        if found.isEmpty {
            Card { Label("Patterns appear after about two weeks of tracking.", systemImage: "hourglass").font(.subheadline) }
        } else {
            ForEach(found) { i in
                Card(title: i.title) { Text(i.text).font(.subheadline) }
            }
        }
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
            else { BigMetric(value: "None yet", caption: "Weekly is plenty.") }
            if let s = slope {
                let perWeek = s * 7
                Text("Trend: \(perWeek >= 0 ? "+" : "")\(imperial ? String(format: "%.1f lb", Units.kgToLb(perWeek)) : String(format: "%.2f kg", perWeek)) a week")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let p = profile, let target = p.targetWeightKg, let first = weights.first, let last = weights.last, abs(first.kg - target) > 0.1 {
                let done = (first.kg - last.kg) / (first.kg - target)
                ProgressBar(fraction: max(0, done))
                Text("\(Int(max(0, min(1, done)) * 100))% of the way to \(show(target))").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack {
                TextField(imperial ? "lb" : "kg", text: $weightText).keyboardType(.decimalPad)
                Button("Log weight", action: logWeight).disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
            }
        }
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

}
