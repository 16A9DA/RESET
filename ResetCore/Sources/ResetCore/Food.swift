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

/// Models sometimes send numbers as strings ("150", "150 g"). One odd field must not sink a whole multi dish reply.
private extension KeyedDecodingContainer {
    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        guard let s = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let digits = s.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

extension ParsedItem {
    enum CodingKeys: String, CodingKey { case name, brand, grams, preparation, consumed, confidence, searchQuery, estimate }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        brand = try? c.decodeIfPresent(String.self, forKey: .brand)
        grams = c.flexDouble(.grams) ?? 0
        preparation = try? c.decodeIfPresent(String.self, forKey: .preparation)
        consumed = try? c.decodeIfPresent(Bool.self, forKey: .consumed)
        confidence = try? c.decodeIfPresent(String.self, forKey: .confidence)
        searchQuery = try? c.decodeIfPresent(String.self, forKey: .searchQuery)
        estimate = try? c.decodeIfPresent(ParsedEstimate.self, forKey: .estimate)
    }
}

extension ParsedEstimate {
    enum CodingKeys: String, CodingKey { case kcal, proteinG, carbsG, fatG, caffeineMg }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kcal = c.flexDouble(.kcal); proteinG = c.flexDouble(.proteinG); carbsG = c.flexDouble(.carbsG)
        fatG = c.flexDouble(.fatG); caffeineMg = c.flexDouble(.caffeineMg)
    }
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

    public init(items: [ParsedItem], mealType: String? = nil, uncertainties: [String]? = nil) {
        self.items = items; self.mealType = mealType; self.uncertainties = uncertainties
    }

    enum CodingKeys: String, CodingKey { case items, mealType, uncertainties }
    private struct Lossy: Decodable {
        let item: ParsedItem?
        init(from d: Decoder) { item = try? ParsedItem(from: d) }
    }

    /// A bad dish is skipped, the others still come through.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        items = try c.decode([Lossy].self, forKey: .items).compactMap(\.item)
        mealType = try? c.decodeIfPresent(String.self, forKey: .mealType)
        uncertainties = try? c.decodeIfPresent([String].self, forKey: .uncertainties)
    }
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

    /// A reply cut off by the token limit has no closing brace. Keep the dishes that finished and close the JSON.
    static func salvageTruncated(_ text: String) -> Data? {
        guard let a = text.firstIndex(of: "{") else { return nil }
        let body = String(text[a...])
        var depth = 0, inString = false, escaped = false, lastItemEnd: String.Index?
        for i in body.indices {
            let ch = body[i]
            if inString { if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }; continue }
            switch ch {
            case "\"": inString = true
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                if depth == 2 { lastItemEnd = i }   // an item object closed inside {"items":[ ... ]}
            default: break
            }
        }
        guard let end = lastItemEnd else { return nil }
        return (String(body[...end]) + "]}").data(using: .utf8)
    }

    /// Decodes and sanitises. Never trusts numbers: clamps grams, drops impossible macros, caps item count.
    public static func parse(_ text: String) throws -> ParsedMeal {
        let decode = { (d: Data?) in d.flatMap { try? JSONDecoder().decode(ParsedMeal.self, from: $0) } }
        guard var meal = decode(extractJSON(text)) ?? decode(salvageTruncated(text)) else {
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
    public static func resolve(_ meal: ParsedMeal, lookup: FoodLookup?, brandLookup: FoodLookup? = nil) async -> [FoodItem] {
        // Dishes resolve in parallel so a six item plate costs one lookup round trip, not six. Order is kept.
        await withTaskGroup(of: (Int, FoodItem).self) { group in
            for (n, p) in meal.items.enumerated() {
                group.addTask { (n, await resolve(p, lookup: lookup, brandLookup: brandLookup)) }
            }
            var out: [(Int, FoodItem)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Branded items try the product database first (labels beat generic averages), then the generic one.
    public static func resolve(_ p: ParsedItem, lookup: FoodLookup?, brandLookup: FoodLookup? = nil) async -> FoodItem {
        if let brand = p.brand, !brand.isEmpty, let brandLookup,
           let hit = try? await brandLookup.search("\(brand) \(p.name)"), best(hit, for: p) != nil {
            return await resolve(p, lookup: StaticLookup(hit), brandLookup: nil)
        }
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

struct StaticLookup: FoodLookup {
    let results: [ReferenceFood]
    init(_ r: [ReferenceFood]) { results = r }
    func search(_ query: String) async throws -> [ReferenceFood] { results }
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
