import Testing
@testable import ResetCore

private func req(_ slot: MealType = .dinner, _ ctx: EatingContext = .home, kcal: Double? = 800, protein: Double = 60, mealsLeft: Int = 1,
                 minutes: Int = 30, prefs: [String] = [], allergies: [String] = [], eaten: [String] = []) -> SuggestionRequest {
    SuggestionRequest(slot: slot, context: ctx, remainingKcal: kcal, remainingProteinG: protein, mealsLeft: mealsLeft, minutes: minutes,
                      preferences: prefs, allergies: allergies, eatenToday: eaten)
}

@Test func returnsSlotAndContextMatches() {
    let s = MealSuggester.suggest(req(.dinner, .cafeteria))
    #expect(!s.isEmpty && s.allSatisfy { $0.idea.contexts.contains(.cafeteria) && $0.idea.slots.contains(.dinner) })
}

@Test func timeLimitHidesLongRecipes() {
    let s = MealSuggester.suggest(req(.dinner, .home, minutes: 10), limit: 20)
    #expect(s.allSatisfy { $0.idea.prepMinutes <= 10 })
}

@Test func allergyFilterIsConservative() {
    let all = MealSuggester.suggest(req(.breakfast, .home, allergies: ["eggs"]), limit: 50)
    #expect(!all.contains { $0.idea.ingredients.contains("eggs") || $0.idea.tags.contains("egg") })
    let nuts = MealSuggester.suggest(req(.snack, .quick, allergies: ["nuts"]), limit: 50)
    #expect(!nuts.contains { $0.idea.tags.contains("nuts") || $0.idea.ingredients.contains("almonds") })
    let peanut = MealSuggester.suggest(req(.snack, .quick, allergies: ["peanut"]), limit: 50)
    #expect(!peanut.contains { $0.idea.tags.contains("peanuts") })
}

@Test func tooShortAllergyWordsAreIgnoredNotMatchedEverywhere() {
    #expect(!MealSuggester.suggest(req(allergies: ["a"]), limit: 50).isEmpty)
}

@Test func dietPreferencesApply() {
    let veg = MealSuggester.suggest(req(.dinner, .home, prefs: ["Vegetarian"]), limit: 50)
    #expect(!veg.isEmpty && veg.allSatisfy { $0.idea.vegetarian })
    let vegan = MealSuggester.suggest(req(.dinner, .home, prefs: ["vegan"]), limit: 50)
    #expect(vegan.allSatisfy { $0.idea.vegan })
    let gf = MealSuggester.suggest(req(.breakfast, .quick, prefs: ["gluten free"]), limit: 50)
    #expect(gf.allSatisfy { !$0.idea.tags.contains("gluten") })
}

@Test func prefersHigherProteinWhenGapIsBig() {
    let s = MealSuggester.suggest(req(.dinner, .home, kcal: 900, protein: 80), limit: 3)
    #expect(s.first!.idea.nutrition.proteinG >= 40)
}

@Test func doesNotSuggestHugeMealsWhenFewCaloriesRemain() {
    let s = MealSuggester.suggest(req(.dinner, .home, kcal: 450, protein: 40), limit: 3)
    #expect(s.allSatisfy { $0.idea.nutrition.kcal <= 650 })
    #expect(s.first!.idea.nutrition.kcal < 600)
}

@Test func countingOffIgnoresCalories() {
    var r = req(.dinner, .home, kcal: 100, protein: 60); r.counting = false
    #expect(!MealSuggester.suggest(r).isEmpty)
}

@Test func avoidsRepeatingTodaysMainIngredient() {
    let base = MealSuggester.suggest(req(.dinner, .home), limit: 20)
    let again = MealSuggester.suggest(req(.dinner, .home, eaten: ["chicken sandwich"]), limit: 20)
    let rank = { (l: [MealSuggestion]) in l.firstIndex { $0.idea.ingredients.first == "chicken" } ?? 99 }
    #expect(rank(again) >= rank(base))
}

@Test func catalogSanity() {
    #expect(Set(MealSuggester.catalog.map(\.name)).count == MealSuggester.catalog.count)
    for m in MealSuggester.catalog {
        let n = m.nutrition
        // Macro calories should roughly match the stated calories.
        let calc = n.proteinG * 4 + n.carbsG * 4 + n.fatG * 9
        #expect(abs(calc - n.kcal) / n.kcal < 0.15, "\(m.name) macros do not add up")
        #expect(!m.vegan || m.vegetarian)
    }
}

@Test func everySlotAndContextHasIdeas() {
    for slot in MealType.allCases {
        for ctx in EatingContext.allCases {
            let found = MealSuggester.suggest(req(slot, ctx, kcal: nil, protein: 40), limit: 1)
            #expect(!found.isEmpty, "no idea for \(slot) in \(ctx)")
        }
    }
}

@Test func questionRouting() {
    #expect(MealSuggester.wantsIdeas("What should I eat for dinner?"))
    #expect(MealSuggester.wantsIdeas("Suggest a high-protein cafeteria meal"))
    #expect(!MealSuggester.wantsIdeas("How much protein have I had today?"))
    #expect(MealSuggester.slot(in: "what should I eat for dinner", fallback: .lunch) == .dinner)
    #expect(MealSuggester.context(in: "suggest a cafeteria meal", fallback: .home) == .cafeteria)
}

@Test func describeIsHonestAboutEstimates() {
    let s = MealSuggester.suggest(req())
    let t = MealSuggester.describe(s, remainingKcal: 800, remainingProteinG: 60)
    #expect(t.contains("not verified") && t.contains("800"))
    #expect(MealSuggester.describe([], remainingKcal: nil, remainingProteinG: 0).contains("could not find"))
}
