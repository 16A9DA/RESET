import Foundation

/// One day of facts for pattern finding. nil means not recorded, and such days are left out of that comparison.
public struct InsightDay: Sendable {
    public var date: Date
    public var sleepHours: Double?
    /// Quality of the night that ended this morning.
    public var sleepQuality: Double?
    /// Morning or daytime energy, 1 to 5.
    public var energy: Double?
    public var fatigue: Double?
    public var lateCaffeine: Bool?
    public var walkMinutes: Double
    public var trained: Bool
    public var firstMealMinute: Double?
    public var isUniversityDay: Bool
    /// Hours at work from place detection, 0 when none.
    public var workHours: Double

    public init(date: Date, sleepHours: Double? = nil, sleepQuality: Double? = nil, energy: Double? = nil, fatigue: Double? = nil,
                lateCaffeine: Bool? = nil, walkMinutes: Double = 0, trained: Bool = false, firstMealMinute: Double? = nil,
                isUniversityDay: Bool = false, workHours: Double = 0) {
        self.date = date; self.sleepHours = sleepHours; self.sleepQuality = sleepQuality; self.energy = energy
        self.fatigue = fatigue; self.lateCaffeine = lateCaffeine; self.walkMinutes = walkMinutes; self.trained = trained
        self.firstMealMinute = firstMealMinute; self.isUniversityDay = isUniversityDay; self.workHours = workHours
    }
}

public struct Insight: Identifiable, Equatable, Sendable {
    public enum State: Sendable { case pattern, noDifference, collecting }
    public var id: String
    public var title: String
    public var text: String
    public var state: State
    /// Observations behind it, shown to the user.
    public var observations: Int
}

public enum InsightEngine {
    /// Each side of a comparison needs this many days before anything is said.
    public static let minPerGroup = 3
    /// And this many in total.
    public static let minTotal = 8
    public static let cautionNote = "These are patterns in your own entries. They show what happened together, not what caused what."

    struct Cmp { var a: [Double]; var b: [Double]
        var meanA: Double { a.reduce(0, +) / Double(a.count) }
        var meanB: Double { b.reduce(0, +) / Double(b.count) }
        var enough: Bool { a.count >= InsightEngine.minPerGroup && b.count >= InsightEngine.minPerGroup && a.count + b.count >= InsightEngine.minTotal }
    }

    private static func collecting(_ id: String, _ title: String, need: String, have: Int) -> Insight {
        Insight(id: id, title: title, text: "Still collecting data. \(need)", state: .collecting, observations: have)
    }

    private static func f(_ v: Double) -> String { String(format: "%.1f", v) }

    public static func all(_ days: [InsightDay], sleepTarget: Double) -> [Insight] {
        [workVsSleep(days), gymVsSleep(days), sleepVsEnergy(days, target: sleepTarget), caffeineVsSleep(days), walkVsEnergy(days), fatigueVsTraining(days), mealTiming(days)]
    }

    /// Sleep on the night after each day, paired with a yes/no trait of that day. Needs consecutive days.
    private static func nextNight(_ days: [InsightDay], trait: (InsightDay) -> Bool?) -> Cmp {
        let sorted = days.sorted { $0.date < $1.date }
        var yes: [Double] = [], no: [Double] = []
        for (i, d) in sorted.enumerated() where i + 1 < sorted.count {
            guard let t = trait(d), let h = sorted[i + 1].sleepHours, sorted[i + 1].date.timeIntervalSince(d.date) < 36 * 3600 else { continue }
            if t { yes.append(h) } else { no.append(h) }
        }
        return Cmp(a: yes, b: no)
    }

    public static func workVsSleep(_ days: [InsightDay]) -> Insight {
        let id = "workSleep", title = "Long work days"
        let c = nextNight(days) { $0.workHours > 0 ? $0.workHours >= 9 : nil }
        guard c.enough else { return collecting(id, title, need: "Needs \(minPerGroup) days of 9 hours or more and \(minPerGroup) shorter, with sleep.", have: c.a.count + c.b.count) }
        let d = c.meanA - c.meanB
        if abs(d) < 0.4 { return Insight(id: id, title: title, text: "Sleep after long work days matches the rest (\(f(c.meanA)) h vs \(f(c.meanB)) h).", state: .noDifference, observations: c.a.count + c.b.count) }
        return Insight(id: id, title: title,
                       text: "After \(c.a.count) work days of 9 h or more you slept \(f(c.meanA)) h, against \(f(c.meanB)) h otherwise. \(d < 0 ? "Long days cost you sleep. Protect an earlier night after them." : "You sleep longer after long days.")",
                       state: .pattern, observations: c.a.count + c.b.count)
    }

