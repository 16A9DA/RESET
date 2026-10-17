import Foundation
import UserNotifications
import SwiftData
import Observation
import ResetCore

/// Rebuilds a short rolling window of one-off notifications. iOS keeps at most 64 pending requests and cannot
/// run our code at fire time, so reminders cannot react to what you do later. The plan is rebuilt whenever the
/// app opens, after you log something, and during background refresh.
@MainActor
@Observable
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let idPrefix = "reset."
    static let limit = 60

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    private(set) var nextWater: Date?
    private(set) var upcoming: [PlannedReminder] = []
    private var container: ModelContainer?
    private let center = UNUserNotificationCenter.current()

    // Action identifiers
    private enum Action {
        static let log250 = "reset.action.water250"
        static let snooze = "reset.action.snooze"
        static let notHungry = "reset.action.notHungry"
        static let eatLater = "reset.action.eatLater"
        static let logMeal = "reset.action.logMeal"
    }

    func setup(container: ModelContainer) {
        self.container = container
        center.delegate = self
        let water = UNNotificationCategory(identifier: "WATER", actions: [
            UNNotificationAction(identifier: Action.log250, title: "Log 250 ml", options: []),
            UNNotificationAction(identifier: Action.snooze, title: "Snooze 30 min", options: []),
        ], intentIdentifiers: [])
        let meal = UNNotificationCategory(identifier: "MEAL", actions: [
            UNNotificationAction(identifier: Action.logMeal, title: "Log a meal", options: [.foreground]),
            UNNotificationAction(identifier: Action.notHungry, title: "Not hungry", options: []),
            UNNotificationAction(identifier: Action.eatLater, title: "Eating later", options: []),
            UNNotificationAction(identifier: Action.snooze, title: "Snooze 30 min", options: []),
        ], intentIdentifiers: [])
        center.setNotificationCategories([water, meal])
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshStatus()
        return ok
    }

    var canSchedule: Bool { status == .authorized || status == .provisional }

    // MARK: Preferences

    static func pref(_ key: String, in context: ModelContext) -> ReminderPreference? {
        try? context.fetch(FetchDescriptor<ReminderPreference>(predicate: #Predicate { $0.key == key })).first
    }

    static func enabled(_ cat: ReminderCategory, in context: ModelContext) -> Bool {
        if let m = pref("master", in: context), !m.enabled { return false }
        return pref(cat.rawValue, in: context)?.enabled ?? defaultOn.contains(cat)
    }

    static func value(_ cat: ReminderCategory, default d: Int, in context: ModelContext) -> Int {
        pref(cat.rawValue, in: context)?.value ?? d
    }

    /// Off by default: intrusive categories the user should opt into.
    static let defaultOn: Set<ReminderCategory> = [.water, .meal, .bedtime, .caffeine]

    static func setEnabled(_ cat: ReminderCategory, _ on: Bool, value: Int? = nil, in context: ModelContext) {
        if let p = pref(cat.rawValue, in: context) {
            p.enabled = on
            if let value { p.value = value }
        } else {
            context.insert(ReminderPreference(key: cat.rawValue, enabled: on, value: value ?? 0))
        }
        try? context.save()
    }

    // MARK: Planning

    func rebuild(context: ModelContext, now: Date = .now) async {
        await refreshStatus()
        guard canSchedule else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
        var planned = Planner.all(profile: profile, context: context, now: now)
        planned.sort { $0.fireDate < $1.fireDate }
        planned = Array(planned.filter { $0.fireDate > now.addingTimeInterval(30) }.prefix(Self.limit))

        for p in planned {
            let c = UNMutableNotificationContent()
            c.title = p.title; c.body = p.body; c.sound = .default
            c.threadIdentifier = Self.idPrefix + p.category.rawValue
            switch p.category {
            case .water: c.categoryIdentifier = "WATER"
            case .meal: c.categoryIdentifier = "MEAL"
            default: break
            }
            // Fixed date components in the current time zone. Rebuilt on launch, so travel and DST self-correct.
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.idPrefix + p.id, content: c, trigger: trigger))
        }
        scheduledCount = planned.count
        upcoming = planned
        nextWater = planned.first { $0.category == .water }?.fireDate
    }

    func scheduleOnce(id: String, category: ReminderCategory, title: String, body: String, at date: Date) async {
        guard canSchedule else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        c.categoryIdentifier = category == .water ? "WATER" : (category == .meal ? "MEAL" : "")
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        try? await center.add(UNNotificationRequest(identifier: Self.idPrefix + id, content: c,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    // MARK: Actions from the notification

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let cat = response.notification.request.content.categoryIdentifier
        await MainActor.run {
            guard let container else { return }
            let ctx = container.mainContext
            switch action {
            case Action.log250:
                ctx.insert(WaterRecord(ml: 250, source: .manual))
                try? ctx.save()
            case Action.snooze:
                Task {
                    await scheduleOnce(id: "snooze.\(UUID().uuidString)", category: cat == "MEAL" ? .meal : .water,
                                       title: cat == "MEAL" ? "Have you eaten recently?" : "Water",
                                       body: cat == "MEAL" ? "Log a meal, or ignore this if you are fine." : "A glass of water? Tap to log it.",
                                       at: Date.now.addingTimeInterval(30 * 60))
                }
            case Action.notHungry:
                // Quiet the meal prompts for the next three hours. Missing logs never mean skipped meals.
                let p = Self.pref("meal.quiet", in: ctx) ?? { let n = ReminderPreference(key: "meal.quiet", enabled: true, value: 0); ctx.insert(n); return n }()
                p.snoozedUntil = Date.now.addingTimeInterval(3 * 3600)
                try? ctx.save()
            case Action.eatLater:
                Task { await scheduleOnce(id: "eatlater.\(UUID().uuidString)", category: .meal, title: "Time to eat?",
                                          body: "You said you would eat later. Log it when you do.", at: Date.now.addingTimeInterval(60 * 60)) }
            default: break
            }
            Task { await rebuild(context: ctx) }
        }
    }
}

/// Collects reminders from each planner. Planners for other categories are added by their features.
enum Planner {
    @MainActor
    static func all(profile: UserProfile, context: ModelContext, now: Date) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        let shape = DayShape(wakeMinute: profile.wakeMinute, bedMinute: profile.bedMinute)

        if NotificationScheduler.enabled(.water, in: context) {
            let drinks = ((try? context.fetch(FetchDescriptor<WaterRecord>(sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? [])
            let today = drinks.filter { Calendar.current.isDateInToday($0.at) }.reduce(0) { $0 + $1.ml }
            let interval = NotificationScheduler.value(.water, default: 120, in: context)
            out += Hydration.waterReminders(shape: shape, now: now, lastDrink: drinks.first?.at, todayMl: today,
                                            goalMl: profile.effectiveWaterGoalMl, intervalMinutes: interval)
        }
        let bedOn = NotificationScheduler.enabled(.bedtime, in: context)
        let wakeOn = NotificationScheduler.enabled(.wake, in: context)
        if bedOn || wakeOn {
            out += SleepPlanner.reminders(shape: shape, targetHours: profile.sleepTargetHours, windDownMinutes: profile.windDownMinutes,
                                          now: now, bedtimeOn: bedOn, wakeOn: wakeOn)
        }
        if NotificationScheduler.enabled(.caffeine, in: context) {
            out += SleepPlanner.caffeineReminders(shape: shape, hoursBefore: 8, now: now)
        }
        let cal = Calendar.current
        if NotificationScheduler.enabled(.movement, in: context) {
            out += DailyReminders.movement(workStart: profile.workStartMinute, workEnd: profile.workEndMinute, workDays: profile.workDays,
                                           intervalMinutes: NotificationScheduler.value(.movement, default: 90, in: context), now: now)
        }
        let acts = (try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []
        if NotificationScheduler.enabled(.walk, in: context) {
            let walked = acts.contains { ($0.kind == .walk || $0.kind == .run) && cal.isDateInToday($0.start) && $0.minutes >= 15 }
            out += DailyReminders.walk(shape: shape, workEnd: profile.workEndMinute, walkedToday: walked, now: now)
        }
        if NotificationScheduler.enabled(.workout, in: context) {
            let week = SessionMath.week(of: now)
            let strength = acts.filter { $0.kind == .strength && week.contains($0.start) }
            out += DailyReminders.workoutPrep(shape: shape, workEnd: profile.workEndMinute, sessionsThisWeek: strength.count,
                                              targetPerWeek: profile.gymDaysPerWeek, doneToday: strength.contains { cal.isDateInToday($0.start) }, now: now)
        }
        if NotificationScheduler.enabled(.checkIn, in: context) {
            let has = ((try? context.fetch(FetchDescriptor<CheckIn>())) ?? []).contains { cal.isDateInToday($0.at) && ($0.kind == .energy || $0.kind == .fatigue) }
            out += DailyReminders.checkIn(shape: shape, hasCheckInToday: has, now: now)
        }
        if NotificationScheduler.enabled(.meal, in: context) {
            let quiet = NotificationScheduler.pref("meal.quiet", in: context)?.snoozedUntil
            let meals = (try? context.fetch(FetchDescriptor<MealRecord>(sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? []
            let todayLogs = meals.filter { Calendar.current.isDateInToday($0.at) }.map { (at: $0.at, type: $0.mealType) }
            let history = meals.filter { $0.at > now.addingTimeInterval(-21 * 86_400) }.map { (at: $0.at, type: $0.mealType) }
            let slots = MealTiming.learned(MealTiming.slots(pattern: profile.mealPattern, shape: shape, on: now), history: history, shape: shape, on: now)
            out += MealTiming.mealReminders(slots: slots, logsToday: todayLogs, now: now, quietUntil: quiet)
            if let check = MealTiming.hungerCheck(lastMeal: meals.first?.at, shape: shape, now: now, quietUntil: quiet) { out.append(check) }
        }
        return out
    }
}
