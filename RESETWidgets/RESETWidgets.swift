import WidgetKit
import SwiftUI
import AppIntents

// MARK: Shared pieces

private func isToday(_ s: WidgetSnapshot?) -> Bool { s.map { Calendar.current.isDateInToday($0.updated) } ?? false }
private func liters(_ ml: Double) -> String { String(format: "%.2f L", ml / 1000) }
private func clampMl(_ v: Int) -> Int { min(1500, max(50, v)) }

private extension View {
    /// Home screen widgets get a dark card. Lock screen widgets must stay transparent and use system colors.
    @ViewBuilder func widgetBackground(_ family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            self.containerBackground(for: .widget) { Color.clear }
        default:
            self.containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.09) }.foregroundStyle(.white)
        }
    }
}

// MARK: Today widget (home and lock screen)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(updated: .now, waterMl: 1250, waterGoalMl: 3000, kcal: 1400, kcalTarget: 2200,
                                                          countCalories: true, proteinG: 90, proteinTargetG: 150, steps: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, snapshot: SharedStore.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app pushes updates. This is only a fallback so old data is flagged as old.
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: SharedStore.snapshot())], policy: .after(Date.now.addingTimeInterval(3600))))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: home
            }
        }
        .widgetBackground(family)
    }

    private var fresh: WidgetSnapshot? { isToday(entry.snapshot) ? entry.snapshot : nil }

    // Lock screen

    @ViewBuilder private var circular: some View {
        if let s = fresh {
            Button(intent: QueueWaterIntent(ml: 250)) {
                if let g = s.waterGoalMl, g > 0 {
                    Gauge(value: min(1, s.waterMl / g)) { Image(systemName: "drop.fill") }.gaugeStyle(.accessoryCircularCapacity)
                } else {
                    ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Image(systemName: "drop.fill").font(.caption); Text(String(format: "%.1f", s.waterMl / 1000)).font(.caption.bold()) } }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add 250 millilitres of water. \(liters(s.waterMl)) today.")
        } else {
            ZStack { AccessoryWidgetBackground(); Image(systemName: "drop") }.widgetURL(DeepLink.food.url)
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let s = fresh {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Water", systemImage: "drop.fill").font(.caption.weight(.semibold))
                    Spacer()
                    Text(liters(s.waterMl)).font(.caption.bold()).monospacedDigit()
                }
                if let g = s.waterGoalMl, g > 0 { ProgressView(value: min(1, s.waterMl / g)) }
                HStack {
                    Button(intent: QueueWaterIntent(ml: 250)) { Label("250 ml", systemImage: "plus") }
                        .buttonStyle(.plain).font(.caption2.weight(.semibold))
                    Spacer()
                    Text("\(Int(s.proteinG.rounded())) g protein").font(.caption2)
                }
            }
        } else {
            VStack(alignment: .leading) { Text("RE:SET").font(.caption.bold()); Text("Open the app to refresh").font(.caption2) }
                .widgetURL(DeepLink.food.url)
        }
    }

    @ViewBuilder private var inline: some View {
        if let s = fresh {
            if let g = s.waterGoalMl, g > 0 { Label("\(liters(s.waterMl)) of \(String(format: "%.1f", g / 1000)) L", systemImage: "drop.fill") }
            else { Label(liters(s.waterMl), systemImage: "drop.fill") }
        } else { Label("Open RE:SET", systemImage: "drop") }
    }

    // Home screen

    @ViewBuilder private var home: some View {
        if let s = fresh { homeContent(s) } else {
            VStack(spacing: 4) {
                Image(systemName: "drop")
                Text(entry.snapshot == nil ? "Open RE:SET" : "Open RE:SET to refresh").font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                Text("Nothing recorded yet today").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func homeContent(_ s: WidgetSnapshot) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                water(s)
                Button(intent: QueueWaterIntent(ml: 250)) { Label("250 ml", systemImage: "plus").font(.caption.weight(.semibold)) }
                    .buttonStyle(.plain).padding(.vertical, 4).padding(.horizontal, 10)
                    .background(Color.cyan.opacity(0.35), in: Capsule())
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    water(s)
                    HStack {
                        ForEach([150, 250, 500], id: \.self) { ml in
                            Button(intent: QueueWaterIntent(ml: ml)) { Text("+\(ml)").font(.caption.weight(.semibold)) }
                                .buttonStyle(.plain).padding(.vertical, 4).padding(.horizontal, 8)
                                .background(Color.cyan.opacity(0.35), in: Capsule())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if s.countCalories {
                        Text("\(Int(s.kcal.rounded()))").font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                        Text(s.kcalTarget.map { "of about \(Int($0.rounded())) kcal" } ?? "kcal logged").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(Int(s.proteinG.rounded())) g protein").font(.caption.weight(.semibold))
                    if s.proteinTargetG > 0 { Text("of about \(Int(s.proteinTargetG.rounded())) g").font(.caption2).foregroundStyle(.secondary) }
                    Text("Estimates").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func water(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Water", systemImage: "drop.fill").font(.caption).foregroundStyle(.cyan)
            Text(liters(s.waterMl)).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            if let g = s.waterGoalMl, g > 0 {
                ProgressView(value: min(1, s.waterMl / g)).tint(.cyan)
                Text(String(format: "goal about %.1f L", g / 1000)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Water, calories and protein for today, with water buttons. Values are what you have logged, and estimates.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Quick action widget (user picks what it does)

enum QuickActionKind: String, AppEnum {
    case water, energy, logFood, photoMeal, startWalk, askCoach

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static var caseDisplayRepresentations: [QuickActionKind: DisplayRepresentation] = [
        .water: "Add water", .energy: "Energy check-in", .logFood: "Log food",
        .photoMeal: "Photograph a meal", .startWalk: "Start a walk", .askCoach: "Ask the coach",
    ]

    var title: String {
        switch self {
        case .water: "Add water"
        case .energy: "Energy"
        case .logFood: "Log food"
        case .photoMeal: "Meal photo"
        case .startWalk: "Start walk"
        case .askCoach: "Ask coach"
        }
    }

    var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .energy: "bolt.heart.fill"
        case .logFood: "fork.knife"
        case .photoMeal: "camera.fill"
        case .startWalk: "figure.walk"
        case .askCoach: "sparkles"
        }
    }

    /// Where a tap goes for actions that need the app. Water and energy are handled inside the widget.
    var link: DeepLink? {
        switch self {
        case .logFood: .food
        case .photoMeal: .photo
        case .startWalk: .walk
        case .askCoach: .coach
        case .water, .energy: nil
        }
    }
}

struct QuickActionConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Quick action"
    static var description = IntentDescription("Choose what this widget does when you tap it.")

    @Parameter(title: "Action", default: .water)
    var action: QuickActionKind

    @Parameter(title: "Water amount (ml)", default: 250)
    var ml: Int

    init() {}
}

struct QuickActionEntry: TimelineEntry {
    let date: Date
    let action: QuickActionKind
    let ml: Int
    let snapshot: WidgetSnapshot?
}

struct QuickActionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickActionEntry { QuickActionEntry(date: .now, action: .water, ml: 250, snapshot: nil) }

    func snapshot(for c: QuickActionConfig, in context: Context) async -> QuickActionEntry {
        QuickActionEntry(date: .now, action: c.action, ml: clampMl(c.ml), snapshot: SharedStore.snapshot())
    }

    func timeline(for c: QuickActionConfig, in context: Context) async -> Timeline<QuickActionEntry> {
        Timeline(entries: [QuickActionEntry(date: .now, action: c.action, ml: clampMl(c.ml), snapshot: SharedStore.snapshot())],
                 policy: .after(Date.now.addingTimeInterval(3600)))
    }
}

struct QuickActionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickActionEntry

    private var snap: WidgetSnapshot? { isToday(entry.snapshot) ? entry.snapshot : nil }
    private var energyToday: Int? {
        guard let s = entry.snapshot, let at = s.lastEnergyAt, Calendar.current.isDateInToday(at) else { return nil }
        return s.lastEnergy
    }

    var body: some View {
        Group {
            switch entry.action {
            case .water: water
            case .energy: energy
            default: opener
            }
        }
        .widgetBackground(family)
    }

    private var lock: Bool { family == .accessoryCircular || family == .accessoryRectangular }

    // Add water

    @ViewBuilder private var water: some View {
        let total = snap?.waterMl
        switch family {
        case .accessoryCircular:
            Button(intent: QueueWaterIntent(ml: entry.ml)) {
                ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Image(systemName: "drop.fill"); Text("+\(entry.ml)").font(.caption2.bold()) } }
            }.buttonStyle(.plain).accessibilityLabel("Add \(entry.ml) millilitres of water")
        case .accessoryRectangular:
            Button(intent: QueueWaterIntent(ml: entry.ml)) {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Add \(entry.ml) ml", systemImage: "drop.fill").font(.caption.weight(.semibold))
                    Text(total.map { "Today \(liters($0))" } ?? "Open RE:SET to sync").font(.caption2)
                }
            }.buttonStyle(.plain)
        default:
            Button(intent: QueueWaterIntent(ml: entry.ml)) {
                VStack(spacing: 6) {
                    Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(.cyan)
                    Text("+\(entry.ml) ml").font(.system(.title3, design: .rounded, weight: .bold))
                    Text(total.map { "Today \(liters($0))" } ?? "Tap to add").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain)
        }
    }

    // Energy check-in

    private static let choices: [(String, Int)] = [("Low", 2), ("OK", 3), ("Great", 5)]

    @ViewBuilder private var energy: some View {
        switch family {
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); Image(systemName: "bolt.heart.fill") }.widgetURL(DeepLink.checkIn.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(energyToday.map { "Energy saved: \($0) of 5" } ?? "How is your energy?").font(.caption.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach(Self.choices, id: \.1) { c in
                        Button(intent: QueueCheckInIntent(value: c.1)) { Text(c.0).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).overlay(Capsule().stroke(lineWidth: 1)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Energy", systemImage: "bolt.heart.fill").font(.caption).foregroundStyle(.yellow)
                Text(energyToday.map { "Saved: \($0) of 5" } ?? "How is it right now?").font(.footnote.weight(.semibold))
                ForEach(Self.choices, id: \.1) { c in
                    Button(intent: QueueCheckInIntent(value: c.1)) { Text(c.0).font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4).background(Color.yellow.opacity(0.3), in: Capsule()) }
                        .buttonStyle(.plain)
                }
                if energyToday != nil { Text("Syncs when you open RE:SET").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }
    }

    // Actions that open the app

    @ViewBuilder private var opener: some View {
        let a = entry.action
        switch family {
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); Image(systemName: a.symbol).font(.title3) }.widgetURL(a.link?.url)
        case .accessoryRectangular:
            HStack { Image(systemName: a.symbol).font(.title3); VStack(alignment: .leading) { Text(a.title).font(.caption.weight(.semibold)); Text("Tap to open").font(.caption2) } }
                .widgetURL(a.link?.url)
        default:
            VStack(spacing: 8) {
                Image(systemName: a.symbol).font(.largeTitle).foregroundStyle(Color(red: 0.8, green: 1.0, blue: 0.2))
                Text(a.title).font(.system(.title3, design: .rounded, weight: .bold))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).widgetURL(a.link?.url)
        }
    }
}

struct QuickActionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickActionWidget", intent: QuickActionConfig.self, provider: QuickActionProvider()) { entry in
            QuickActionView(entry: entry)
        }
        .configurationDisplayName("Quick action")
        .description("One tap to add water, record your energy, or jump to logging food, a meal photo, a walk or the coach. Touch and hold the widget, then Edit Widget, to choose.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct RESETWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        QuickActionWidget()
    }
}