    public static func gymVsSleep(_ days: [InsightDay]) -> Insight {
        let id = "gymSleep", title = "Training and sleep"
        let c = nextNight(days) { $0.trained }
        guard c.enough else { return collecting(id, title, need: "Needs \(minPerGroup) training and \(minPerGroup) rest days, with sleep.", have: c.a.count + c.b.count) }
        let d = c.meanA - c.meanB
        if abs(d) < 0.4 { return Insight(id: id, title: title, text: "Sleep is the same after training and rest days (\(f(c.meanA)) h vs \(f(c.meanB)) h).", state: .noDifference, observations: c.a.count + c.b.count) }
        return Insight(id: id, title: title,
                       text: "You sleep \(f(c.meanA)) h after training days and \(f(c.meanB)) h after rest days. \(d > 0 ? "Training helps your sleep." : "Training days cost you sleep. Try finishing earlier.")",
                       state: .pattern, observations: c.a.count + c.b.count)
    }

    public static func sleepVsEnergy(_ days: [InsightDay], target: Double) -> Insight {
        let id = "sleepEnergy", title = "Sleep and energy"
        let rows = days.compactMap { d -> (Double, Double)? in d.sleepHours.flatMap { s in d.energy.map { (s, $0) } } }
        let c = Cmp(a: rows.filter { $0.0 < target - 1 }.map(\.1), b: rows.filter { $0.0 >= target - 1 }.map(\.1))
        guard c.enough else { return collecting(id, title, need: "Needs at least \(minPerGroup) shorter-sleep and \(minPerGroup) well-slept days with an energy check-in.", have: rows.count) }
        let d = c.meanA - c.meanB
        if abs(d) < 0.5 { return Insight(id: id, title: title, text: "Your reported energy looks similar after shorter and longer sleep so far (\(f(c.meanA)) vs \(f(c.meanB)) of 5, \(c.a.count) vs \(c.b.count) days).", state: .noDifference, observations: rows.count) }
        return Insight(id: id, title: title,
                       text: "On \(c.a.count) days after sleeping more than an hour under target, your energy averaged \(f(c.meanA)) of 5, against \(f(c.meanB)) on \(c.b.count) other days. \(d < 0 ? "Lower energy tends to go with shorter sleep for you." : "Energy was higher after shorter sleep, which may be chance or other factors.")",
                       state: .pattern, observations: rows.count)
    }

    public static func caffeineVsSleep(_ days: [InsightDay]) -> Insight {
        let id = "caffeineSleep", title = "Late caffeine and sleep quality"
        // Caffeine on day D is paired with the sleep quality reported on D+1.
        let sorted = days.sorted { $0.date < $1.date }
        var late: [Double] = [], other: [Double] = []
        for (i, d) in sorted.enumerated() where i + 1 < sorted.count {
            guard let lc = d.lateCaffeine, let q = sorted[i + 1].sleepQuality else { continue }
            let gap = sorted[i + 1].date.timeIntervalSince(d.date)
            guard gap < 36 * 3600 else { continue }
            if lc { late.append(q) } else { other.append(q) }
        }
        let c = Cmp(a: late, b: other)
        guard c.enough else { return collecting(id, title, need: "Needs \(minPerGroup) nights after late caffeine and \(minPerGroup) after none, with a sleep rating.", have: late.count + other.count) }
        let d = c.meanA - c.meanB
        if abs(d) < 0.5 { return Insight(id: id, title: title, text: "Sleep ratings look similar after late caffeine and after none (\(f(c.meanA)) vs \(f(c.meanB)) of 5).", state: .noDifference, observations: late.count + other.count) }
        return Insight(id: id, title: title,
                       text: "After \(c.a.count) days with caffeine close to bedtime, your sleep rating averaged \(f(c.meanA)) of 5, against \(f(c.meanB)) after \(c.b.count) days without. \(d < 0 ? "Sleep was rated lower after late caffeine." : "Sleep was not rated lower after late caffeine in your data.")",
                       state: .pattern, observations: late.count + other.count)
    }

