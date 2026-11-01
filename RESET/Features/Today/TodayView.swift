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
                VStack(spacing: Theme.gap) {
                    pageNavigation
                    header(s, symptoms: symptoms)
                    foodCard(s)
                    HStack(spacing: 12) {
                        waterTile(s)
                        sleepTile(s)
                    }
                    bodyStrip(s)
                    let times = [SessionCategory.work, .university, .gym].filter { hasTime($0) }
                    ForEach(times, id: \.self) { timeRow($0, s) }
                }
                .padding(.horizontal, Theme.screenInset).padding(.top, 8)
            }
            .background(GlassBackdrop())
            .safeAreaInset(edge: .bottom) { logBar }
            .toolbar(.hidden, for: .navigationBar)
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

    /// History on the left, app name in the middle, settings on the right. 44 high, 22 inset.
    private var pageNavigation: some View {
        HStack {
            NavigationLink { TimelineScreen() } label: { Icon("history", size: 22) }.accessibilityLabel("Timeline")
            Spacer()
            Text("RE:SET AI").font(Theme.text(Theme.Size.caption, .bold)).foregroundStyle(Theme.secondaryText)
            Spacer()
            NavigationLink { SettingsView() } label: { Icon("settings", size: 22) }.accessibilityLabel("Settings and profile")
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 2).frame(height: 44)
    }

    private func header(_ s: DaySummary, symptoms: Bool) -> some View {
        let hour = Calendar.current.component(.hour, from: .now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.secondaryText)
            Text(Priority.message(s, symptoms: symptoms, hour: hour))
                .font(Theme.text(Theme.Size.headline, .bold, relativeTo: .title2)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A work, university or gym card appears only after you have been there once.
    private func hasTime(_ category: SessionCategory) -> Bool {
        sessions.contains { $0.category == category }
    }

    /// Work, university and gym fill themselves from place detection: "09:02 to 17:40, 8h 38m".
    @ViewBuilder private func timeRow(_ category: SessionCategory, _ s: DaySummary) -> some View {
        let now = Date.now
        let w = Day.interval(of: now)
        let today = sessions.filter { $0.category == category && w.contains($0.start) && $0.status != .needsReview }.sorted { $0.start < $1.start }
        let done = SessionMath.totals(sessions.map(\.value), category: category, in: w, now: now).total
        let here = today.contains { $0.end == nil }
        if hasTime(category) {
            Card(spacing: 8) {
                HStack {
                    CardHeading(icon: category == .work ? "briefcase" : (category == .gym ? "dumbbell" : "graduationcap"),
                                title: category.rawValue.capitalized, tint: Theme.secondaryText)
                    Spacer()
                    if here { Text("Here now").font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.good) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.hours(done)).font(Theme.number(Theme.Size.workNumber)).tracking(-0.8).foregroundStyle(Theme.text)
                    Spacer()
                    if let first = today.first {
                        let last = today.last?.end
                        Text("\(first.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())) to \(last.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) } ?? "now")")
                            .font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                    }
                }
                Text("Automatically filled \u{b7} No logging needed").font(Theme.text(Theme.Size.footnote)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func foodCard(_ s: DaySummary) -> some View {
        FoodSummary(kcal: s.kcalConsumed, target: s.kcalTarget, counting: s.calorieCounting,
                    protein: (s.proteinG, s.proteinTargetG), carbs: (s.carbsG, s.carbsTargetG), fat: (s.fatG, s.fatTargetG))
            .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).glass(Theme.cardRadius)
    }

    /// Recovery and steps on one slim row. Tap recovery to check in.
    private func bodyStrip(_ s: DaySummary) -> some View {
        let tint = s.recoveryBand.color
        return HStack {
            Button { sheet = .checkIn } label: {
                HStack(spacing: 7) {
                    Icon("heart-pulse", size: 17).foregroundStyle(tint)
                    Text("Recovery").font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.secondaryText)
                    Text(s.recoveryScore.map(String.init) ?? "--").font(Theme.text(Theme.Size.body, .bold)).foregroundStyle(Theme.text).monospacedDigit()
                    Text(s.recoveryBand == .unknown ? "Check in" : s.recoveryBand.title).font(Theme.text(Theme.Size.caption)).foregroundStyle(tint).lineLimit(1)
                }
            }.buttonStyle(Press())
            Spacer()
            HStack(spacing: 6) {
                Icon("footprints", size: 17).foregroundStyle(Theme.steps)
                Text(s.steps.map { $0.formatted() } ?? "None").font(Theme.text(Theme.Size.tileTitle, .semibold)).foregroundStyle(Theme.text).monospacedDigit()
            }
        }
        .padding(Theme.tilePadding).frame(maxWidth: .infinity).glass(Theme.cardRadius)
        .accessibilityElement(children: .contain)
    }

    private func waterTile(_ s: DaySummary) -> some View {
        let ml = Double(profile?.quickWaterMl[safe: 1] ?? 250)
        let goal = s.waterGoalMl.map { String(format: "of %.1f L", $0 / 1000) } ?? "No goal"
        return Button {
            context.insert(WaterRecord(ml: ml)); try? context.save()
            Task { await notifier.rebuild(context: context) }
        } label: {
            Tile(title: "Water", icon: "droplet", tint: Theme.water, value: String(format: "%.1f L", s.waterMl / 1000),
                 caption: "\(goal)  \u{b7}  +\(Int(ml)) ml", fraction: s.waterGoalMl.map { s.waterMl / $0 }, plus: true)
        }
        .buttonStyle(Press())
        .sensoryFeedback(.success, trigger: waters.count)
        .accessibilityHint("Adds \(Int(ml)) millilitres")
    }

    /// Opens the sleep history when there is a night, otherwise the manual log so a missing Health import never blocks you.
    @ViewBuilder private func sleepTile(_ s: DaySummary) -> some View {
        let body = Tile(title: "Sleep", icon: "moon", tint: Theme.sleep, value: s.sleepHours.map { String(format: "%.1f h", $0) } ?? "None",
                        caption: s.sleepHours == nil ? "Tap to log" : "of \(String(format: "%g", s.sleepTargetHours)) h",
                        fraction: s.sleepHours.map { $0 / s.sleepTargetHours })
        if s.sleepHours == nil {
            Button { sheet = .sleepLog } label: { body }.buttonStyle(Press())
        } else {
            NavigationLink { SleepView() } label: { body }.buttonStyle(Press())
        }
    }

    /// One place to log anything you eat or drink. A 243 wide lime pill floating above the tab bar, as in the design.
    private var logBar: some View {
        PillButton(title: "Log food or drink", icon: "plus") { sheet = .food }
            .frame(width: 243)
            .padding(.top, 10).padding(.bottom, 20)
            .frame(maxWidth: .infinity)
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

/// Icon in the metric color, title in the quiet text color.
struct TintedIcon: LabelStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}
