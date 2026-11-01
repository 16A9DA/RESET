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
    @Query private var waters: [WaterRecord]
    @Query private var acts: [ActivityRecord]
    @Query private var sessions: [TrackedSession]
    @Query(sort: \WeightRecord.at) private var weights: [WeightRecord]
    @State private var weightText = ""
    @State private var weightSheet = false

    private var profile: UserProfile? { profiles.first }


    var body: some View {
        let _ = (sleeps.count, checks.count, meals.count, caffeine.count, acts.count, sessions.count, waters.count)
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    weekCards
                    weightRow
                }.padding(.horizontal).padding(.top, 8).padding(.bottom, 12)
            }
            .background(GlassBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $weightSheet) {
                ScrollView { weightCard.padding() }.background(GlassBackdrop()).presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Week

    private func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    private var week: [Date] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }
    }

    private var header: some View {
        let sub: String = {
            guard let a = week.first, let b = week.last else { return "This week" }
            return "\(a.formatted(.dateTime.day()))\u{2013}\(b.formatted(.dateTime.day().month(.wide))) \u{b7} This week"
        }()
        return PageHeader(title: "Insights", subtitle: sub) {
            Image(systemName: "calendar").font(.title2).foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
        }
    }

    private var weekCards: some View {
        let cal = Calendar.current
        let sleepTarget = profile?.sleepTargetHours ?? 8
        let sleep = week.map { d in sleeps.first { cal.isDate($0.day, inSameDayAs: d) }?.hours ?? 0 }
        let steps = week.map { d in Double(health.week.first { cal.isDate($0.day, inSameDayAs: d) }?.steps ?? 0) }
        let water = week.map { d in waters.filter { cal.isDate($0.at, inSameDayAs: d) }.reduce(0) { $0 + $1.ml } / 1000 }
        let kcal = week.map { d in NutritionTotals.day(meals.map { ($0.at, $0.items) }, on: d).total.kcal }
        func mean(_ v: [Double]) -> Double? { let x = v.filter { $0 > 0 }; return x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }
        let sleepAvg = mean(sleep), stepsAvg = mean(steps), waterAvg = mean(water), kcalAvg = mean(kcal)
        let waterGoal = (profile?.effectiveWaterGoalMl ?? 3000) / 1000
        let kcalGoal = profile?.energyPlan.targetKcal ?? 2500
        let known = kcal.filter { $0 > 0 }
        let steady = (known.max() ?? 0) - (known.min() ?? 0) < (kcalAvg ?? 0) * 0.35
        func k(_ v: Double) -> String { v >= 1000 ? (v / 1000).formatted(.number.precision(.fractionLength(0...1))) + "k" : "\(Int(v))" }
        return VStack(spacing: 12) {
            insightCard("Sleep", sleepAvg.map { $0.formatted(.number.precision(.fractionLength(1))) }, "h avg",
                        sleepAvg.map { $0 < sleepTarget - 1 ? "Sleep ran short this week. An earlier bedtime would help." : "A consistent bedtime could make mornings easier." }
                            ?? "No nights recorded this week.",
                        Theme.sleep, sleep, top: max(sleepTarget, sleep.max() ?? 0), topLabel: "\(Int(max(sleepTarget, sleep.max() ?? 0).rounded())) h", zeroLabel: "0 h")
            insightCard("Steps", stepsAvg.map { Int($0).formatted() }, "steps avg",
                        (stepsAvg ?? 0) >= 8000 ? "You are reaching your steps. Keep them gentle." : "Your workday walks add up. Keep them gentle.",
                        Theme.steps, steps, top: max(8000, steps.max() ?? 0), topLabel: k(max(8000, steps.max() ?? 0)), zeroLabel: "0")
            insightCard("Water", waterAvg.map { $0.formatted(.number.precision(.fractionLength(1))) }, "L avg",
                        (waterAvg ?? 0) < waterGoal * 0.7 ? "Keep a glass nearby for your next work break." : "Water is on track. Keep it up.",
                        Theme.water, water, top: max(waterGoal, water.max() ?? 0), topLabel: "\(Int(max(waterGoal, water.max() ?? 0).rounded())) L", zeroLabel: "0 L")
            insightCard("Energy", kcalAvg.map { Int($0).formatted() }, "kcal avg",
                        kcalAvg == nil ? "No meals logged this week." : (steady ? "Your intake is fairly steady across the week." : "Intake varied this week. Regular meals help."),
                        Theme.food, kcal, top: max(kcalGoal, kcal.max() ?? 0), topLabel: k(max(kcalGoal, kcal.max() ?? 0)), zeroLabel: "0")
            Text("Daily totals \u{b7} Last bar is today \u{b7} Trends, not grades").font(.footnote).foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
        }
    }

    private func insightCard(_ title: String, _ value: String?, _ unit: String, _ caption: String, _ tint: Color, _ values: [Double],
                             top: Double, topLabel: String, zeroLabel: String) -> some View {
        let today = week.last
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(value ?? "None").font(.system(size: 30, weight: .bold)).tracking(-0.6).monospacedDigit()
                if value != nil { Text(unit).font(.subheadline).foregroundStyle(Theme.secondaryText) }
            }
            Text(caption).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Chart(Array(zip(week, values)), id: \.0) { d, v in
                BarMark(x: .value("Day", d, unit: .day), y: .value(title, v), width: .fixed(16))
                    .foregroundStyle(d == today ? tint : tint.opacity(0.5)).clipShape(Capsule())
            }
            .chartYScale(domain: 0...max(top, 0.001))
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, top]) { value in
                    AxisValueLabel {
                        Text((value.as(Double.self) ?? 0) == 0 ? zeroLabel : topLabel).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption).foregroundStyle(Theme.secondaryText) } }
            .frame(height: 96)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18).glass(24)
    }

    /// Weight stays available but takes one slim row. The full log and trend open in a sheet.
    private var weightRow: some View {
        let imperial = profile?.units == .imperial
        let v = weights.last.map { imperial ? String(format: "%.1f lb", Units.kgToLb($0.kg)) : String(format: "%.1f kg", $0.kg) } ?? "Log"
        return ListGroup {
            Button { weightSheet = true } label: { GroupRow(title: "Weight", icon: "scalemass", value: v, tint: Theme.secondaryText) }.buttonStyle(Press())
        }
    }

    private enum Good { case up, none }

    private func stat(_ title: String, _ now: Double?, _ before: Double?, unit: String, good: Good, whole: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.map { $0.formatted(.number.precision(.fractionLength(whole ? 0...0 : 0...1))) + (unit.isEmpty ? "" : " " + unit) } ?? "None")
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
