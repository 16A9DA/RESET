import Foundation

/// Everything the dashboard and the coach know about one day. A nil value means "not recorded", never zero.
public struct DaySummary: Codable, Equatable, Sendable {
    public var date: Date
    public var sleepHours: Double?
    public var sleepTargetHours: Double
    public var energy: Int?
    public var fatigue: Int?
    public var steps: Int?
    public var stepSource: String?
    public var structuredActivityMinutes: Double
    public var workouts: [String]
    public var kcalConsumed: Double
    public var kcalTarget: Double?
    public var kcalMaintenance: Double?
    public var calorieCounting: Bool
    public var proteinG: Double
    public var proteinTargetG: Double
    public var carbsG = 0.0
    public var carbsTargetG = 0.0
    public var fatG = 0.0
    public var fatTargetG = 0.0
    public var mealsLogged: Int
    public var estimatedItems: Int
    public var waterMl: Double
    public var waterGoalMl: Double?
    public var caffeineMg: Double
    public var workSeconds: Double?
    public var universitySeconds: Double?
    public var recoveryBand: RecoveryBand
    public var recoveryReasons: [String]

    public var calorieBalance: Double? { Energy.balance(consumedKcal: kcalConsumed, maintenanceKcal: kcalMaintenance) }
    public var kcalRemaining: Double? { kcalTarget.map { $0 - kcalConsumed } }

    public init(date: Date, sleepHours: Double? = nil, sleepTargetHours: Double = 8, energy: Int? = nil, fatigue: Int? = nil,
                steps: Int? = nil, stepSource: String? = nil, structuredActivityMinutes: Double = 0, workouts: [String] = [],
                kcalConsumed: Double = 0, kcalTarget: Double? = nil, kcalMaintenance: Double? = nil, calorieCounting: Bool = true,
                proteinG: Double = 0, proteinTargetG: Double = 0, mealsLogged: Int = 0, estimatedItems: Int = 0,
                waterMl: Double = 0, waterGoalMl: Double? = nil, caffeineMg: Double = 0, workSeconds: Double? = nil,
                universitySeconds: Double? = nil, recoveryBand: RecoveryBand = .unknown, recoveryReasons: [String] = []) {
        self.date = date; self.sleepHours = sleepHours; self.sleepTargetHours = sleepTargetHours; self.energy = energy
        self.fatigue = fatigue; self.steps = steps; self.stepSource = stepSource
        self.structuredActivityMinutes = structuredActivityMinutes; self.workouts = workouts
        self.kcalConsumed = kcalConsumed; self.kcalTarget = kcalTarget; self.kcalMaintenance = kcalMaintenance
        self.calorieCounting = calorieCounting; self.proteinG = proteinG; self.proteinTargetG = proteinTargetG
        self.mealsLogged = mealsLogged; self.estimatedItems = estimatedItems; self.waterMl = waterMl
        self.waterGoalMl = waterGoalMl; self.caffeineMg = caffeineMg; self.workSeconds = workSeconds
        self.universitySeconds = universitySeconds; self.recoveryBand = recoveryBand; self.recoveryReasons = recoveryReasons
    }
}

public enum Priority {
    /// One sentence for the top of Today. Deterministic and rule ordered: safety, recovery, then habits.
    public static func message(_ s: DaySummary, symptoms: Bool, hour: Int) -> String {
        if symptoms { return "Rest and look after yourself. Skip hard training and get checked if symptoms continue." }
        let longWork = (s.workSeconds ?? 0) >= 9 * 3600
        let shortSleep = (s.sleepHours.map { $0 < s.sleepTargetHours - 1.5 }) ?? false
        switch s.recoveryBand {
        case .low:
            if longWork { return "Recover from a demanding workday and get enough sleep." }
            if shortSleep { return "An easy day and an earlier night to make up for short sleep." }
            return "Take it easy and let your body recover."
        case .unknown:
            return "Log last night's sleep and a quick check-in so I can tailor the day."
        default: break
        }
        if let goal = s.waterGoalMl, hour >= 15, s.waterMl < goal * 0.4 {
            return "Catch up on water over the next few hours."
        }
        if hour >= 17, s.proteinTargetG > 0, s.proteinG < s.proteinTargetG * 0.5, s.mealsLogged > 0 {
            return "Get a solid protein source into your evening meal."
        }
        if s.recoveryBand == .good && s.workouts.isEmpty && s.structuredActivityMinutes < 20 {
            return "Fit in your planned workout or a good walk."
        }
        return "Keep the basics steady. Water, regular meals and an on-time bedtime."
    }
}

public enum TimelineKind: String, Codable, Sendable {
    case sleep, work, university, meal, water, caffeine, activity, workout, checkIn, reminder
}

/// How a timeline entry came to exist, so the user can judge how much to trust it.
public enum Origin: String, Codable, Sendable {
    case automatic = "Detected automatically"
    case imported = "Imported"
    case manual = "Entered by you"
    case aiEstimate = "AI estimate"
    case confirmed = "Confirmed by you"

    public static func from(_ source: Source, status: SessionStatus? = nil) -> Origin {
        if status == .confirmed { return .confirmed }
        switch source {
        case .auto: return .automatic
        case .imported: return .imported
        case .manual: return .manual
        case .aiEstimate: return .aiEstimate
        case .confirmed: return .confirmed
        }
    }
}

public struct TimelineEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: TimelineKind
    public var start: Date
    public var end: Date?
    public var title: String
    public var detail: String
    public var origin: Origin
    public init(id: String, kind: TimelineKind, start: Date, end: Date? = nil, title: String, detail: String = "", origin: Origin) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.title = title; self.detail = detail; self.origin = origin
    }
}

public enum Timeline {
    /// Entries for one day in time order. Sleep that ended today is shown at the wake-up. Water drinks within
    /// `groupMinutes` of each other collapse into one line so the timeline stays readable.
    public static func build(_ entries: [TimelineEntry], on day: Date, groupMinutes: Int = 45, calendar: Calendar = .current) -> [TimelineEntry] {
        let w = Day.interval(of: day, calendar: calendar)
        let today = entries.filter { w.contains($0.start) || ($0.end.map { w.contains($0) } ?? false) }.sorted { $0.start < $1.start }
        var out: [TimelineEntry] = []
        for e in today {
            if e.kind == .water, let last = out.last, last.kind == .water, e.start.timeIntervalSince(last.end ?? last.start) <= Double(groupMinutes) * 60,
               let a = Double(last.detail.split(separator: " ").first ?? ""), let b = Double(e.detail.split(separator: " ").first ?? "") {
                var merged = last
                merged.end = e.start
                merged.detail = "\(Int(a + b)) ml"
                merged.title = "Water"
                out[out.count - 1] = merged
            } else {
                out.append(e)
            }
        }
        return out
    }
}
