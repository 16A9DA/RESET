import SwiftUI
import SwiftData
import Observation
import ResetCore

enum AppTab: Hashable { case today, activity, nutrition, insights, coach }

@Observable
final class AppRouter {
    var tab: AppTab = .today
}

private enum QuickSheet: String, Identifiable {
    case food, photo, drink, workout, checkIn, workHours
    var id: String { rawValue }
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(NotificationScheduler.self) private var notifier
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]
    // Observed so the dashboard recomputes when any source changes.
    @Query private var meals: [MealRecord]
    @Query private var waters: [WaterRecord]
    @Query private var caffeines: [CaffeineRecord]
    @Query private var sleeps: [SleepRecord]
    @Query private var checks: [CheckIn]
    @Query private var sessions: [TrackedSession]
    @Query private var acts: [ActivityRecord]
    @Query private var workouts: [WorkoutRecord]
    @AppStorage("walk.start") private var walkStart: Double = 0
    @State private var sheet: QuickSheet?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        let _ = (meals.count, waters.count, caffeines.count, sleeps.count, checks.count, sessions.count, acts.count, workouts.count)
        let s = DaySummaryBuilder.build(context: context, profile: profile, health: health)
        let symptoms = checks.contains { $0.kind == .symptom && $0.at > Date.now.addingTimeInterval(-24 * 3600) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header(s, symptoms: symptoms)
                    quickActions
                    RecoveryCard()
                    metricsGrid(s)
                    nutritionCard(s)
                    workCard(s)
                    upcoming
                    planCard
                    NavigationLink { TimelineScreen() } label: {
                        Card(title: "Timeline") { Text("Everything recorded today, with where it came from").foregroundStyle(Theme.secondaryText) }
                    }.buttonStyle(.plain)
                }.padding()
            }
            .background(Theme.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings and profile")
                }
            }
            .task { await health.refresh(); await notifier.rebuild(context: context) }
            .refreshable { await health.refresh() }
            .sheet(item: $sheet) { which in
                switch which {
                case .food: AddFoodView()
                case .photo: AddFoodView(startWith: .photo)
                case .drink: LogDrinkView()
                case .workout: WorkoutSheet()
                case .checkIn: CheckInSheet()
                case .workHours: NavigationStack { TimeTrackingView() }
                }
            }
        }
    }

    // MARK: Pieces

    private func header(_ s: DaySummary, symptoms: Bool) -> some View {
        let hour = Calendar.current.component(.hour, from: .now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Text(Priority.message(s, symptoms: symptoms, hour: hour)).font(.system(.title3, design: .rounded, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        let items: [(String, String, () -> Void)] = [
            ("Log food", "fork.knife", { sheet = .food }),
            ("Photo meal", "camera", { sheet = .photo }),
            ("Drink", "cup.and.saucer", { sheet = .drink }),
            ("+250 ml", "drop", { context.insert(WaterRecord(ml: Double(profile?.quickWaterMl[safe: 1] ?? 250))); try? context.save(); Task { await notifier.rebuild(context: context) } }),
            ("Start walk", "figure.walk", { if walkStart == 0 { walkStart = Date.now.timeIntervalSince1970 }; router.tab = .activity }),
            ("Workout", "dumbbell", { sheet = .workout }),
            ("Fatigue", "bolt.heart", { sheet = .checkIn }),
            ("Work hours", "clock", { sheet = .workHours }),
            ("Ask coach", "sparkles", { router.tab = .coach }),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items, id: \.0) { item in
                Button(action: item.2) {
                    VStack(spacing: 6) {
                        Image(systemName: item.1).font(.title3)
                        Text(item.0).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private func metric(_ title: String, _ value: String?, unit: String = "", caption: String) -> some View {
        Card(title: title) {
            if let value { BigMetric(value: value, unit: unit, caption: caption) }
            else { BigMetric(value: "Not recorded", caption: caption) }
        }
    }

    private func metricsGrid(_ s: DaySummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            metric("Sleep", s.sleepHours.map { String(format: "%.1f", $0) }, unit: "h",
                   caption: "Target \(String(format: "%g", s.sleepTargetHours)) h")
            metric("Energy", s.energy.map(String.init), unit: "of 5",
                   caption: s.fatigue.map { "Fatigue \($0) of 5" } ?? "Fatigue not recorded")
            metric("Steps", s.steps.map { $0.formatted() },
                   caption: s.steps == nil ? (health.authRequested ? "No data yet" : "Permission required") : (s.stepSource ?? ""))
            metric("Activity", s.structuredActivityMinutes > 0 ? "\(Int(s.structuredActivityMinutes.rounded()))" : nil, unit: "min",
                   caption: s.workouts.isEmpty ? "Walks and workouts" : s.workouts.joined(separator: ", "))
            metric("Water", String(format: "%.1f", s.waterMl / 1000), unit: "L",
                   caption: s.waterGoalMl.map { "Goal about \(String(format: "%.1f", $0 / 1000)) L" } ?? "No goal set")
            metric("Caffeine", s.caffeineMg > 0 ? "\(Int(s.caffeineMg.rounded()))" : nil, unit: "mg", caption: "Roughly 400 mg is a commonly cited limit")
        }
    }

    private func nutritionCard(_ s: DaySummary) -> some View {
        Card(title: "Food") {
            HStack(alignment: .top) {
                if s.calorieCounting {
                    BigMetric(value: "\(Int(s.kcalConsumed.rounded()))", unit: "kcal",
                              caption: s.kcalTarget.map { "Suggested about \(Int($0.rounded()))" } ?? "Target: Estimate unavailable")
                    Spacer()
                }
                BigMetric(value: "\(Int(s.proteinG.rounded()))", unit: "g protein", caption: "Target about \(Int(s.proteinTargetG.rounded())) g")
            }
            if s.calorieCounting, let t = s.kcalTarget { ProgressBar(fraction: s.kcalConsumed / t) }
            if s.calorieCounting, let b = s.calorieBalance {
                Text("Balance so far: \(Int(b.rounded())) kcal against estimated maintenance. Estimates only, and the day is not over.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if s.mealsLogged == 0 { Text("No meals logged yet. That may just mean you have not logged.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if s.estimatedItems > 0 { Text("\(s.estimatedItems) item(s) are estimates.").font(.caption).foregroundStyle(Theme.warn) }
        }
    }

    private func workCard(_ s: DaySummary) -> some View {
        Card(title: "Work and university") {
            HStack {
                BigMetric(value: s.workSeconds.map(Fmt.hours) ?? "Not recorded", caption: "Work today")
                Spacer()
                BigMetric(value: s.universitySeconds.map(Fmt.hours) ?? "Not recorded", caption: "University today")
            }
            Text("From place detection and timers. Detected times are estimates until you confirm them.").font(.caption).foregroundStyle(Theme.secondaryText)
            let review = sessions.filter { $0.status == .needsReview }.count
            if review > 0 { Text("\(review) session(s) need a quick review.").font(.footnote).foregroundStyle(Theme.warn) }
        }
    }

    @ViewBuilder private var upcoming: some View {
        Card(title: "Upcoming reminders") {
            if notifier.upcoming.isEmpty {
                Text(notifier.canSchedule ? "Nothing scheduled right now." : "Notifications are off or not yet allowed.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(notifier.upcoming.prefix(4)), id: \.id) { r in
                HStack {
                    Text(r.title)
                    Spacer()
                    Text(r.fireDate.formatted(date: .omitted, time: .shortened)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                }.font(.subheadline)
            }
            NavigationLink("Reminder settings") { RemindersSettingsView() }.font(.footnote)
        }
    }

    private var planCard: some View { WorkoutCard() }
}
