import SwiftUI
import SwiftData
import Observation
import ResetCore

enum AppTab: Hashable { case today, activity, nutrition, insights, coach }

@Observable
final class AppRouter {
    var tab: AppTab = .today
    /// A screen a widget asked for. Cleared once Today has handled it.
    var deepLink: DeepLink?

    func open(_ link: DeepLink) {
        switch link {
        case .food, .photo, .checkIn:
            tab = .today
            deepLink = link
        case .walk:
            tab = .activity
            // The user tapped a Start a walk widget, so that is explicit. Never restart one already running.
            if UserDefaults.standard.double(forKey: "walk.start") == 0 { UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "walk.start") }
        case .coach:
            tab = .coach
        }
    }
}

private enum QuickSheet: String, Identifiable {
    case food, photo, barcode, checkIn, canEat, sleepLog
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
    @State private var sheet: QuickSheet?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        let _ = (meals.count, waters.count, caffeines.count, sleeps.count, checks.count, sessions.count, acts.count, workouts.count)
        let s = DaySummaryBuilder.build(context: context, profile: profile, health: health)
        let symptoms = checks.contains { $0.kind == .symptom && $0.at > Date.now.addingTimeInterval(-24 * 3600) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header(s, symptoms: symptoms)
                    let times = [SessionCategory.work, .university, .gym].filter { hasTime($0) }
                    if !times.isEmpty { SectionLabel("Time") }
                    ForEach(times, id: \.self) { timeRow($0, s) }
                    SectionLabel("Nutrition")
                    foodCard(s)
                    SectionLabel("Body")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        waterTile(s)
                        tile("Steps", s.steps.map { $0.formatted() }, icon: "figure.walk", tint: Theme.steps,
                             fraction: s.steps.map { Double($0) / 8000 }, caption: "of 8,000")
                        sleepTile(s)
                        recoveryTile(s)
                    }
                    SectionLabel("Tools")
                    Button { sheet = .canEat } label: { row("Can I eat this?", icon: "questionmark.circle") }.buttonStyle(Press())
                    NavigationLink { ScrollView { WorkoutCard().padding() }.background(GlassBackdrop()).navigationTitle("Workout") } label: {
                        row("Workout", icon: "dumbbell")
                    }.buttonStyle(Press())
                }
                .padding(.horizontal).padding(.top, 8)
            }
            .background(GlassBackdrop())
            .safeAreaInset(edge: .bottom) { logBar }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { TimelineScreen() } label: { Image(systemName: "clock") }.accessibilityLabel("Timeline")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings and profile")
                }
            }
            .task { await health.refresh(); await notifier.rebuild(context: context) }
            .task { RecoverySnapshot.store(RecoverySnapshot.assess(context: context, profile: profile), context: context) }
            .task(id: [meals.count, waters.count, caffeines.count, acts.count, Int(health.todaySteps ?? -1)]) { WidgetBridge.publish(s) }
            .refreshable { await health.refresh() }
            .onAppear(perform: handleDeepLink)
            .onChange(of: router.deepLink) { _, _ in handleDeepLink() }
            .sheet(item: $sheet) { which in
                switch which {
                case .food: AddFoodView()
                case .photo: AddFoodView(startWith: .photo)
                case .barcode: AddFoodView(startWith: .barcode)
                case .checkIn: CheckInSheet()
                case .canEat: CanIEatView()
                case .sleepLog: SleepLogSheet()
                }
            }
        }
    }

    private func handleDeepLink() {
        guard let link = router.deepLink else { return }
        router.deepLink = nil
        switch link {
        case .food: sheet = .food
        case .photo: sheet = .photo
        case .checkIn: sheet = .checkIn
        default: break
        }
    }

    // MARK: Pieces

    private func header(_ s: DaySummary, symptoms: Bool) -> some View {
        let hour = Calendar.current.component(.hour, from: .now)
        return VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Text(Priority.message(s, symptoms: symptoms, hour: hour))
                .font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
    }

    private func hasTime(_ category: SessionCategory) -> Bool {
        let w = Day.interval(of: .now)
        return profile?.goalSeconds(category) != nil || sessions.contains { $0.category == category && w.contains($0.start) && $0.status != .needsReview }
    }

    /// Work, university and gym fill themselves from place detection: "09:02 to 17:40, 8h 38m".
    @ViewBuilder private func timeRow(_ category: SessionCategory, _ s: DaySummary) -> some View {
        let now = Date.now
        let w = Day.interval(of: now)
        let today = sessions.filter { $0.category == category && w.contains($0.start) && $0.status != .needsReview }.sorted { $0.start < $1.start }
        let done = SessionMath.totals(sessions.map(\.value), category: category, in: w, now: now).total
        let goal = profile?.goalSeconds(category)
        let here = today.contains { $0.end == nil }
        if goal != nil || !today.isEmpty {
            Card {
                HStack {
                    Label(category.rawValue.capitalized, systemImage: category == .work ? "briefcase" : (category == .gym ? "dumbbell" : "graduationcap"))
                        .font(.headline)
                    if here { Text("Here now").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(.black) }
                    Spacer()
                    Text(Fmt.hours(done)).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                }
                if let first = today.first {
                    let last = today.last?.end
                    Text("\(first.start.formatted(date: .omitted, time: .shortened)) to \(last.map { $0.formatted(date: .omitted, time: .shortened) } ?? "now")")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText).monospacedDigit()
                }
                if let goal { ProgressBar(fraction: done / goal) }
            }
        }
    }

    private func foodCard(_ s: DaySummary) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label("Food", systemImage: "fork.knife").font(.headline).foregroundStyle(Theme.food)
                Spacer()
                if s.calorieCounting {
                    Text("\(Int(s.kcalConsumed.rounded()))").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                    + Text(s.kcalTarget.map { " / \(Int($0.rounded())) kcal" } ?? " kcal").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            if s.calorieCounting, let t = s.kcalTarget { ProgressBar(fraction: s.kcalConsumed / t, tint: Theme.food) }
            MacroRow(name: "Protein", eaten: s.proteinG, goal: s.proteinTargetG, tint: Theme.protein)
            MacroRow(name: "Carbs", eaten: s.carbsG, goal: s.carbsTargetG, tint: Theme.carbs)
            MacroRow(name: "Fat", eaten: s.fatG, goal: s.fatTargetG, tint: Theme.fat)
        }
    }

    private func waterTile(_ s: DaySummary) -> some View {
        let ml = Double(profile?.quickWaterMl[safe: 1] ?? 250)
        return Button {
            context.insert(WaterRecord(ml: ml)); try? context.save()
            Task { await notifier.rebuild(context: context) }
        } label: {
            tileBody("Water", String(format: "%.1f L", s.waterMl / 1000), icon: "drop.fill", tint: Theme.water,
                     fraction: s.waterGoalMl.map { s.waterMl / $0 }, caption: s.waterGoalMl.map { String(format: "of %.1f L", $0 / 1000) })
        }
        .buttonStyle(Press())
        .sensoryFeedback(.success, trigger: waters.count)
        .accessibilityHint("Adds \(Int(ml)) millilitres")
    }

    private func tile(_ title: String, _ value: String?, icon: String, tint: Color, fraction: Double?, caption: String?) -> some View {
        tileBody(title, value ?? "None", icon: icon, tint: tint, fraction: fraction, caption: value == nil ? "Not recorded" : caption)
    }

    /// Health-style tile: colored title, big value, ring for goal progress.
    private func tileBody(_ title: String, _ value: String, icon: String, tint: Color, fraction: Double?, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                Spacer()
                ProgressRing(fraction: fraction ?? 0, tint: tint, icon: icon)
            }
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(caption ?? " ").font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .glass(20)
        .accessibilityElement(children: .combine)
    }

    /// Opens the sleep history when there is a night, otherwise the manual log so a missing Health import never blocks you.
    @ViewBuilder private func sleepTile(_ s: DaySummary) -> some View {
        let body = tile("Sleep", s.sleepHours.map { String(format: "%.1f h", $0) }, icon: "moon.fill", tint: Theme.sleep,
                        fraction: s.sleepHours.map { $0 / s.sleepTargetHours },
                        caption: s.sleepHours == nil ? "Tap to log" : "of \(String(format: "%g", s.sleepTargetHours)) h")
        if s.sleepHours == nil {
            Button { sheet = .sleepLog } label: { body }.buttonStyle(Press())
        } else {
            NavigationLink { SleepView() } label: { body }.buttonStyle(Press())
        }
    }

    private func recoveryTile(_ s: DaySummary) -> some View {
        Button { sheet = .checkIn } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recovery").font(.subheadline.weight(.semibold)).foregroundStyle(s.recoveryBand.color)
                    Spacer()
                    Image(systemName: "heart.fill").foregroundStyle(s.recoveryBand.color).frame(width: 38, height: 38)
                }
                Text(s.recoveryBand.title).font(.system(.title2, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text("Tap to check in").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .glass(20)
        }.buttonStyle(Press())
    }

    private func row(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .padding(16).glass(20)
    }

    /// One place to log anything you eat or drink. Floats over the content on a translucent layer.
    private var logBar: some View {
        HStack(spacing: 8) {
            Button { sheet = .food } label: {
                Label("Log food or drink", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(Press())
            .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
        }
        .padding(8).background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal).padding(.bottom, 4)
    }
}

/// Feedback on press-down, not release. Springs back without overshoot.
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0), value: configuration.isPressed)
    }
}
