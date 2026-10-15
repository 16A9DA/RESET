import Foundation

public enum TrainingLevel: String, Codable, Sendable, CaseIterable {
    case beginner, returning, regular

    public var title: String {
        switch self {
        case .beginner: "New to training"
        case .returning: "Getting back into it"
        case .regular: "Train regularly"
        }
    }
    /// Working sets per exercise.
    var sets: Int { self == .beginner ? 2 : 3 }
}

public struct Exercise: Codable, Hashable, Sendable {
    public var name: String
    public var sets: Int
    public var reps: String
    public var restSec: Int
    public var modification: String?
}

public struct WorkoutSuggestion: Codable, Equatable, Sendable {
    public var title: String
    public var kind: ActivityKind
    public var minutes: Int
    public var exercises: [Exercise]
    public var stepTarget: Int?
    /// Plain-language why. Always shown.
    public var reason: String
    /// True for anything that should not be forced on a tired or unwell day.
    public var strenuous: Bool
}

public struct PastSession: Sendable {
    public var kind: ActivityKind
    public var title: String
    public var day: Date
    public var completed: Bool
    public init(kind: ActivityKind, title: String, day: Date, completed: Bool = true) {
        self.kind = kind; self.title = title; self.day = day; self.completed = completed
    }
}

public struct WorkoutContext: Sendable {
    public var band: RecoveryBand
    public var symptoms: Bool
    public var equipment: Equipment
    public var level: TrainingLevel
    public var minutesAvailable: Int
    public var goal: Goal
    public var gymDaysPerWeek: Int
    public var recent: [PastSession]
    public var now: Date
    /// Average daily steps over the last week, when known.
    public var avgSteps: Int?
    public var planned: Bool
    public var calendar: Calendar

    public init(band: RecoveryBand, symptoms: Bool = false, equipment: Equipment = .gym, level: TrainingLevel = .returning,
                minutesAvailable: Int = 45, goal: Goal = .fatLossKeepMuscle, gymDaysPerWeek: Int = 3, recent: [PastSession] = [],
                now: Date = .now, avgSteps: Int? = nil, planned: Bool = true, calendar: Calendar = .current) {
        self.band = band; self.symptoms = symptoms; self.equipment = equipment; self.level = level
        self.minutesAvailable = minutesAvailable; self.goal = goal; self.gymDaysPerWeek = gymDaysPerWeek
        self.recent = recent; self.now = now; self.avgSteps = avgSteps; self.planned = planned; self.calendar = calendar
    }
}

public enum WorkoutGenerator {
    // MARK: Templates

    private static func ex(_ n: String, _ sets: Int, _ reps: String, rest: Int = 90, mod: String? = nil) -> Exercise {
        Exercise(name: n, sets: sets, reps: reps, restSec: rest, modification: mod)
    }

