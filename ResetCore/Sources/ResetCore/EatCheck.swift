import Foundation

/// Answer to "Can I eat this?". Only an allergy match says no. Calories and caffeine say "maybe", never a scolding.
public struct EatVerdict: Equatable, Sendable {
    public enum Level: String, Sendable { case yes, maybe, no }
    public var level: Level
    public var reasons: [String]
    public var kcal: Double
    public var proteinG: Double
}

public enum EatCheck {
    public static let allergyCaveat = "I cannot see every ingredient. Check the label if you have an allergy."

    public static func verdict(items: [FoodItem], remainingKcal: Double?, caffeineTodayMg: Double, hoursToBed: Double?,
                               allergies: [String], proteinLeftG: Double? = nil) -> EatVerdict {
        let total = items.reduce(Nutrition.zero) { $0 + $1.nutrition }
        var level = EatVerdict.Level.yes
        var reasons: [String] = []

        let text = items.map { "\($0.name) \($0.brand ?? "") \($0.preparation ?? "")" }.joined(separator: " ").lowercased()
        let hits = allergies.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && text.contains($0) }
        if !hits.isEmpty {
            level = .no
            reasons.append("Contains \(hits.joined(separator: ", ")), which you listed as an allergy.")
        }
        if let r = remainingKcal, total.kcal > max(r, 0) + 1 {
            if level == .yes { level = .maybe }
            reasons.append(r <= 0 ? "You are already at your calorie guide for today." : "About \(Int(total.kcal.rounded())) kcal, you have about \(Int(r.rounded())) left.")
        }
        if let mg = total.caffeineMg, mg > 0 {
            if let h = hoursToBed, h < 8 {
                if level == .yes { level = .maybe }
                reasons.append("Has about \(Int(mg.rounded())) mg caffeine and bedtime is \(Int(h.rounded())) h away. It may affect sleep.")
            } else if caffeineTodayMg + mg > 400 {
                if level == .yes { level = .maybe }
                reasons.append("That would take caffeine past the commonly cited 400 mg a day.")
            }
        }
        // Mostly carbs while protein is behind: still fine to eat, but pair it with protein.
        if level != .no, total.kcal >= 150, total.carbsG * 4 / total.kcal > 0.6, total.proteinG < 10, (proteinLeftG ?? 0) >= 25 {
            reasons.append("Mostly carbs and you are behind on protein. Pair it with \(MacroCoach.proteinFoods).")
        }
        if reasons.isEmpty {
            reasons.append(total.proteinG >= 20 ? "Fits your day, and it has about \(Int(total.proteinG.rounded())) g protein." : "Fits your day.")
        }
        return EatVerdict(level: level, reasons: reasons, kcal: total.kcal, proteinG: total.proteinG)
    }
}
