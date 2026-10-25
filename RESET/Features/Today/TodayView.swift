import SwiftUI
import SwiftData
import Observation
import Charts
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
                    recoveryHero(s)
                    foodCard(s)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        waterTile(s)
                        caffeineTile(s)
                        stepsTile(s)
                        sleepTile(s)
                    }
                    weekCard(s)
                    let times = [SessionCategory.work, .university, .gym].filter { hasTime($0) }
                    ForEach(times, id: \.self) { timeRow($0, s) }
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
                .font(.system(.title, design: .rounded, weight: .bold)).tracking(-0.6).lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
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
                Label("Food", systemImage: "fork.knife").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.food)
                Spacer()
                if let left = s.kcalRemaining, s.calorieCounting {
                    Text(left >= 0 ? "\(Int(left.rounded())) kcal left" : "\(Int((-left).rounded())) kcal over")
                        .font(.footnote.weight(.medium)).foregroundStyle(left >= 0 ? Theme.secondaryText : Theme.warn).monospacedDigit()
                }
            }
            if s.calorieCounting {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(s.kcalConsumed.rounded()))").font(.system(size: 44, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit()
                    Text(s.kcalTarget.map { "of \(Int($0.rounded())) kcal" } ?? "kcal").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                if let t = s.kcalTarget { ProgressBar(fraction: s.kcalConsumed / t, tint: Theme.food).frame(height: 8) }
            }
            HStack(spacing: 10) {
                macroColumn("Protein", s.proteinG, s.proteinTargetG, Theme.protein)
                macroColumn("Carbs", s.carbsG, s.carbsTargetG, Theme.carbs)
                macroColumn("Fat", s.fatG, s.fatTargetG, Theme.fat)
            }.padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func macroColumn(_ name: String, _ eaten: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text("\(Int(eaten.rounded())) g").font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
            if goal > 0 { ProgressBar(fraction: eaten / goal, tint: tint).frame(height: 4) }
            Text(goal > 0 ? "of \(Int(goal.rounded())) g" : " ").font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Recovery hero

    private func recoveryHero(_ s: DaySummary) -> some View {
        let tint = s.recoveryBand.color
        return Button { sheet = .checkIn } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        ArcGauge(fraction: Double(s.recoveryScore ?? 0) / 100, tint: tint)
                        VStack(spacing: 0) {
                            Text(s.recoveryScore.map(String.init) ?? "--")
                                .font(.system(size: 46, weight: .bold, design: .rounded)).tracking(-1.5).monospacedDigit()
                            Text("Recovery").font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .frame(width: 138, height: 138)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.recoveryBand.title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(tint)
                        Text(s.recoveryAdvice.isEmpty ? "Log sleep and a quick check-in to get a read." : s.recoveryAdvice)
                            .font(.subheadline).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if !s.recoveryComponents.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(s.recoveryComponents) { c in
                            ComponentBar(title: c.title, fraction: c.fraction, detail: c.detail, tint: componentTint(c.fraction))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).glass(26)
        }
        .buttonStyle(Press())
        .accessibilityHint("Opens check in")
    }

    private func componentTint(_ f: Double) -> Color { f >= 0.75 ? Theme.good : (f >= 0.5 ? Theme.warn : Theme.low) }

    // MARK: Week

    private func weekCard(_ s: DaySummary) -> some View {
        let cal = Calendar.current
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }
        let sleepByDay = days.map { d in (day: d, hours: sleeps.first { cal.isDate($0.day, inSameDayAs: d) }?.hours) }
        return Card(title: "This week") {
            HStack(alignment: .top, spacing: 14) {
                weekChart("Steps", tint: Theme.steps, goal: 8000,
                          data: days.map { d in (d, Double(health.week.first { cal.isDate($0.day, inSameDayAs: d) }?.steps ?? 0)) })
                weekChart("Sleep h", tint: Theme.sleep, goal: s.sleepTargetHours,
                          data: sleepByDay.map { ($0.day, $0.hours ?? 0) })
            }
        }
    }

    private func weekChart(_ title: String, tint: Color, goal: Double, data: [(Date, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Chart {
                ForEach(data, id: \.0) { d, v in
                    BarMark(x: .value("Day", d, unit: .day), y: .value(title, v), width: .fixed(9))
                        .foregroundStyle(v >= goal ? tint : tint.opacity(0.45)).clipShape(Capsule())
                }
                RuleMark(y: .value("Goal", goal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.secondaryText.opacity(0.5))
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2) } }
            .frame(height: 84)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Compact metric tile: icon and name, one big number, a goal bar underneath.
    private func tileBody(_ title: String, _ value: String, icon: String, tint: Color, fraction: Double?, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.5).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            ProgressBar(fraction: fraction ?? 0, tint: tint).frame(height: 5).opacity(fraction == nil ? 0.3 : 1)
            Text(caption ?? " ").font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .glass(22)
        .accessibilityElement(children: .combine)
    }

    private func stepsTile(_ s: DaySummary) -> some View {
        tile("Steps", s.steps.map { $0.formatted() }, icon: "figure.walk", tint: Theme.steps,
             fraction: s.steps.map { Double($0) / 8000 }, caption: "of 8,000")
    }

    private func caffeineTile(_ s: DaySummary) -> some View {
        NavigationLink { ScrollView { CaffeineCard().padding() }.background(GlassBackdrop()).navigationTitle("Caffeine") } label: {
            tileBody("Caffeine", "\(Int(s.caffeineMg.rounded())) mg", icon: "cup.and.saucer.fill", tint: Theme.carbs,
                     fraction: s.caffeineMg / 400, caption: "of 400 mg guide")
        }.buttonStyle(Press())
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
