import Foundation

/// One short next-meal suggestion from today's macros. Thresholds come from published guidance:
/// - Protein per meal about 0.4 g/kg, over at least four meals (Schoenfeld and Aragon 2018, JISSN).
/// - Daily protein 1.4 to 2.0 g/kg for most active people, more in a deficit (ISSN position stand 2017; Morton 2018, BJSM).
/// - Fat 20 to 35% and carbohydrate 45 to 65% of energy, fibre 14 g per 1000 kcal (Dietary Guidelines, Dietary Reference Intakes).
/// Estimates only. Nothing here is medical advice, and it never tells anyone to skip a meal.
public struct MacroAdvice: Equatable, Sendable {
    public var headline: String
    public var detail: String
    public var kcalLeft: Double?
    public var proteinLeftG: Double
    public var nextMealProteinG: Double
}

public enum MacroCoach {
    public static let proteinFoods = "chicken, eggs, Greek yogurt, fish, tofu or lean beef"

    public static func advise(consumed c: Nutrition, targetKcal: Double?, targetProteinG: Double, weightKg: Double,
                              hour: Int, mealsLogged: Int) -> MacroAdvice? {
        guard mealsLogged > 0, c.kcal > 0 else { return nil }
        let proteinLeft = max(0, targetProteinG - c.proteinG)
        let perMeal = min(max(0.4 * weightKg, 20), 50)
        let next = min(perMeal, max(proteinLeft, 0)).rounded()
        let kcalLeft = targetKcal.map { $0 - c.kcal }
        func make(_ h: String, _ d: String) -> MacroAdvice {
            MacroAdvice(headline: h, detail: d, kcalLeft: kcalLeft, proteinLeftG: proteinLeft, nextMealProteinG: next)
        }

        let enough = c.kcal >= 400
        let carbShare = c.carbsG * 4 / c.kcal, proteinShare = c.proteinG * 4 / c.kcal, fatShare = c.fatG * 9 / c.kcal

        if enough, carbShare > 0.6, proteinShare < 0.2, proteinLeft >= 20 {
            return make("Carb heavy so far. Add protein next.",
                        "Aim for about \(Int(max(next, 20))) g protein at your next meal: \(proteinFoods).")
        }
        if enough, fatShare > 0.4 {
            return make("Fat is high so far. Go lean next.",
                        "Pick a lean protein with vegetables or fruit, about \(Int(max(next, 20))) g protein.")
        }
        if let k = kcalLeft, k < 0 {
            return make("Past your guide today. Keep the next meal light.",
                        "Mostly protein and vegetables. Do not skip meals. One day does not change your trend.")
        }
        if proteinLeft >= 25, hour >= 15 {
            return make("Protein is behind. About \(Int(proteinLeft.rounded())) g to go.",
                        "Spread it over your next meals, about \(Int(max(next, 20))) g each: \(proteinFoods).")
        }
        if let f = c.fiberG, c.kcal >= 1000, f / c.kcal * 1000 < 10 {
            return make("Low fibre today.", "Add vegetables, beans, lentils or whole grains to your next meal.")
        }
        let left = [kcalLeft.map { "\(Int($0.rounded())) kcal" }, proteinLeft >= 5 ? "\(Int(proteinLeft.rounded())) g protein" : nil]
            .compactMap { $0 }.joined(separator: " and ")
        return make("On track.", left.isEmpty ? "You have hit today's targets." : "Left today: \(left).")
    }
}
