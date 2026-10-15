import Foundation

public enum EatingContext: String, Codable, Sendable, CaseIterable {
    case cafeteria, home, quick
    public var title: String {
        switch self {
        case .cafeteria: "Cafeteria"
        case .home: "Cooking at home"
        case .quick: "Quick, no cooking"
        }
    }
}

public struct MealIdea: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var contexts: Set<EatingContext>
    public var slots: Set<MealType>
    /// Words used to filter allergies and diets, for example "pork", "egg", "dairy", "gluten", "fish", "nuts".
    public var tags: Set<String>
    public var ingredients: [String]
    public var prepMinutes: Int
    public var nutrition: Nutrition
    public var tip: String
    public var vegetarian: Bool
    public var vegan: Bool
}

public struct MealSuggestion: Equatable, Sendable, Identifiable {
    public var id: String { idea.id }
    public var idea: MealIdea
    public var reason: String
}

public struct SuggestionRequest: Sendable {
    public var slot: MealType
    public var context: EatingContext
    public var remainingKcal: Double?
    public var remainingProteinG: Double
    public var mealsLeft: Int
    public var minutes: Int
    public var preferences: [String]
    public var allergies: [String]
    public var eatenToday: [String]
    public var counting: Bool

    public init(slot: MealType, context: EatingContext, remainingKcal: Double?, remainingProteinG: Double, mealsLeft: Int = 1,
                minutes: Int = 30, preferences: [String] = [], allergies: [String] = [], eatenToday: [String] = [], counting: Bool = true) {
        self.slot = slot; self.context = context; self.remainingKcal = remainingKcal; self.remainingProteinG = remainingProteinG
        self.mealsLeft = max(1, mealsLeft); self.minutes = minutes; self.preferences = preferences; self.allergies = allergies
        self.eatenToday = eatenToday; self.counting = counting
    }
}

public enum MealSuggester {
    public static let disclaimer = "Ideas with typical portion estimates, not verified nutrition. Adjust to what is actually on your plate. Check ingredients yourself if you have an allergy."

    private static func idea(_ name: String, _ ctx: [EatingContext], _ slots: [MealType], tags: [String] = [], ing: [String], prep: Int = 0,
                             kcal: Double, p: Double, c: Double, f: Double, veg: Bool = false, vegan: Bool = false, tip: String) -> MealIdea {
        MealIdea(name: name, contexts: Set(ctx), slots: Set(slots), tags: Set(tags), ingredients: ing, prepMinutes: prep,
                 nutrition: Nutrition(kcal: kcal, proteinG: p, carbsG: c, fatG: f), tip: tip, vegetarian: veg || vegan, vegan: vegan)
    }

    private static let main: [MealType] = [.lunch, .dinner]

