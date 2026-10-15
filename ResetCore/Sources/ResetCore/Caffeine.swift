import Foundation

public struct CaffeineDose: Sendable, Equatable {
    public var at: Date
    public var mg: Double
    public init(at: Date, mg: Double) { self.at = at; self.mg = mg }
}

public struct CatalogDrink: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var servingMl: Double
    public var mg: Double
    public var note: String
}

public enum Caffeine {
    /// Commonly cited ceiling for healthy adults. Not a target and not a guarantee of safety.
    public static let commonlyCitedDailyMg = 400.0
    public static let halfLifeHours: (low: Double, mid: Double, high: Double) = (3, 5, 7)

    /// Typical label or reference values. Products and countries differ, so the app tells users to check their can.
    public static let catalog: [CatalogDrink] = [
        .init(name: "Hell Energy Classic", servingMl: 250, mg: 80, note: "About 32 mg per 100 ml. Check the can."),
        .init(name: "Monster Energy", servingMl: 500, mg: 160, note: "Original 500 ml can. Zero Sugar is similar, Ultra is slightly lower. Check the can."),
        .init(name: "Red Bull", servingMl: 250, mg: 80, note: "250 ml can. Check the can."),
        .init(name: "Espresso (single shot)", servingMl: 30, mg: 63, note: "Varies widely by café and bean."),
        .init(name: "Brewed coffee", servingMl: 240, mg: 95, note: "Varies widely. Large café cups can hold much more."),
        .init(name: "Black tea", servingMl: 240, mg: 47, note: "Varies with brewing time."),
    ]

    public static func catalogMatch(_ text: String) -> CatalogDrink? {
        let t = text.lowercased()
        return catalog.first { d in
            let key = d.name.lowercased().split(separator: " ").first.map(String.init) ?? ""
            return t.contains(d.name.lowercased()) || (!key.isEmpty && ["hell", "monster", "red"].contains(key) && t.contains(key == "red" ? "red bull" : key))
        }
    }

    public static func dailyTotal(_ doses: [CaffeineDose], on day: Date, calendar: Calendar = .current) -> Double {
        let w = Day.interval(of: day, calendar: calendar)
        return doses.filter { w.contains($0.at) }.reduce(0) { $0 + $1.mg }
    }

    public enum Level: Sendable, Equatable { case none, moderate, near, above }

    public static func level(totalMg: Double) -> Level {
        switch totalMg {
        case ..<1: .none
        case ..<300: .moderate
        case ..<commonlyCitedDailyMg: .near
        default: .above
        }
    }

    /// Estimated caffeine still in the body at `time`, with a range for individual differences in half-life.
    public static func remaining(_ doses: [CaffeineDose], at time: Date) -> (low: Double, mid: Double, high: Double) {
        func amount(_ half: Double) -> Double {
            doses.filter { $0.at <= time }.reduce(0) { $0 + $1.mg * pow(0.5, time.timeIntervalSince($1.at) / 3600 / half) }
        }
        return (amount(halfLifeHours.low), amount(halfLifeHours.mid), amount(halfLifeHours.high))
    }

    /// Latest sensible time for caffeine. Default is eight hours before bed.
    public static func cutoff(bedtime: Date, hoursBefore: Double = 8) -> Date {
        bedtime.addingTimeInterval(-hoursBefore * 3600)
    }

    public static func isLate(_ time: Date, bedtime: Date, hoursBefore: Double = 8) -> Bool {
        time > cutoff(bedtime: bedtime, hoursBefore: hoursBefore) && time < bedtime.addingTimeInterval(8 * 3600)
    }
}

public enum Safety {
    /// Words that mean "get medical help", not "adjust your routine". Checked on check-in notes and coach messages.
    private static let urgent = [
        "chest pain", "chest tightness", "fainted", "fainting", "passed out", "can't breathe", "cannot breathe",
        "shortness of breath", "severe palpitation", "racing heart", "irregular heartbeat", "heart racing",
        "seizure", "blacked out", "confusion",
    ]

    public static func needsUrgentCare(_ text: String) -> Bool {
        let t = text.lowercased()
        return urgent.contains { t.contains($0) }
    }

    public static let urgentMessage =
        "That can be serious. Please stop training and caffeine for now and get medical help promptly. If it is severe or comes with chest pain, trouble breathing or fainting, call your local emergency number. RE:SET can't assess this."
}
