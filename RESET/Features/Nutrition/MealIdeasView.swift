import SwiftUI
import SwiftData
import ResetCore

enum MealIdeaBuilder {
    /// Builds the request from stored data. Remaining values are nil or zero when nothing is known, never guessed.
    @MainActor
    static func request(context: ModelContext, profile: UserProfile?, health: HealthService?, slot: MealType, eating: EatingContext, minutes: Int = 30) -> SuggestionRequest {
        let s = DaySummaryBuilder.build(context: context, profile: profile, health: health)
        let meals = ((try? context.fetch(FetchDescriptor<MealRecord>())) ?? []).filter { Calendar.current.isDateInToday($0.at) }
        var left = 1
        if let p = profile {
            let slots = MealTiming.slots(pattern: p.mealPattern, shape: DayShape(wakeMinute: p.wakeMinute, bedMinute: p.bedMinute), on: .now)
            let logs = meals.map { (at: $0.at, type: $0.mealType) }
            left = max(1, slots.filter { $0.time > .now && !MealTiming.isCovered($0, logs: logs) }.count)
        }
        return SuggestionRequest(slot: slot, context: eating, remainingKcal: s.calorieCounting ? s.kcalRemaining : nil,
                                 remainingProteinG: max(0, s.proteinTargetG - s.proteinG), mealsLeft: left, minutes: minutes,
                                 preferences: profile?.dietaryPreferences ?? [], allergies: profile?.allergies ?? [],
                                 eatenToday: meals.flatMap { $0.items.map(\.name) }, counting: s.calorieCounting)
    }
}

extension MealIdea {
    /// A draft item the user confirms and edits. Marked as an estimate with low confidence.
    var draftItem: FoodItem {
        FoodItem(name: name, grams: 400, nutrition: nutrition, dataSource: "RE:SET meal idea, typical estimate", verified: false, confidence: .low)
    }
}

struct MealIdeasCard: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query private var profiles: [UserProfile]
    // Re-evaluate when logs change.
    @Query private var meals: [MealRecord]
    @AppStorage("meal.context") private var contextRaw = EatingContext.cafeteria.rawValue
    @State private var slot = AddFoodView.guessMealType()
    @State private var draft: [FoodItem] = []
    @State private var showDraft = false

    private var eating: EatingContext { EatingContext(rawValue: contextRaw) ?? .cafeteria }

    var body: some View {
        let _ = meals.count
        let req = MealIdeaBuilder.request(context: context, profile: profiles.first, health: health, slot: slot, eating: eating)
        let ideas = MealSuggester.suggest(req)
        Card(title: "What to eat") {
            Picker("Meal", selection: $slot) { ForEach(MealType.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("Where", selection: $contextRaw) { ForEach(EatingContext.allCases, id: \.self) { Text($0.title).tag($0.rawValue) } }
            if let k = req.remainingKcal { Text("About \(Int(max(0, k).rounded())) kcal and \(Int(req.remainingProteinG.rounded())) g protein left today.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            else { Text("About \(Int(req.remainingProteinG.rounded())) g protein left today.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if ideas.isEmpty {
                Text("No matching idea with your diet, allergy and setting choices. Try another setting.").font(.footnote)
            }
            ForEach(ideas) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.idea.name).font(.headline)
                        Spacer()
                        Text("\(Int(m.idea.nutrition.kcal)) kcal, \(Int(m.idea.nutrition.proteinG)) g P").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                    }
                    Text(m.reason).font(.footnote)
                    Text(m.idea.tip).font(.caption).foregroundStyle(Theme.secondaryText)
                    Button("Log this") { draft = [m.idea.draftItem]; showDraft = true }.font(.footnote)
                }
                if m.id != ideas.last?.id { Divider() }
            }
            Text(MealSuggester.disclaimer).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $showDraft) { AddFoodView(initialItems: draft, startWith: .manual) }
    }
}