    public static let catalog: [MealIdea] = [
        idea("Grilled chicken, rice and salad", [.cafeteria], main, ing: ["chicken", "rice", "lettuce", "tomato", "cucumber"],
             kcal: 620, p: 45, c: 70, f: 14, tip: "Ask for dressing on the side. A palm of chicken, a fist of rice, the rest salad or veg."),
        idea("Baked fish, potatoes and vegetables", [.cafeteria], main, tags: ["fish"], ing: ["fish", "potato", "vegetables"],
             kcal: 580, p: 38, c: 60, f: 18, tip: "Skip creamy sauces. Extra vegetables keep it filling."),
        idea("Lentil or bean stew with bread", [.cafeteria, .home], main, tags: ["gluten"], ing: ["lentils", "beans", "tomato", "bread"],
             kcal: 520, p: 26, c: 80, f: 9, vegan: true, tip: "Cheap, high in fibre and filling. Add a yogurt or egg if you want more protein."),
        idea("Turkey or chicken sandwich with salad", [.cafeteria, .quick], [.lunch, .dinner, .snack], tags: ["gluten"], ing: ["turkey", "chicken", "bread", "lettuce"],
             kcal: 480, p: 34, c: 48, f: 14, tip: "Wholemeal bread, mustard instead of mayo, add a side fruit."),
        idea("Beef or lean meat with potatoes and veg", [.cafeteria], main, ing: ["beef", "potato", "vegetables"],
             kcal: 700, p: 42, c: 60, f: 28, tip: "Take the smaller meat portion if it looks large, double the vegetables."),
        idea("Egg omelette with vegetables and toast", [.home, .cafeteria], [.breakfast, .lunch, .dinner], tags: ["egg", "gluten"], ing: ["eggs", "peppers", "onion", "bread"],
             prep: 12, kcal: 450, p: 28, c: 28, f: 24, veg: true, tip: "Three eggs plus vegetables. Cook in a small amount of oil."),
        idea("Chicken and vegetable stir fry with rice", [.home], main, ing: ["chicken", "rice", "peppers", "broccoli", "soy sauce"],
             prep: 25, kcal: 600, p: 44, c: 65, f: 16, tip: "Go easy on oil and sauce. Frozen vegetables are fine."),
        idea("Tuna pasta with tomato sauce", [.home], main, tags: ["fish", "gluten"], ing: ["tuna", "pasta", "tomato"],
             prep: 20, kcal: 640, p: 42, c: 82, f: 12, tip: "Tinned tuna in water. Add a handful of spinach."),
        idea("Oven chicken thighs with potatoes and veg", [.home], main, ing: ["chicken", "potato", "vegetables"],
             prep: 40, kcal: 640, p: 40, c: 52, f: 26, tip: "Skinless thighs cut the fat. Batch cook for two days."),
        idea("Tofu and vegetable curry with rice", [.home], main, tags: ["soy"], ing: ["tofu", "rice", "coconut milk", "vegetables"],
             prep: 30, kcal: 610, p: 26, c: 78, f: 20, vegan: true, tip: "Light coconut milk reduces the calories."),
        idea("Beef or turkey mince chilli with rice", [.home], main, ing: ["beef", "turkey", "beans", "tomato", "rice"],
             prep: 35, kcal: 650, p: 44, c: 72, f: 18, tip: "Makes several portions. Freezes well."),
        idea("Greek yogurt, oats and berries", [.home, .quick, .cafeteria], [.breakfast, .snack], tags: ["dairy", "gluten"], ing: ["yogurt", "oats", "berries"],
             prep: 3, kcal: 380, p: 28, c: 48, f: 7, veg: true, tip: "Plain high protein yogurt, then add fruit and oats yourself."),
        idea("Cottage cheese with fruit and crispbread", [.quick], [.breakfast, .snack, .lunch], tags: ["dairy", "gluten"], ing: ["cottage cheese", "fruit", "crispbread"],
             prep: 3, kcal: 330, p: 30, c: 36, f: 6, veg: true, tip: "Good protein for few calories."),
        idea("Skyr or quark with a banana", [.quick], [.snack, .breakfast], tags: ["dairy"], ing: ["skyr", "banana"],
             prep: 1, kcal: 250, p: 25, c: 33, f: 1, veg: true, tip: "A fast snack that is mostly protein."),
        idea("Tinned tuna or chicken wrap", [.quick, .home], [.lunch, .dinner, .snack], tags: ["fish", "gluten"], ing: ["tuna", "chicken", "wrap", "salad"],
             prep: 6, kcal: 450, p: 36, c: 42, f: 14, tip: "Use mustard or yogurt instead of mayo."),
        idea("Hummus, vegetables and wholemeal pitta", [.quick], [.snack, .lunch], tags: ["gluten", "sesame"], ing: ["chickpeas", "hummus", "pitta", "carrot"],
             prep: 4, kcal: 380, p: 15, c: 52, f: 13, vegan: true, tip: "Add a boiled egg or cheese for more protein if you eat them."),
        idea("Boiled eggs, fruit and a handful of nuts", [.quick], [.snack, .breakfast], tags: ["egg", "nuts", "peanuts"], ing: ["eggs", "fruit", "almonds"],
             prep: 10, kcal: 330, p: 20, c: 22, f: 18, veg: true, tip: "Boil a batch at the start of the week."),
        idea("Protein shake with milk and a banana", [.quick], [.snack, .breakfast], tags: ["dairy"], ing: ["whey protein", "milk", "banana"],
             prep: 2, kcal: 320, p: 32, c: 38, f: 5, veg: true, tip: "Handy after training or when you are short on time. Real food first when you can."),
        idea("Cold chicken, rice and vegetables (leftovers)", [.quick, .home], main, ing: ["chicken", "rice", "vegetables"],
             prep: 3, kcal: 560, p: 42, c: 62, f: 12, tip: "Cook double portions, box up the rest."),
        idea("Porridge with milk, berries and seeds", [.home], [.breakfast], tags: ["dairy", "gluten"], ing: ["oats", "milk", "berries", "seeds"],
             prep: 8, kcal: 400, p: 16, c: 62, f: 10, veg: true, tip: "Stir in a scoop of protein powder or serve with yogurt to lift protein."),
        idea("Salmon, couscous and green vegetables", [.home], [.dinner], tags: ["fish", "gluten"], ing: ["salmon", "couscous", "green beans"],
             prep: 22, kcal: 640, p: 40, c: 55, f: 26, tip: "Oily fish is a good choice once or twice a week."),
        idea("Vegetable soup with an egg and bread", [.home, .cafeteria], [.lunch, .dinner], tags: ["egg", "gluten"], ing: ["vegetables", "egg", "bread"],
             prep: 15, kcal: 360, p: 18, c: 40, f: 12, veg: true, tip: "Light option when you are not very hungry."),
    ]

