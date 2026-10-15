import Foundation

/// One logged food. `verified` means the per-100 g values came from a database or label.
/// Portions are usually still estimates, which `confidence` reflects.
public struct FoodItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var brand: String?
    public var grams: Double
    public var preparation: String?
    public var nutrition: Nutrition
    public var dataSource: String
    public var verified: Bool
    public var confidence: Confidence
    public var consumed: Bool

    public init(id: UUID = UUID(), name: String, brand: String? = nil, grams: Double, preparation: String? = nil,
                nutrition: Nutrition, dataSource: String, verified: Bool, confidence: Confidence, consumed: Bool = true) {
        self.id = id; self.name = name; self.brand = brand; self.grams = grams; self.preparation = preparation
        self.nutrition = nutrition; self.dataSource = dataSource; self.verified = verified
        self.confidence = confidence; self.consumed = consumed
    }
}

/// What a language model is allowed to return for a food description or photo.
public struct ParsedItem: Codable, Sendable, Equatable {
    public var name: String
    public var brand: String?
    public var grams: Double
    public var preparation: String?
    /// False for things bought or mentioned but not eaten.
    public var consumed: Bool?
    public var confidence: String?
    /// Short database search phrase, for example "chicken breast cooked".
    public var searchQuery: String?
    /// The model's own guess for the stated grams. Used only when no database match exists.
    public var estimate: ParsedEstimate?
}

public struct ParsedEstimate: Codable, Sendable, Equatable {
    public var kcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var caffeineMg: Double?
}

public struct ParsedMeal: Codable, Sendable, Equatable {
    public var items: [ParsedItem]
    public var mealType: String?
    public var uncertainties: [String]?
}

public enum FoodValidationError: Error, Equatable, LocalizedError {
    case notJSON, noItems
    public var errorDescription: String? {
        switch self {
        case .notJSON: "The AI reply was not in the expected format."
        case .noItems: "No foods were recognised."
        }
    }
}

public enum FoodValidator {
    public static let maxItems = 25
    public static let maxGrams = 3000.0

    /// Models often wrap JSON in prose or code fences. Take the outermost object.
    public static func extractJSON(_ text: String) -> Data? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        return String(text[a...b]).data(using: .utf8)
    }

    /// Decodes and sanitises. Never trusts numbers: clamps grams, drops impossible macros, caps item count.
    public static func parse(_ text: String) throws -> ParsedMeal {
        guard let data = extractJSON(text), var meal = try? JSONDecoder().decode(ParsedMeal.self, from: data) else {
            throw FoodValidationError.notJSON
        }
        meal.items = meal.items.prefix(maxItems).compactMap(sanitize)
        guard !meal.items.isEmpty else { throw FoodValidationError.noItems }
        return meal
    }

    static func sanitize(_ i: ParsedItem) -> ParsedItem? {
        var i = i
        i.name = i.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !i.name.isEmpty, i.name.count <= 120 else { return nil }
        guard i.grams.isFinite, i.grams > 0 else { return nil }
        i.grams = min(i.grams, maxGrams)
        if let e = i.estimate {
            func ok(_ v: Double?, max: Double) -> Double? { (v?.isFinite == true && v! >= 0 && v! <= max) ? v : nil }
            var c = ParsedEstimate(kcal: ok(e.kcal, max: i.grams * 9.5), proteinG: ok(e.proteinG, max: i.grams),
                                   carbsG: ok(e.carbsG, max: i.grams), fatG: ok(e.fatG, max: i.grams),
                                   caffeineMg: ok(e.caffeineMg, max: 1000))
            // Macros cannot outweigh the food itself.
            if (c.proteinG ?? 0) + (c.carbsG ?? 0) + (c.fatG ?? 0) > i.grams { c.proteinG = nil; c.carbsG = nil; c.fatG = nil }
            i.estimate = c
        }
        return i
    }
}

public enum FoodResolver {
    /// Turns parsed items into stored items. Database values win. The model's numbers are a labelled fallback.
    /// Lookup failures (offline, rate limit) degrade to the fallback and never throw away the entry.
    public static func resolve(_ meal: ParsedMeal, lookup: FoodLookup?) async -> [FoodItem] {
        var out: [FoodItem] = []
        for p in meal.items {
            out.append(await resolve(p, lookup: lookup))
        }
        return out
    }

    public static func resolve(_ p: ParsedItem, lookup: FoodLookup?) async -> FoodItem {
        let baseConf = Confidence(rawValue: (p.confidence ?? "").lowercased()) ?? .medium
        let consumed = p.consumed ?? true

        if let lookup, let hit = try? await lookup.search(p.searchQuery ?? p.name), let ref = best(hit, for: p) {
            var n = ref.nutrition(forGrams: p.grams)
            // Caffeine is rarely in generic databases. Keep the model's figure only if the reference has none.
            if n.caffeineMg == nil, let c = p.estimate?.caffeineMg { n.caffeineMg = c }
            return FoodItem(name: p.name, brand: p.brand ?? ref.brand, grams: p.grams, preparation: p.preparation,
                            nutrition: n, dataSource: ref.source, verified: true, confidence: min(baseConf, .high),
                            consumed: consumed)
        }
        if let e = p.estimate, let kcal = e.kcal {
            let n = Nutrition(kcal: kcal, proteinG: e.proteinG ?? 0, carbsG: e.carbsG ?? 0, fatG: e.fatG ?? 0,
                              caffeineMg: e.caffeineMg)
            return FoodItem(name: p.name, brand: p.brand, grams: p.grams, preparation: p.preparation, nutrition: n,
                            dataSource: "AI estimate, not from a database", verified: false, confidence: min(baseConf, .medium),
                            consumed: consumed)
        }
        return FoodItem(name: p.name, brand: p.brand, grams: p.grams, preparation: p.preparation, nutrition: .zero,
                        dataSource: "No nutrition data found. Edit to add values.", verified: false, confidence: .low,
                        consumed: consumed)
    }

    /// First result whose name shares a word with the item. Order from the database is relevance.
    static func best(_ results: [ReferenceFood], for p: ParsedItem) -> ReferenceFood? {
        let words = Set(p.name.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 })
        return results.first { r in
            let rw = Set(r.name.lowercased().split { !$0.isLetter }.map(String.init))
            return !words.isDisjoint(with: rw)
        }
    }
}

public enum Duplicates {
    public static func normalize(_ s: String) -> String {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    /// Same text logged again within the window is probably an accidental double entry. The user is asked, not blocked.
    public static func isLikelyDuplicate(text: String, at: Date, existing: [(text: String, at: Date)],
                                         window: TimeInterval = 600) -> Bool {
        let n = normalize(text)
        guard !n.isEmpty else { return false }
        return existing.contains { normalize($0.text) == n && abs($0.at.timeIntervalSince(at)) <= window }
    }
}

public struct DayNutrition: Sendable, Equatable {
    public var total: Nutrition
    public var mealCount: Int
    public var estimatedItemCount: Int
}

public enum NutritionTotals {
    /// Sums consumed items only. Items bought but not eaten are never counted.
    public static func day(_ meals: [(at: Date, items: [FoodItem])], on day: Date, calendar: Calendar = .current) -> DayNutrition {
        let w = Day.interval(of: day, calendar: calendar)
        var total = Nutrition.zero, count = 0, est = 0
        for m in meals where w.contains(m.at) {
            count += 1
            for i in m.items where i.consumed {
                total = total + i.nutrition
                if !i.verified { est += 1 }
            }
        }
        return DayNutrition(total: total, mealCount: count, estimatedItemCount: est)
    }
}