    static func strength(variant: Int, equipment: Equipment, sets: Int) -> (title: String, exercises: [Exercise]) {
        let a = variant == 0
        switch equipment {
        case .gym:
            return a
            ? ("Full body A", [ex("Leg press or goblet squat", sets, "8-10", mod: "Use a box squat if knees complain"),
                               ex("Dumbbell or barbell bench press", sets, "8-10", mod: "Incline push-up if no bench"),
                               ex("Seated cable row", sets, "10-12"), ex("Romanian deadlift", sets, "8-10", mod: "Lighter weight, same pattern"),
                               ex("Plank", 2, "30-45 s", rest: 45)])
            : ("Full body B", [ex("Walking lunge", sets, "10 each leg", mod: "Split squat holding a rail"),
                               ex("Overhead dumbbell press", sets, "8-10"), ex("Lat pulldown", sets, "10-12"),
                               ex("Hip thrust", sets, "10-12"), ex("Farmer carry", 2, "30-40 m", rest: 60)])
        case .dumbbells:
            return a
            ? ("Dumbbell full body A", [ex("Goblet squat", sets, "10-12"), ex("Dumbbell floor press", sets, "8-12"),
                                        ex("One arm dumbbell row", sets, "10 each side"), ex("Dumbbell Romanian deadlift", sets, "10-12"),
                                        ex("Dead bug", 2, "8 each side", rest: 45)])
            : ("Dumbbell full body B", [ex("Reverse lunge", sets, "8-10 each leg"), ex("Dumbbell shoulder press", sets, "8-10"),
                                        ex("Chest supported or bent over row", sets, "10-12"), ex("Glute bridge with dumbbell", sets, "12-15"),
                                        ex("Plank", 2, "30-45 s", rest: 45)])
        case .none:
            return a
            ? ("Bodyweight A", [ex("Squat", sets, "12-15", mod: "Sit to a chair"), ex("Push-up", sets, "6-12", mod: "Hands on a table or wall"),
                                ex("Glute bridge", sets, "12-15"), ex("Dead bug", 2, "8 each side", rest: 45), ex("Plank", 2, "20-40 s", rest: 45)])
            : ("Bodyweight B", [ex("Split squat", sets, "8-10 each leg", mod: "Hold a doorframe"), ex("Pike push-up or incline push-up", sets, "6-10"),
                                ex("Towel or backpack row", sets, "10-12"), ex("Single leg glute bridge", sets, "8-10 each side"),
                                ex("Side plank", 2, "20-30 s each side", rest: 45)])
        }
    }

    static let mobility = [ex("Cat cow", 1, "10 slow reps", rest: 0), ex("Hip flexor stretch", 1, "40 s each side", rest: 0),
                           ex("Thoracic rotation", 1, "8 each side", rest: 0), ex("Hamstring stretch", 1, "40 s each side", rest: 0),
                           ex("Child's pose", 1, "60 s", rest: 0)]

    // MARK: Selection

    public static func suggest(_ c: WorkoutContext) -> WorkoutSuggestion {
        let cal = c.calendar
        let lastWeek = c.recent.filter { $0.completed && c.now.timeIntervalSince($0.day) <= 7 * 86_400 }
        let strengthWeek = lastWeek.filter { $0.kind == .strength }.count
        let strengthYesterday = c.recent.contains {
            $0.completed && $0.kind == .strength && cal.isDate($0.day, inSameDayAs: cal.date(byAdding: .day, value: -1, to: c.now) ?? c.now)
        }
        let strengthStreak = streak(c.recent.filter { $0.kind == .strength && $0.completed }, now: c.now, calendar: cal)
        let walkMinutes = [c.band == .low ? 20 : (c.band == .moderate ? 30 : 40), c.minutesAvailable].min() ?? 20

        if c.symptoms {
            return rest("You reported symptoms. Rest today. Gentle movement is fine if it feels okay, but nothing hard. See a clinician if symptoms persist or worry you.")
        }
        if c.band == .low {
            return walk(minutes: max(15, min(walkMinutes, 25)), c, reason: "Recovery looks low, so an easy walk beats forcing a workout. It still counts, and it helps you move without adding strain.")
        }
        if c.minutesAvailable < 20 {
            return walk(minutes: max(10, c.minutesAvailable), c, reason: "Short on time. A brisk walk keeps the day active without squeezing in a rushed workout.")
        }
        if !c.planned {
            return walk(minutes: walkMinutes, c, reason: "No gym planned today, so a walk keeps momentum. Missing the gym is not a setback.")
        }
        // Weekly cap, and always a rest day after three strength days in a row or the day after a session.
        if strengthWeek >= c.gymDaysPerWeek || strengthStreak >= 3 || strengthYesterday && c.level != .regular {
            return walk(minutes: walkMinutes, c, reason: strengthStreak >= 3 ? "Three strength days in a row. A walk or rest lets you recover and come back stronger."
                        : "You are on track for strength this week, so today is a lighter day. A walk fits well.")
        }

        // Alternate A and B based on the last strength session.
        let lastStrength = c.recent.filter { $0.kind == .strength && $0.completed }.max { $0.day < $1.day }
        let variant = (lastStrength?.title.hasSuffix("A") ?? false) ? 1 : 0

        var sets = c.level.sets
        var minutes = min(c.minutesAvailable, 50)
        var why = "Strength training protects muscle while you lose fat, and it works best with enough recovery between sessions."
        if c.band == .moderate {
            sets = max(2, sets - 1)
            minutes = min(minutes, 35)
            why = "Recovery is moderate, so this is a trimmed version: one fewer set each. " + why
        }
        if c.band == .unknown { why += " Not enough recovery data to tune it, so go by how you feel." }
        if minutes < 30 { sets = 2 }

        let t = strength(variant: variant, equipment: c.equipment, sets: sets)
        why += " " + progressionNote(c)
        return WorkoutSuggestion(title: t.title, kind: .strength, minutes: minutes, exercises: t.exercises, stepTarget: nil,
                                 reason: why, strenuous: true)
    }

