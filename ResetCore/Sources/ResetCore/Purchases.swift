import Foundation

public enum PurchaseCategory: String, Codable, Sendable {
    case food, drink, groceries, notFood, unknown
    /// Worth showing as a possible meal. Everything else is hidden unless the user asks.
    public var maybeEaten: Bool { self == .food || self == .drink || self == .groceries || self == .unknown }
}

/// One purchase line, reduced to what the food log needs. Prices, totals, dates and card numbers are removed on
/// purpose: the app never keeps financial amounts.
public struct PurchaseCandidate: Equatable, Sendable {
    public var text: String
    public var category: PurchaseCategory
    public init(text: String, category: PurchaseCategory) { self.text = text; self.category = category }
}

public struct PurchaseRule: Codable, Equatable, Sendable {
    public var keyword: String
    /// Text placed in the food description box. A rule only prefills. It never logs anything.
    public var prefill: String
    public init(keyword: String, prefill: String) { self.keyword = keyword; self.prefill = prefill }
}

public enum PurchaseParser {
    private static let skipWords = ["total", "subtotal", "sub total", "tax", "vat", "tva", "change", "cash", "balance", "thank you", "receipt",
                                    "invoice", "tel", "www", "http", "cashier", "terminal", "approved", "authorisation", "authorization",
                                    "visa", "mastercard", "maestro"]

    private static let drinkWords = ["energy", "monster", "red bull", "hell ", "coffee", "cappuccino", "latte", "espresso", "tea", "cola", "juice",
                                     "water", "beer", "smoothie", "milkshake", "soda", "drink"]
    private static let foodWords = ["cafe", "café", "coffee", "restaurant", "pizza", "burger", "kebab", "shawarma", "bakery", "sandwich", "sushi", "grill",
                                    "bistro", "canteen", "cafeteria", "mcdonald", "kfc", "subway", "starbucks", "burger king", "dominos", "domino",
                                    "wrap", "salad", "chicken", "rice", "pasta", "bread", "waffle", "croissant", "cake", "snack", "lunch", "dinner",
                                    "breakfast", "food", "eat", "kitchen", "deli", "noodle", "falafel", "taco", "fries", "yogurt", "yoghurt", "eggs"]
    private static let groceryWords = ["supermarket", "market", "grocery", "lidl", "aldi", "tesco", "carrefour", "kaufland", "penny", "auchan", "spar",
                                       "mega image", "profi", "rewe", "edeka", "migros", "coop", "walmart", "whole foods", "trader joe", "sainsbury"]
    private static let notFoodWords = ["uber", "taxi", "bolt", "parking", "netflix", "spotify", "youtube", "rent", "insurance", "atm", "transfer",
                                       "salary", "refund", "zara", "h&m", "ikea", "pharmacy", "clinic", "hospital", "gym membership", "subscription",
                                       "mobile", "vodafone", "orange", "telekom", "electric", "gas bill", "fuel", "petrol", "tuition", "book",
                                       "cinema", "hotel", "airline", "ticket", "amazon", "ebay", "steam", "playstation", "app store", "google play"]

    /// What is left of a card payment line on a receipt once its numbers are gone. Not a purchase.
    private static let leftovers: Set<String> = ["card", "cash", "payment", "pos", "debit", "credit", "visa", "contactless", "online", "purchase", "ref", "reference"]

