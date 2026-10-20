import SwiftUI
import SwiftData
import ResetCore

enum RecoverySnapshot {
    /// Gathers inputs from stored data only. Missing data stays missing, it is never filled in.
    static func input(context: ModelContext, profile: UserProfile?, now: Date = .now) -> RecoveryInput {
        let cal = Calendar.current
        let sleeps = ((try? context.fetch(FetchDescriptor<SleepRecord>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []).prefix(3)
        let since24 = now.addingTimeInterval(-24 * 3600)
        let checks = ((try? context.fetch(FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? []).filter { $0.at >= since24 }
        func latest(_ k: CheckInKind) -> Int? { checks.first { $0.kind == k }?.value }

        let sessions = ((try? context.fetch(FetchDescriptor<TrackedSession>())) ?? []).map(\.value)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let workH = [now, yesterday].map { SessionMath.totals(sessions, category: .work, in: Day.interval(of: $0), now: now).total / 3600 }.max() ?? 0

        let acts = (try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []
        let hard = acts.filter { ($0.kind == .strength || $0.kind == .run) && $0.minutes >= 30 }
        let last48 = hard.filter { $0.start >= now.addingTimeInterval(-48 * 3600) }.count
        var streak = 0
        for back in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -back, to: now) else { break }
            let had = hard.contains { cal.isDate($0.start, inSameDayAs: d) }
            if had { streak += 1 } else if back > 0 { break }
        }
        let yWindow = Day.interval(of: yesterday)
        let waterMl = ((try? context.fetch(FetchDescriptor<WaterRecord>())) ?? []).filter { yWindow.contains($0.at) }.reduce(0) { $0 + $1.ml }
        let waterShare = profile?.effectiveWaterGoalMl.flatMap { waterMl > 0 ? waterMl / $0 : nil }
        let meals = ((try? context.fetch(FetchDescriptor<MealRecord>())) ?? []).map { ($0.at, $0.items) }
        let eaten = NutritionTotals.day(meals, on: yesterday, calendar: cal)
        let counting = profile?.calorieCountingEnabled ?? true
        let intakeShare = (counting && eaten.mealCount > 0) ? profile?.energyPlan.targetKcal.map { eaten.total.kcal / $0 } : nil
        let stored = UserDefaults.standard.integer(forKey: HealthService.yesterdayStepsKey)
        return RecoveryInput(sleepHours: sleeps.map(\.hours), sleepTargetHours: profile?.sleepTargetHours ?? 8,
                             sleepQuality: sleeps.first.flatMap { Calendar.current.isDate($0.day, inSameDayAs: now) ? $0.quality : nil },
                             energy: latest(.energy), fatigue: latest(.fatigue), workHoursRecent: workH > 0 ? workH : nil,
                             strenuousSessionsLast48h: last48, consecutiveTrainingDays: streak,
                             symptomsReported: checks.contains { $0.kind == .symptom },
                             waterShare: waterShare, intakeShare: intakeShare, yesterdaySteps: stored > 0 ? stored : nil)
    }

    static func assess(context: ModelContext, profile: UserProfile?) -> RecoveryResult {
        RecoveryEngine.assess(input(context: context, profile: profile))
    }

    /// One stored assessment per day, so history shows how the indicator moved.
    static func store(_ r: RecoveryResult, context: ModelContext, now: Date = .now) {
        let existing = ((try? context.fetch(FetchDescriptor<RecoveryAssessment>())) ?? []).filter { Calendar.current.isDate($0.day, inSameDayAs: now) }
        if let e = existing.first { e.bandRaw = r.band.rawValue; e.reasons = r.reasons }
        else { context.insert(RecoveryAssessment(day: Calendar.current.startOfDay(for: now), bandRaw: r.band.rawValue, reasons: r.reasons)) }
        try? context.save()
    }
}

extension RecoveryBand {
    var color: Color {
        switch self {
        case .good: Theme.good
        case .moderate: Theme.warn
        case .low: Theme.low
        case .unknown: Theme.secondaryText
        }
    }
}

struct RecoveryCard: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var sleeps: [SleepRecord]
    @Query private var checks: [CheckIn]
    @Query private var activities: [ActivityRecord]
    @State private var checkingIn = false

    var body: some View {
        let r = RecoverySnapshot.assess(context: context, profile: profiles.first)
        let _ = (sleeps.count, checks.count, activities.count) // re-evaluate when inputs change
        Card(title: "Recovery") {
            HStack {
                Circle().fill(r.band.color).frame(width: 14, height: 14)
                Text(r.band.title).font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Button("Check in") { checkingIn = true }.buttonStyle(.bordered)
            }
            Text(r.advice).font(.subheadline)
            ForEach(r.reasons, id: \.self) { Text("• \($0)").font(.footnote).foregroundStyle(Theme.secondaryText) }
            Text(RecoveryResult.disclaimer).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $checkingIn) { CheckInSheet() }
        .onChange(of: r.band) { _, _ in RecoverySnapshot.store(r, context: context) }
        .task { RecoverySnapshot.store(r, context: context) }
    }
}

struct CheckInSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var energy = 3
    @State private var fatigue = 3
    @State private var hasSymptom = false
    @State private var symptom = ""
    @State private var saved = false

    private var urgent: Bool { hasSymptom && Safety.needsUrgentCare(symptom) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Energy right now") {
                    Picker("Energy", selection: $energy) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    Text("1 drained, 5 great").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Section("Fatigue") {
                    Picker("Fatigue", selection: $fatigue) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    Text("1 fresh, 5 exhausted").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Section {
                    Toggle("Something feels wrong", isOn: $hasSymptom)
                    if hasSymptom {
                        TextField("e.g. dizzy, chest pain, racing heart", text: $symptom, axis: .vertical)
                    }
                    if urgent { Text(Safety.urgentMessage).foregroundStyle(Theme.low) }
                } footer: { Text("Dizziness, illness or anything concerning means rest, not a harder workout.") }
            }
            .navigationTitle("Check in").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        context.insert(CheckIn(kind: .energy, value: energy))
        context.insert(CheckIn(kind: .fatigue, value: fatigue))
        if hasSymptom && !symptom.trimmingCharacters(in: .whitespaces).isEmpty {
            context.insert(CheckIn(kind: .symptom, value: 0, note: symptom))
        }
        try? context.save()
        if urgent { return } // keep the sheet open so the message stays visible
        dismiss()
    }
}
