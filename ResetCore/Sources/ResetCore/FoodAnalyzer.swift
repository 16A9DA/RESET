import Foundation

public struct FoodAnalysis: Sendable {
    public var items: [FoodItem]
    public var mealType: MealType?
    public var uncertainties: [String]
    /// True when every item is database backed or the model was confident. Used for opt-in quick logging.
    public var canAutoSave: Bool
}

public enum FoodAnalyzer {
    public static let system = """
    You turn a description or photo of food into structured data for a nutrition log. Reply with ONE JSON object and nothing else.
    Schema: {"items":[{"name":string,"brand":string|null,"grams":number,"preparation":string|null,"consumed":boolean,\
    "confidence":"low"|"medium"|"high","searchQuery":string,"estimate":{"kcal":number,"proteinG":number,"carbsG":number,"fatG":number,"caffeineMg":number|null}}],\
    "mealType":"breakfast"|"lunch"|"dinner"|"snack"|null,"uncertainties":[string]}
    Rules:
    - One item per distinct food or drink. Grams is the edible weight, or millilitres for drinks. Use the amount the user states; otherwise estimate a typical portion and lower confidence.
    - consumed is false only if the user says they bought, were offered or saved something rather than ate it. Never assume purchases were eaten.
    - searchQuery is a short plain database phrase such as "chicken breast cooked".
    - estimate is your best guess for that many grams. It is only a fallback and is not verified. Use null for caffeineMg unless the item contains caffeine; for a branded energy drink give the label amount only if you are sure, otherwise null.
    - For cafeteria plates and photos, list oil, sauces and dressings you cannot see or quantify in uncertainties and use low or medium confidence.
    - Do not give health advice. Do not invent brands. If nothing edible is described, return {"items":[]}.
    """

    public static func analyze(text: String?, imageJPEG: Data?, provider: AIProvider, lookup: FoodLookup?, brandLookup: FoodLookup? = nil) async throws -> FoodAnalysis {
        var parts: [AIPart] = []
        if let imageJPEG { parts.append(.image(mime: "image/jpeg", base64: imageJPEG.base64EncodedString())) }
        let prompt: String
        switch (text?.isEmpty == false, imageJPEG != nil) {
        case (true, true): prompt = "Photo of the meal. The user says: \(text!)"
        case (true, false): prompt = text!
        default: prompt = "Identify the foods in this photo and estimate portions."
        }
        parts.append(.text(prompt))
        let reply = try await provider.complete(AIRequest(system: system, messages: [AIMessage(role: .user, parts: parts)], maxTokens: 1500))
        return try await finish(reply.text, lookup: lookup, brandLookup: brandLookup)
    }

    static func finish(_ replyText: String, lookup: FoodLookup?, brandLookup: FoodLookup? = nil) async throws -> FoodAnalysis {
        let meal = try FoodValidator.parse(replyText)
        let items = await FoodResolver.resolve(meal, lookup: lookup, brandLookup: brandLookup)
        let unc = meal.uncertainties ?? []
        let sure = items.allSatisfy { $0.confidence >= .medium && ($0.verified || $0.nutrition.kcal > 0) }
        return FoodAnalysis(items: items, mealType: meal.mealType.flatMap { MealType(rawValue: $0) },
                            uncertainties: unc, canAutoSave: sure && unc.isEmpty && items.allSatisfy(\.consumed))
    }
}
