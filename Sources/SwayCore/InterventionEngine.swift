import Foundation

/// Signals about what the user is doing that should hold notifications.
/// Each one is something the OS actually exposes; Sway never claims to know
/// more (e.g. it cannot see whether a screen is being shared).
public struct InterruptionContext: Equatable, Sendable {
    /// Another app is using the microphone or a camera (likely a call).
    public var micOrCameraInUseByOthers = false
    /// The frontmost app covers a whole display (presenting, a video, or
    /// deliberate full-screen focus).
    public var fullScreenAppInFront = false
    public var pausedUntil: Date?

    public init(micOrCameraInUseByOthers: Bool = false, fullScreenAppInFront: Bool = false, pausedUntil: Date? = nil) {
        self.micOrCameraInUseByOthers = micOrCameraInUseByOthers
        self.fullScreenAppInFront = fullScreenAppInFront
        self.pausedUntil = pausedUntil
    }
}

public enum HoldReason: Equatable, Sendable {
    case paused(until: Date)
    case notificationsOff
    case quietHours
    case likelyInCall
    case fullScreen

    public var label: String {
        switch self {
        case .paused(let until):
            let f = DateFormatter()
            f.timeStyle = .short
            return "Paused until \(f.string(from: until))"
        case .notificationsOff: return "Notifications are off"
        case .quietHours: return "Quiet hours"
        case .likelyInCall: return "Microphone or camera in use by another app"
        case .fullScreen: return "A full-screen app is in front"
        }
    }
}

public struct InterventionDecision: Equatable, Sendable {
    /// At most one notification per evaluation.
    public var deliver: DueReminder?
    /// Due reminders shown only as a menu-bar indication.
    public var passive: [DueReminder]
    /// Why nothing was delivered, when a context holds reminders.
    public var hold: HoldReason?

    public init(deliver: DueReminder?, passive: [DueReminder], hold: HoldReason?) {
        self.deliver = deliver
        self.passive = passive
        self.hold = hold
    }
}

/// Notification policy: deduplication, per-kind cooldowns, global spacing,
/// hourly/daily budgets, snooze limits and backing off after dismissals.
public struct InterventionEngine: Codable, Equatable, Sendable {
    struct Snooze: Codable, Equatable, Sendable {
        var until: Date
        var count: Int
    }

    /// Delivery times (bounded to the last 24 h) for budgets and spacing.
    private(set) var deliveries: [Date] = []
    private(set) var lastDeliveredByKind: [ReminderKind: Date] = [:]
    /// Instances already notified; never notified again unless snoozed.
    private(set) var deliveredInstances: [String: Date] = [:]
    private var snoozes: [String: Snooze] = [:]
    /// Consecutive dismissals/"not helpful" per kind, reset by acceptance.
    private(set) var negativeStreak: [ReminderKind: Int] = [:]
    /// Kinds silenced (menu bar only) until the given time after repeated
    /// dismissals.
    private(set) var silencedUntil: [ReminderKind: Date] = [:]

    public static let silenceAfterStreak = 3

    public init() {}

    public static func cooldown(for kind: ReminderKind) -> TimeInterval {
        switch kind {
        case .microBreak: return 15 * 60
        case .longBreak, .longSession: return 20 * 60
        case .eyeRest: return 15 * 60
        case .workstationReview: return 20 * 60 * 60
        default: return 25 * 60   // posture kinds
        }
    }

    public func holdReason(now: Date, context: InterruptionContext, settings: CoachSettings) -> HoldReason? {
        if let until = context.pausedUntil, until > now { return .paused(until: until) }
        if !settings.notificationsEnabled { return .notificationsOff }
        if settings.isQuietHours(at: now) { return .quietHours }
        if settings.holdDuringCalls, context.micOrCameraInUseByOthers { return .likelyInCall }
        if settings.holdDuringFullScreen, context.fullScreenAppInFront { return .fullScreen }
        return nil
    }

    public func decide(candidates: [DueReminder], now: Date, context: InterruptionContext, settings: CoachSettings, adjustments: Adjustments = .neutral) -> InterventionDecision {
        let sorted = candidates.sorted { $0.priority > $1.priority }
        if let hold = holdReason(now: now, context: context, settings: settings) {
            return InterventionDecision(deliver: nil, passive: sorted, hold: hold)
        }
        var passive: [DueReminder] = []
        var chosen: DueReminder?
        for c in sorted {
            if chosen == nil, canDeliver(c, now: now, settings: settings, adjustments: adjustments) {
                chosen = c
            } else {
                passive.append(c)
            }
        }
        return InterventionDecision(deliver: chosen, passive: passive, hold: nil)
    }