    /// Offered in the evening when a planned workout did not happen. Never framed as a failure.
    public static func missedSessionAlternative(_ c: WorkoutContext) -> WorkoutSuggestion {
        var ctx = c
        ctx.band = c.band == .good || c.band == .unknown ? .moderate : c.band
        return walk(minutes: 20, ctx, reason: "No gym today, and that is fine. A 20 minute walk is a real session, and tomorrow stays the same size. You do not need to make up for it.")
    }

    static func walk(minutes: Int, _ c: WorkoutContext, reason: String) -> WorkoutSuggestion {
        // Target built from the user's own average and capped, never ramped because sessions were missed.
        var target: Int?
        if let avg = c.avgSteps, avg > 0 { target = min(10_000, max(4_000, Int((Double(avg) * 1.1 / 500).rounded()) * 500)) }
        return WorkoutSuggestion(title: "\(minutes) minute walk", kind: .walk, minutes: minutes, exercises: [], stepTarget: target,
                                 reason: reason + " Standing and walking at work is useful, but it is not the same as a planned walk or a strength session.",
                                 strenuous: false)
    }

    static func rest(_ reason: String) -> WorkoutSuggestion {
        WorkoutSuggestion(title: "Rest and light mobility", kind: .mobility, minutes: 10, exercises: mobility, stepTarget: nil, reason: reason, strenuous: false)
    }

    public static func mobilitySession() -> WorkoutSuggestion {
        WorkoutSuggestion(title: "10 minute mobility", kind: .mobility, minutes: 10, exercises: mobility, stepTarget: nil,
                          reason: "Gentle work on hips, back and shoulders. Good on a heavy workday.", strenuous: false)
    }

    /// Progress only after consistent completed sessions. Missed sessions never raise the load.
    static func progressionNote(_ c: WorkoutContext) -> String {
        let done = c.recent.filter { $0.kind == .strength && $0.completed }.sorted { $0.day > $1.day }.prefix(3)
        let missed = c.recent.contains { $0.kind == .strength && !$0.completed && c.now.timeIntervalSince($0.day) <= 7 * 86_400 }
        if missed { return "Keep the same weights as last time. Skipped sessions do not mean you should do more." }
        if done.count >= 3 { return "You have completed your last three sessions, so add one rep to each set or a small amount of weight if the last set felt easy." }
        return "Keep a rep or two in reserve on every set."
    }

    static func streak(_ sessions: [PastSession], now: Date, calendar: Calendar) -> Int {
        var n = 0
        for back in 1...7 {
            guard let d = calendar.date(byAdding: .day, value: -back, to: now) else { break }
            if sessions.contains(where: { calendar.isDate($0.day, inSameDayAs: d) }) { n += 1 } else { break }
        }
        return n
    }
}
