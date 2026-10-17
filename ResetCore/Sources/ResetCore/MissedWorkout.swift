import Foundation

/// What to do when today's workout cannot happen. Walking and a small food adjustment only. Never a crash cut.
public struct MissedWorkoutAdvice: Equatable, Sendable {
    public var walkMinutes: Int
    public var eatLessKcal: Int
    public var text: String
}

public enum MissedWorkout {
    /// Easy walk, about 3.5 MET: kcal per minute is 0.06 per kg of body weight.
    public static func walkKcalPerMinute(weightKg: Double) -> Double { 0.0612 * max(weightKg, 40) }

    public static func advice(consumedKcal: Double, targetKcal: Double?, weightKg: Double, mealsLogged: Int, steps: Int?) -> MissedWorkoutAdvice {
        let perMin = walkKcalPerMinute(weightKg: weightKg)
        func round5(_ v: Double) -> Int { max(5, Int((v / 5).rounded()) * 5) }

        guard let target = targetKcal, mealsLogged > 0 else {
            let low = (steps ?? 0) < 6000
            return MissedWorkoutAdvice(walkMinutes: low ? 30 : 20, eatLessKcal: 0,
                                       text: "Nothing logged to compare. A \(low ? 30 : 20) minute walk keeps the day active. Eat normally.")
        }
        let over = consumedKcal - target
        if over <= 0 {
            return MissedWorkoutAdvice(walkMinutes: 15, eatLessKcal: 0,
                                       text: "You are \(Int((-over).rounded())) kcal under your guide, so skipping is fine. A 15 minute walk is enough.")
        }
        let walkAll = over / perMin
        if walkAll <= 60 {
            return MissedWorkoutAdvice(walkMinutes: round5(walkAll), eatLessKcal: 0,
                                       text: "You are \(Int(over.rounded())) kcal over. Walk about \(round5(walkAll)) minutes to even it out, or leave it, one day does not matter.")
        }
        // Large surplus: half by walking (capped at 45 min), the rest as a modest cut over the next meals, never more than 300 kcal.
        let walk = min(45, round5(over / 2 / perMin))
        let rest = max(0, over - Double(walk) * perMin)
        let eat = min(300, round5(rest))
        return MissedWorkoutAdvice(walkMinutes: walk, eatLessKcal: eat,
                                   text: "You are \(Int(over.rounded())) kcal over. Walk about \(walk) minutes and make your next meals about \(eat) kcal lighter. Do not skip meals.")
    }
}