    // MARK: Filtering

    private static let dietRules: [(keys: [String], excludes: (MealIdea) -> Bool)] = [
        (["vegan"], { !$0.vegan }),
        (["vegetarian"], { !$0.vegetarian }),
        (["no pork", "pork free", "halal"], { $0.tags.contains("pork") }),
        (["gluten"], { $0.tags.contains("gluten") }),
        (["dairy", "lactose"], { $0.tags.contains("dairy") }),
        (["fish", "pescatarian"], { _ in false }),
        (["no fish"], { $0.tags.contains("fish") }),
        (["no egg", "egg free"], { $0.tags.contains("egg") }),
    ]

    /// Conservative: a free text allergy word that appears anywhere in the name, tags or ingredients removes the meal.
    /// "nut" also catches peanuts and almonds. This is a convenience filter, not allergy safety.
    static func allergyConflict(_ i: MealIdea, allergies: [String]) -> Bool {
        let hay = ([i.name.lowercased()] + i.tags + i.ingredients.map { $0.lowercased() }).joined(separator: " ")
        return allergies.contains { a in
            let w = a.lowercased().trimmingCharacters(in: .whitespaces)
            guard w.count >= 3 else { return false }
            let stem = w.hasSuffix("s") ? String(w.dropLast()) : w
            return hay.contains(stem)
        }
    }

    static func excludedByDiet(_ i: MealIdea, prefs: [String]) -> Bool {
        let p = prefs.map { $0.lowercased() }
        for rule in dietRules where rule.keys.contains(where: { k in p.contains { $0.contains(k) } }) {
            if rule.excludes(i) { return true }
        }
        // "no pork" style with a trailing word, for example "no pork" in any preference
        return false
    }

    // MARK: Ranking

