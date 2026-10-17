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
    case food, photo, barcode, checkIn, canEat
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
                    ForEach([SessionCategory.work, .university, .gym], id: \.self) { timeRow($0, s) }
                    foodCard(s)
                    HStack(spacing: 12) {
                        waterTile(s)
                        tile("Steps", s.steps.map { $0.formatted() }, icon: "figure.walk")
                        tile("Sleep", s.sleepHours.map { String(format: "%.1f h", $0) }, icon: "moon")
                    }
                    Button { sheet = .canEat } label: { row("Can I eat this?", icon: "questionmark.circle") }.buttonStyle(Press())
                    recoveryRow(s)
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
                Label("Food", systemImage: "fork.knife").font(.headline)
                Spacer()
                if s.calorieCounting {
                    Text("\(Int(s.kcalConsumed.rounded()))").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                    + Text(s.kcalTarget.map { " / \(Int($0.rounded())) kcal" } ?? " kcal").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            if s.calorieCounting, let t = s.kcalTarget { ProgressBar(fraction: s.kcalConsumed / t) }
            HStack {
                Text("Protein").foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("\(Int(s.proteinG.rounded())) / \(Int(s.proteinTargetG.rounded())) g").monospacedDigit()
            }.font(.subheadline)
        }
    }

    private func waterTile(_ s: DaySummary) -> some View {
        let ml = Double(profile?.quickWaterMl[safe: 1] ?? 250)
        return Button {
            context.insert(WaterRecord(ml: ml)); try? context.save()
            Task { await notifier.rebuild(context: context) }
        } label: {
            tileBody("Water", String(format: "%.1f L", s.waterMl / 1000), icon: "drop")
        }
        .buttonStyle(Press())
        .sensoryFeedback(.success, trigger: waters.count)
        .accessibilityHint("Adds \(Int(ml)) millilitres")
    }

    private func tile(_ title: String, _ value: String?, icon: String) -> some View {
        tileBody(title, value ?? "None", icon: icon)
    }

    private func tileBody(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .glass(20)
    }

    private func recoveryRow(_ s: DaySummary) -> some View {
        Button { sheet = .checkIn } label: {
            HStack {
                Circle().fill(s.recoveryBand.color).frame(width: 12, height: 12)
                Text("Recovery").font(.headline)
                Spacer()
                Text(s.recoveryBand.title).foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .padding(16).glass(20)
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
            barButton("camera.fill", "Photo") { sheet = .photo }
            barButton("barcode.viewfinder", "Barcode") { sheet = .barcode }
        }
        .padding(8).background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal).padding(.bottom, 4)
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.headline).frame(width: 48, height: 48)
        }
        .buttonStyle(Press())
        .background(Color.primary.opacity(0.12), in: Circle())
        .accessibilityLabel(label)
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
