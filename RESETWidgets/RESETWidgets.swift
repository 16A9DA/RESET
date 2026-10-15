import WidgetKit
import SwiftUI
import AppIntents

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
        let entry = SnapshotEntry(date: .now, snapshot: SharedStore.snapshot())
        // The app pushes updates. This is only a fallback so old data is flagged as old.
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(3600))))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var isToday: Bool { entry.snapshot.map { Calendar.current.isDateInToday($0.updated) } ?? false }

    var body: some View {
        Group {
            if let s = entry.snapshot, isToday { content(s) }
            else {
                VStack(spacing: 4) {
                    Image(systemName: "drop")
                    Text(entry.snapshot == nil ? "Open RE:SET" : "Open RE:SET to refresh").font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                    Text("Nothing recorded yet today").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.09) }
        .foregroundStyle(.white)
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                water(s)
                Button(intent: QueueWaterIntent(ml: 250)) { Label("250 ml", systemImage: "plus") .font(.caption.weight(.semibold)) }
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
            Text(String(format: "%.2f L", s.waterMl / 1000)).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
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
        .description("Water, calories and protein for today. Tap to add water. Values are what you have logged, and estimates.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RESETWidgetBundle: WidgetBundle {
    var body: some Widget { TodayWidget() }
}
