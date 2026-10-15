import SwiftUI
import SwiftData
import ResetCore

struct TimelineScreen: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [TrackedSession]
    @Query private var meals: [MealRecord]
    @Query private var water: [WaterRecord]
    @State private var day = Date.now

    var body: some View {
        let _ = (sessions.count, meals.count, water.count)
        let entries = DaySummaryBuilder.timeline(context: context, day: day)
        List {
            DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
            if entries.isEmpty {
                EmptyNote(systemImage: "list.bullet.clipboard", title: "Nothing recorded",
                          message: "Sleep, work, meals, water and walks appear here as you log them or as they are detected.")
            }
            ForEach(entries) { e in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(e.kind)).frame(width: 24).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.title).font(.headline)
                            Spacer()
                            Text(timeText(e)).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        if !e.detail.isEmpty { Text(e.detail).font(.subheadline).foregroundStyle(Theme.secondaryText) }
                        Text(e.origin.rawValue).font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Section {
                NavigationLink("Edit work and university times") { TimeTrackingView() }
            } footer: {
                Text("Tap through to correct anything that looks wrong. Meals can be edited from the Nutrition tab.")
            }
        }
        .navigationTitle("Timeline")
    }

    private func timeText(_ e: TimelineEntry) -> String {
        let s = e.start.formatted(date: .omitted, time: .shortened)
        guard let end = e.end else { return s }
        return "\(s) to \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func icon(_ k: TimelineKind) -> String {
        switch k {
        case .sleep: "bed.double.fill"
        case .work: "briefcase.fill"
        case .university: "graduationcap.fill"
        case .meal: "fork.knife"
        case .water: "drop.fill"
        case .caffeine: "cup.and.saucer.fill"
        case .activity: "figure.walk"
        case .workout: "dumbbell.fill"
        case .checkIn: "heart.text.square"
        case .reminder: "bell"
        }
    }
}
