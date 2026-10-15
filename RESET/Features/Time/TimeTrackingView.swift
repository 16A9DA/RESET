import SwiftUI
import SwiftData
import ResetCore

struct TimeTrackingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedSession.start, order: .reverse) private var sessions: [TrackedSession]
    @State private var editing: TrackedSession?
    @State private var addingManual = false

    private var values: [SessionValue] { sessions.map(\.value) }
    private var needsReview: [TrackedSession] { sessions.filter { $0.status == .needsReview } }

    var body: some View {
        List {
            Section {
                TotalsCard(category: .work, values: values)
                TotalsCard(category: .university, values: values)
            }
            .listRowBackground(Color.clear).listRowInsets(.init())

            Section("Timer") {
                TimerRow(category: .work, sessions: sessions)
                TimerRow(category: .university, sessions: sessions)
            }

            if !needsReview.isEmpty {
                Section {
                    ForEach(needsReview) { s in row(s) }
                } header: {
                    Text("Needs review")
                } footer: {
                    Text("Missed or conflicting events are kept here until you fix or delete them. They are not counted in totals.")
                }
            }

            Section("History") {
                if sessions.isEmpty {
                    EmptyNote(systemImage: "clock", title: "No sessions yet",
                              message: "Start a timer, add a place for automatic suggestions, or add a session by hand.")
                }
                ForEach(sessions.filter { $0.status != .needsReview }) { s in row(s) }
            }

            Section {
                NavigationLink("Places and permissions") { PlacesView() }
                Button("Add session by hand") { addingManual = true }
            }
        }
        .navigationTitle("Work and University")
        .sheet(item: $editing) { SessionEditor(session: $0) }
        .sheet(isPresented: $addingManual) { SessionEditor(session: nil) }
    }

    private func row(_ s: TrackedSession) -> some View {
        Button { editing = s } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(s.category.rawValue.capitalized).font(.headline)
                    Spacer()
                    Text(label(for: s)).font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                }
                Text("\(s.start.formatted(date: .abbreviated, time: .shortened)) to \(s.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? "now")")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                if !s.breaks.isEmpty {
                    Text("\(s.breaks.count) break(s)").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions { Button("Delete", role: .destructive) { context.delete(s); try? context.save() } }
    }

    private func label(for s: TrackedSession) -> String {
        switch (s.status, s.source) {
        case (.needsReview, _): "Review"
        case (_, .manual): "Manual"
        case (.confirmed, _): "Confirmed"
        default: "Estimated"
        }
    }
}

struct TotalsCard: View {
    let category: SessionCategory
    let values: [SessionValue]

    var body: some View {
        let now = Date.now
        let day = SessionMath.totals(values, category: category, in: Day.interval(of: now), now: now)
        let week = SessionMath.totals(values, category: category, in: SessionMath.week(of: now), now: now)
        let month = SessionMath.totals(values, category: category, in: SessionMath.month(of: now), now: now)
        Card(title: category == .work ? "Work" : "University") {
            HStack(alignment: .top, spacing: 20) {
                cell("Today", day)
                cell("Week", week)
                cell("Month", month)
            }
            if week.estimated > 0 {
                Text("Includes \(Fmt.hours(week.estimated)) of location estimates this week. Confirm sessions to firm them up.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ title: String, _ t: SessionTotals) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(t.total == 0 ? "Not recorded" : Fmt.hours(t.total))
                .font(.system(t.total == 0 ? .footnote : .title3, design: .rounded, weight: .bold)).monospacedDigit()
        }
    }
}

struct TimerRow: View {
    @Environment(\.modelContext) private var context
    let category: SessionCategory
    let sessions: [TrackedSession]

    private var running: TrackedSession? {
        sessions.first { $0.category == category && $0.end == nil && $0.source == .manual }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(category == .work ? "Work timer" : "University timer")
                if let r = running {
                    Text("Since \(r.start.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Button(running == nil ? "Start" : "Stop") {
                if let r = running { r.end = .now } else {
                    context.insert(TrackedSession(category: category, start: .now, status: .confirmed, source: .manual))
                }
                try? context.save()
            }
            .buttonStyle(.borderedProminent).tint(running == nil ? Theme.accent : Theme.low).foregroundStyle(.black)
        }
    }
}

struct SessionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let session: TrackedSession?

    @State private var category: SessionCategory = .work
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var end = Date.now
    @State private var isOpen = false
    @State private var breaks: [BreakInterval] = []
    @State private var note = ""

    private var invalid: Bool { !isOpen && end <= start }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $category) {
                    Text("Work").tag(SessionCategory.work)
                    Text("University").tag(SessionCategory.university)
                    Text("Gym").tag(SessionCategory.gym)
                    Text("Other").tag(SessionCategory.other)
                }
                DatePicker("Start", selection: $start)
                Toggle("Still running", isOn: $isOpen)
                if !isOpen { DatePicker("End", selection: $end, in: start...) }
                Section("Breaks") {
                    ForEach(breaks.indices, id: \.self) { i in
                        DatePicker("From", selection: $breaks[i].start)
                        DatePicker("To", selection: $breaks[i].end)
                    }
                    .onDelete { breaks.remove(atOffsets: $0) }
                    Button("Add break") { breaks.append(BreakInterval(start: start, end: start.addingTimeInterval(1800))) }
                }
                Section("Note") { TextField("Optional", text: $note) }
                if invalid { Text("End must be after start.").foregroundStyle(Theme.low) }
            }
            .navigationTitle(session == nil ? "New session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(invalid) }
            }
            .onAppear {
                guard let s = session else { return }
                category = s.category; start = s.start; end = s.end ?? .now; isOpen = s.end == nil
                breaks = s.breaks; note = s.note
            }
        }
    }

    private func save() {
        let s = session ?? TrackedSession(category: category, start: start, source: .manual)
        s.category = category; s.start = start; s.end = isOpen ? nil : end
        s.breaks = breaks; s.note = note
        // A user edit is a confirmation. The original source stays so history shows it began as an estimate.
        s.status = .confirmed
        if session == nil { context.insert(s) }
        try? context.save()
        dismiss()
    }
}