    func canDeliver(_ c: DueReminder, now: Date, settings: CoachSettings, adjustments: Adjustments) -> Bool {
        if c.level == .passive { return false }
        let snooze = snoozes[c.instanceID]
        if let snooze, snooze.until > now { return false }
        let returningFromSnooze = snooze != nil
        if deliveredInstances[c.instanceID] != nil, !returningFromSnooze { return false }
        if let until = silencedUntil[c.kind], until > now, c.kind != .longSession { return false }
        if !returningFromSnooze, let last = lastDeliveredByKind[c.kind] {
            let streak = Double(min(negativeStreak[c.kind] ?? 0, 2))
            let cooldown = Self.cooldown(for: c.kind) * pow(2, streak) * adjustments.cooldownMultiplier(c.kind)
            if now.timeIntervalSince(last) < cooldown { return false }
        }
        if let lastAny = deliveries.last, now.timeIntervalSince(lastAny) < settings.minSpacingBetweenNotifications { return false }
        let lastHour = deliveries.filter { now.timeIntervalSince($0) < 3600 }.count
        if lastHour >= settings.maxNotificationsPerHour { return false }
        let today = deliveries.filter { Calendar.current.isDate($0, inSameDayAs: now) }.count
        if today >= settings.maxNotificationsPerDay { return false }
        return true
    }

    public mutating func recordDelivered(_ r: DueReminder, at now: Date) {
        deliveries.append(now)
        deliveries.removeAll { now.timeIntervalSince($0) > 86_400 }
        lastDeliveredByKind[r.kind] = now
        deliveredInstances[r.instanceID] = now
        if let s = snoozes[r.instanceID] {
            // Delivered again after a snooze: consumed until snoozed again.
            snoozes[r.instanceID] = Snooze(until: .distantFuture, count: s.count)
        }
        if deliveredInstances.count > 400 {
            deliveredInstances = deliveredInstances.filter { now.timeIntervalSince($0.value) < 86_400 * 2 }
        }
    }

    public func snoozeCount(_ instanceID: String) -> Int { snoozes[instanceID]?.count ?? 0 }

    public func canSnooze(_ instanceID: String, settings: CoachSettings) -> Bool {
        snoozeCount(instanceID) < settings.maxSnoozesPerReminder
    }

    /// Returns false when the snooze limit was already reached (the reminder
    /// then simply stays in the menu bar; it is not re-sent).
    @discardableResult
    public mutating func snooze(_ instanceID: String, kind: ReminderKind, now: Date, settings: CoachSettings) -> Bool {
        let count = snoozeCount(instanceID)
        guard count < settings.maxSnoozesPerReminder else { return false }
        snoozes[instanceID] = Snooze(until: now.addingTimeInterval(settings.snoozeDuration), count: count + 1)
        pruneSnoozes(now: now)
        return true
    }

    public mutating func record(_ response: PromptResponse, kind: ReminderKind, now: Date) {
        switch response {
        case .accepted, .helpful:
            negativeStreak[kind] = 0
            silencedUntil[kind] = nil
        case .snoozed:
            break
        case .dismissed, .unhelpful:
            let streak = (negativeStreak[kind] ?? 0) + (response == .unhelpful ? 2 : 1)
            negativeStreak[kind] = streak
            if streak >= Self.silenceAfterStreak {
                // Back off to the menu bar for the rest of the day.
                let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
                silencedUntil[kind] = endOfDay
                negativeStreak[kind] = 0
            }
        }
    }

    public func isSilenced(_ kind: ReminderKind, now: Date) -> Bool {
        (silencedUntil[kind] ?? .distantPast) > now
    }

    public var lastDelivery: Date? { deliveries.last }

    private mutating func pruneSnoozes(now: Date) {
        if snoozes.count > 200 {
            snoozes = snoozes.filter { $0.value.until == .distantFuture ? false : now.timeIntervalSince($0.value.until) < 86_400 }
        }
    }
}