    public static func suggest(_ r: SuggestionRequest, limit: Int = 3) -> [MealSuggestion] {
        let eaten = r.eatenToday.joined(separator: " ").lowercased()
        let perMealKcal: Double? = r.counting ? r.remainingKcal.map { max(250, $0 / Double(r.mealsLeft)) } : nil
        let perMealProtein = r.remainingProteinG / Double(r.mealsLeft)

        let scored: [(MealIdea, Double, [String])] = catalog.compactMap { i in
            guard i.contexts.contains(r.context), i.slots.contains(r.slot), i.prepMinutes <= r.minutes else { return nil }
            guard !allergyConflict(i, allergies: r.allergies), !excludedByDiet(i, prefs: r.preferences) else { return nil }

            var score = 0.0
            var why: [String] = []
            let n = i.nutrition
            if let target = perMealKcal {
                let over = (n.kcal - target) / target
                if over > 0.25 { score -= 40 * over } else if abs(over) <= 0.2 { score += 20; why.append("fits about \(Int(target.rounded())) kcal for this meal") }
                else { score += 5 }
                if let rem = r.remainingKcal, n.kcal > rem * 1.15 { score -= 30 }
            }
            if perMealProtein > 10 {
                let ratio = n.proteinG / perMealProtein
                score += min(ratio, 1.3) * 25
                if ratio >= 0.8 { why.append("\(Int(n.proteinG)) g protein helps close your gap") }
            } else { why.append("protein is already well covered") }
            score += (n.proteinG / max(n.kcal, 1)) * 100 // protein density
            // Variety: avoid repeating the same main ingredient eaten today.
            if let main = i.ingredients.first, eaten.contains(main) { score -= 15; why.append("different from the \(main) you already had") }
            else if let main = i.ingredients.first, !eaten.isEmpty { why.append("adds variety beyond \(main)") }
            if i.prepMinutes == 0 { why.append("no prep") } else if i.prepMinutes <= 10 { why.append("ready in \(i.prepMinutes) min") }
            return (i, score, why)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { MealSuggestion(idea: $0.0, reason: ($0.2.prefix(2)).joined(separator: ", ").capitalizedFirst) }
    }

    // MARK: Questions

    public static func wantsIdeas(_ question: String) -> Bool {
        let q = question.lowercased()
        let asks = ["what should i eat", "what to eat", "suggest", "idea", "recommend", "what can i eat", "meal for", "something to eat", "cafeteria meal"]
        let food = ["eat", "meal", "dinner", "lunch", "breakfast", "snack", "cafeteria"]
        return asks.contains { q.contains($0) } && food.contains { q.contains($0) }
    }

    public static func slot(in question: String, fallback: MealType) -> MealType {
        let q = question.lowercased()
        for (w, t) in [("breakfast", MealType.breakfast), ("lunch", .lunch), ("dinner", .dinner), ("supper", .dinner), ("snack", .snack)] where q.contains(w) { return t }
        return fallback
    }

    public static func context(in question: String, fallback: EatingContext) -> EatingContext {
        let q = question.lowercased()
        if q.contains("cafeteria") || q.contains("canteen") || q.contains("uni ") { return .cafeteria }
        if q.contains("quick") || q.contains("no cook") || q.contains("fast") { return .quick }
        if q.contains("cook") || q.contains("at home") { return .home }
        return fallback
    }

    public static func describe(_ s: [MealSuggestion], remainingKcal: Double?, remainingProteinG: Double) -> String {
        guard !s.isEmpty else {
            return "I could not find a matching idea with your allergy, diet and time settings. Try another setting or ask me with AI turned on."
        }
        var head = "Ideas"
        if let k = remainingKcal { head += " (about \(Int(k.rounded())) kcal and \(Int(remainingProteinG.rounded())) g protein left today)" }
        let lines = s.enumerated().map { i, m in
            let n = m.idea.nutrition
            return "\(i + 1). \(m.idea.name), about \(Int(n.kcal)) kcal and \(Int(n.proteinG)) g protein. \(m.reason). \(m.idea.tip)"
        }
        return head + ":\n" + lines.joined(separator: "\n") + "\n" + disclaimer
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