    public static func walkVsEnergy(_ days: [InsightDay]) -> Insight {
        let id = "walkEnergy", title = "Walking and energy"
        let rows = days.compactMap { d in d.energy.map { (d.walkMinutes, $0) } }
        let c = Cmp(a: rows.filter { $0.0 >= 20 }.map(\.1), b: rows.filter { $0.0 < 20 }.map(\.1))
        guard c.enough else { return collecting(id, title, need: "Needs \(minPerGroup) days with a 20 minute walk and \(minPerGroup) without, each with an energy check-in.", have: rows.count) }
        let d = c.meanA - c.meanB
        if abs(d) < 0.5 { return Insight(id: id, title: title, text: "Energy looks about the same on walking and non-walking days so far (\(f(c.meanA)) vs \(f(c.meanB)) of 5).", state: .noDifference, observations: rows.count) }
        return Insight(id: id, title: title,
                       text: "On \(c.a.count) days with a walk of 20 minutes or more, energy averaged \(f(c.meanA)) of 5, against \(f(c.meanB)) on \(c.b.count) days without. \(d > 0 ? "Walking days went with higher energy." : "Walking days did not go with higher energy.")",
                       state: .pattern, observations: rows.count)
    }

    public static func fatigueVsTraining(_ days: [InsightDay]) -> Insight {
        let id = "fatigueTraining", title = "Fatigue and training"
        let rows = days.compactMap { d in d.fatigue.map { ($0, d.trained ? 1.0 : 0.0) } }
        let c = Cmp(a: rows.filter { $0.0 >= 4 }.map(\.1), b: rows.filter { $0.0 < 4 }.map(\.1))
        guard c.enough else { return collecting(id, title, need: "Needs \(minPerGroup) high-fatigue and \(minPerGroup) lower-fatigue days with a fatigue check-in.", have: rows.count) }
        let pa = Int((c.meanA * 100).rounded()), pb = Int((c.meanB * 100).rounded())
        if abs(c.meanA - c.meanB) < 0.2 { return Insight(id: id, title: title, text: "You trained at a similar rate on high and lower fatigue days (\(pa)% vs \(pb)%).", state: .noDifference, observations: rows.count) }
        return Insight(id: id, title: title,
                       text: "You trained on \(pa)% of \(c.a.count) high-fatigue days, against \(pb)% of \(c.b.count) other days. \(c.meanA < c.meanB ? "Skipping on tired days is a sensible response. A walk is a fine substitute." : "You are training even when tired. Consider easier sessions on those days.")",
                       state: .pattern, observations: rows.count)
    }

    public static func mealTiming(_ days: [InsightDay]) -> Insight {
        let id = "mealTiming", title = "First meal timing on university days"
        let uni = days.filter { $0.isUniversityDay }.compactMap(\.firstMealMinute)
        let other = days.filter { !$0.isUniversityDay }.compactMap(\.firstMealMinute)
        guard uni.count >= minPerGroup, other.count >= minPerGroup, uni.count + other.count >= minTotal else {
            return collecting(id, title, need: "Needs \(minPerGroup) university and \(minPerGroup) other days with a logged meal.", have: uni.count + other.count)
        }
        func sd(_ v: [Double]) -> Double { let m = v.reduce(0, +) / Double(v.count); return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot() }
        func clock(_ m: Double) -> String { String(format: "%02d:%02d", Int(m) / 60, Int(m) % 60) }
        let su = sd(uni), so = sd(other)
        let mu = uni.reduce(0, +) / Double(uni.count)
        if su - so < 30 { return Insight(id: id, title: title, text: "Your first meal is about as regular on university days as other days (average \(clock(mu))).", state: .noDifference, observations: uni.count + other.count) }
        return Insight(id: id, title: title,
                       text: "On \(uni.count) university days your first meal varied by about \(Int(su.rounded())) minutes around \(clock(mu)), against about \(Int(so.rounded())) minutes on other days. A fixed time or a packed first meal could help.",
                       state: .pattern, observations: uni.count + other.count)
    }
}

public enum CSV {
    public static func escape(_ s: String) -> String {
        guard s.contains(where: { ",\"\n\r".contains($0) }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Spreadsheet formula injection guard: values starting with = + - @ are prefixed so they stay text.
    public static func safe(_ s: String) -> String {
        if let f = s.first, "=+-@".contains(f), Double(s) == nil { return "'" + s }
        return s
    }

    public static func build(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map { escape(safe($0)) }.joined(separator: ",") }.joined(separator: "\n") + "\n"
    }
}