    // Money, dates, times and long digit runs (card and reference numbers).
    private static let noise: [NSRegularExpression] = [
        #"[€$£]\s?\d+(?:[.,]\d{1,2})?"#,
        #"\d+(?:[.,]\d{1,2})?\s?(?:eur|usd|gbp|ron|lei|pln|chf|czk|huf|sek|nok|dkk)\b"#,
        #"\b\d+[.,]\d{2}\b"#,
        #"\b\d{1,2}[./-]\d{1,2}(?:[./-]\d{2,4})?\b"#,
        #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#,
        #"[*xX]{2,}\s?\d{2,4}"#,
        #"\b\d{4,}\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func clean(_ line: String) -> String {
        var s = line
        for re in noise { s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ") }
        let parts = s.split(whereSeparator: { " \t,;|*#:".contains($0) }).map(String.init)
        return parts.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -_.()"))
    }

    public static func categorize(_ text: String) -> PurchaseCategory {
        let t = " " + text.lowercased() + " "
        func any(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if any(notFoodWords) && !any(drinkWords) && !any(foodWords) { return .notFood }
        if any(groceryWords) { return .groceries }
        if any(drinkWords) && !any(["restaurant", "grill", "bistro", "pizza", "burger"]) { return .drink }
        if any(foodWords) { return .food }
        return .unknown
    }

    /// Parses pasted receipt text. Lines with no letters, totals and headers are dropped.
    public static func parse(_ text: String, limit: Int = 60) -> [PurchaseCandidate] {
        var seen = Set<String>()
        var out: [PurchaseCandidate] = []
        for raw in text.components(separatedBy: .newlines).prefix(500) {
            let lower = raw.lowercased()
            if skipWords.contains(where: { lower.contains($0) }) { continue }
            let c = clean(raw)
            guard c.count >= 2, c.count <= 80, c.contains(where: \.isLetter), !leftovers.contains(c.lowercased()) else { continue }
            let key = Duplicates.normalize(c)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(PurchaseCandidate(text: c, category: categorize(c)))
            if out.count >= limit { break }
        }
        return out
    }

    /// Candidates worth asking about. Obvious non-food is hidden.
    public static func relevant(_ c: [PurchaseCandidate]) -> [PurchaseCandidate] { c.filter { $0.category.maybeEaten } }

    /// Drops candidates already waiting or recently handled, using the same normalisation as the food duplicate guard.
    public static func removingKnown(_ c: [PurchaseCandidate], known: [String]) -> [PurchaseCandidate] {
        let k = Set(known.map(Duplicates.normalize))
        return c.filter { !k.contains(Duplicates.normalize($0.text)) }
    }
}

public enum PurchaseRules {
    public static let maxRules = 30

    /// The text to prefill in the food box. The first rule whose keyword appears wins, otherwise the cleaned purchase text.
    public static func prefill(for candidateText: String, rules: [PurchaseRule]) -> String {
        let t = candidateText.lowercased()
        for r in rules {
            let k = r.keyword.trimmingCharacters(in: .whitespaces).lowercased()
            if k.count >= 2, t.contains(k) { return r.prefill }
        }
        return candidateText
    }

    public static func isValid(_ r: PurchaseRule) -> Bool {
        r.keyword.trimmingCharacters(in: .whitespaces).count >= 2 && !r.prefill.trimmingCharacters(in: .whitespaces).isEmpty
            && r.keyword.count <= 40 && r.prefill.count <= 200
    }
}

public enum ReceiptAnalyzer {
    public static let system = """
    You read a photo of a shopping or restaurant receipt and list only the FOOD and DRINK items on it. Reply with ONE JSON object and nothing else.
    Schema: {"items":[{"name":string,"brand":string|null,"grams":number,"confidence":"low"|"medium"|"high","searchQuery":string,"estimate":{"kcal":number,"proteinG":number,"carbsG":number,"fatG":number,"caffeineMg":number|null}}],"uncertainties":[string]}
    Rules:
    - Ignore prices, totals, taxes, dates, store details, card numbers and anything that is not food or drink. Never output money amounts or personal details.
    - Grams is the pack or serving size printed on the receipt if shown, otherwise a typical size with low confidence.
    - This is what was BOUGHT, not what was eaten. Do not decide what the user ate. Do not add a "consumed" field.
    - estimate is only a fallback for that many grams. caffeineMg only if the item contains caffeine and you are sure.
    - If the text is unreadable or has no food, return {"items":[],"uncertainties":["unreadable"]}.
    """

    /// Reads a receipt photo. Every item comes back as NOT consumed, so nothing can reach the food totals without the user.
    public static func analyze(imageJPEG: Data, provider: AIProvider, lookup: FoodLookup?, brandLookup: FoodLookup? = nil) async throws -> FoodAnalysis {
        let parts: [AIPart] = [.image(mime: "image/jpeg", base64: imageJPEG.base64EncodedString()),
                               .text("List the food and drink items on this receipt.")]
        let reply = try await provider.complete(AIRequest(system: system, messages: [AIMessage(role: .user, parts: parts)], maxTokens: 1500))
        return try await forceNotConsumed(reply.text, lookup: lookup, brandLookup: brandLookup)
    }

    static func forceNotConsumed(_ text: String, lookup: FoodLookup?, brandLookup: FoodLookup?) async throws -> FoodAnalysis {
        var meal = try FoodValidator.parse(text)
        meal.items = meal.items.map { var i = $0; i.consumed = false; return i }
        var items = await FoodResolver.resolve(meal, lookup: lookup, brandLookup: brandLookup)
        items = items.map { var i = $0; i.consumed = false; return i }
        return FoodAnalysis(items: items, mealType: nil, uncertainties: meal.uncertainties ?? [], canAutoSave: false)
    }
}
