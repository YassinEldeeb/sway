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
    /// macOS lets Sway show notifications. When it doesn't, a "sent"
    /// reminder would be invisible, so reminders stay in the menu bar.
    public var systemNotificationsAllowed = true

    public init(micOrCameraInUseByOthers: Bool = false, fullScreenAppInFront: Bool = false, pausedUntil: Date? = nil, systemNotificationsAllowed: Bool = true) {
        self.micOrCameraInUseByOthers = micOrCameraInUseByOthers
        self.fullScreenAppInFront = fullScreenAppInFront
        self.pausedUntil = pausedUntil
        self.systemNotificationsAllowed = systemNotificationsAllowed
    }
}

public enum HoldReason: Equatable, Sendable {
    case paused(until: Date)
    case notificationsOff
    case systemNotificationsOff
    case quietHours
    case likelyInCall
    case fullScreen

    public var label: String {
        switch self {
        case .paused(let until): return "Paused until \(Clock.time(until))"
        case .notificationsOff: return "Notifications are off in Sway's settings"
        case .systemNotificationsOff: return "macOS isn't showing Sway's notifications (not allowed, or set to no banners), so reminders appear here only"
        case .quietHours: return "Quiet hours"
        case .likelyInCall: return "Held while another app uses the mic or camera"
        case .fullScreen: return "Held while a full-screen app is in front"
        }
    }

    /// After these end, Sway waits a little before speaking, so the end of a
    /// call doesn't bring a burst of reminders.
    public var settles: Bool { self != .notificationsOff && self != .systemNotificationsOff }
}

/// Why a due reminder wasn't sent this time. Every case has a plain label.
public enum Blocker: Equatable, Sendable {
    /// The reminder is only meant for the menu bar right now (for example a
    /// posture deviation that hasn't lasted long enough to notify).
    case menuOnly
    case alreadySent
    case silencedToday
    case cooldown(until: Date)
    case spacing(until: Date)
    case hourlyBudget(until: Date)
    case dailyBudget
    case settling(until: Date)
    /// A more important reminder was sent in the same evaluation.
    case anotherFirst
    /// The user has just moved back (`DueReminder.standby`).
    case standby

    public var label: String {
        switch self {
        case .menuOnly: return "Shown here only"
        case .alreadySent: return "Already sent; it stays here until it's no longer due"
        case .silencedToday: return "Dismissed several times today, so it stays in the menu bar until tomorrow"
        case .cooldown(let until): return "Sent recently; next possible at \(Clock.time(until))"
        case .spacing(let until): return "Another reminder went out recently; next possible at \(Clock.time(until))"
        case .hourlyBudget(let until): return "Hourly limit reached; next possible at \(Clock.time(until))"
        case .dailyBudget: return "Daily limit reached; shown in the menu bar only"
        case .settling(let until): return "Giving you a moment after a hold ends; next possible at \(Clock.time(until))"
        case .anotherFirst: return "A more important reminder went out first"
        case .standby: return "You've moved back; this clears in a few seconds if you stay there"
        }
    }
}

public enum ReminderState: Equatable, Sendable {
    case sent
    case held(HoldReason)
    case waiting(Blocker)

    public var label: String {
        switch self {
        case .sent: return "Sent as a notification"
        case .held(let h): return h.label
        case .waiting(let b): return b.label
        }
    }
}

extension ReminderStatus {
    /// The explanation shown under a reminder in the menu.
    public var explanation: String {
        if case .waiting(.menuOnly) = state, let note = reminder.note { return note }
        return state.label
    }
}

public struct ReminderStatus: Equatable, Sendable {
    public var reminder: DueReminder
    public var state: ReminderState

    public init(reminder: DueReminder, state: ReminderState) {
        self.reminder = reminder
        self.state = state
    }
}

public struct InterventionDecision: Equatable, Sendable {
    /// At most one notification per evaluation.
    public var deliver: DueReminder?
    /// Every visible due reminder, most important first, with why it was or
    /// wasn't sent. Answered and snoozed reminders are left out.
    public var statuses: [ReminderStatus]
    /// Why nothing could be delivered, when a context holds reminders.
    public var hold: HoldReason?
    /// Kinds whose notification on screen is no longer relevant (the break
    /// was taken, the position changed): remove them.
    public var expired: [ReminderKind]

    public init(deliver: DueReminder?, statuses: [ReminderStatus], hold: HoldReason?, expired: [ReminderKind] = []) {
        self.deliver = deliver
        self.statuses = statuses
        self.hold = hold
        self.expired = expired
    }

    public static let empty = InterventionDecision(deliver: nil, statuses: [], hold: nil)

    /// Due reminders not sent this time (menu bar only).
    public var passive: [DueReminder] { statuses.filter { $0.state != .sent }.map(\.reminder) }

    public func status(of instanceID: String) -> ReminderState? {
        statuses.first { $0.reminder.instanceID == instanceID }?.state
    }
}

/// Notification policy: deduplication, per-kind cooldowns, global spacing,
/// hourly/daily budgets, snooze limits, backing off after dismissals, a
/// short settling time after holds, and expiry of notifications that are no
/// longer relevant. Pure and deterministic: time is always passed in.
public struct InterventionEngine: Codable, Equatable, Sendable {
    struct Snooze: Codable, Equatable, Sendable {
        var until: Date
        var count: Int
    }

    struct Streak: Codable, Equatable, Sendable {
        var count: Int
        var at: Date
    }

    /// Delivery times (bounded to the last 24 h) for budgets and spacing.
    private(set) var deliveries: [Date] = []
    private(set) var lastDeliveredByKind: [ReminderKind: Date] = [:]
    /// Instances already notified; never notified again unless snoozed.
    private(set) var deliveredInstances: [String: Date] = [:]
    private var snoozes: [String: Snooze] = [:]
    /// Consecutive dismissals/"not helpful" per kind, reset by acceptance and
    /// at the start of each day.
    private var streaks: [ReminderKind: Streak] = [:]
    /// Kinds silenced (menu bar only) until the given time after repeated
    /// dismissals.
    private(set) var silencedUntil: [ReminderKind: Date] = [:]
    /// Instances the user already responded to (acted on, dismissed, marked
    /// not helpful). They leave the menu-bar card and count only once.
    private(set) var answeredInstances: [String: Date] = [:]
    /// The notification currently on screen per kind (they replace each
    /// other), so it can be removed once it's no longer relevant.
    public private(set) var posted: [ReminderKind: String] = [:]
    /// Last time a hold that settles was in effect.
    private(set) var heldAt: Date?

    public var deliveryTimes: [Date] { deliveries }

    public static let silenceAfterStreak = 3
    /// Quiet time after a call, full-screen app, pause or quiet hours ends.
    public static let settleAfterHold: TimeInterval = 3 * 60

    public init() {}

    enum CodingKeys: String, CodingKey {
        case deliveries, lastDeliveredByKind, deliveredInstances, snoozes, streaks, silencedUntil, answeredInstances, posted, heldAt
    }

    /// Tolerant: state saved by an older version (or a damaged file) keeps
    /// whatever it can instead of resetting everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deliveries = c.lenient([Date].self, .deliveries) ?? []
        lastDeliveredByKind = c.lenientMap(ReminderKind.self, Date.self, .lastDeliveredByKind) ?? [:]
        deliveredInstances = c.lenient([String: Date].self, .deliveredInstances) ?? [:]
        snoozes = c.lenient([String: Snooze].self, .snoozes) ?? [:]
        streaks = c.lenientMap(ReminderKind.self, Streak.self, .streaks) ?? [:]
        silencedUntil = c.lenientMap(ReminderKind.self, Date.self, .silencedUntil) ?? [:]
        answeredInstances = c.lenient([String: Date].self, .answeredInstances) ?? [:]
        posted = c.lenientMap(ReminderKind.self, String.self, .posted) ?? [:]
        heldAt = c.lenient(Date.self, .heldAt)
    }

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
        if !context.systemNotificationsAllowed { return .systemNotificationsOff }
        if settings.isQuietHours(at: now) { return .quietHours }
        if settings.holdDuringCalls, context.micOrCameraInUseByOthers { return .likelyInCall }
        if settings.holdDuringFullScreen, context.fullScreenAppInFront { return .fullScreen }
        return nil
    }

    /// What would happen now, without changing any state.
    public func decide(candidates: [DueReminder], now: Date, context: InterruptionContext, settings: CoachSettings, adjustments: Adjustments = .neutral) -> InterventionDecision {
        let sorted = candidates.sorted { $0.priority > $1.priority }
        let visible = sorted.filter { !isHidden($0, now: now) && (!$0.standby || posted[$0.kind] == $0.instanceID) }
        let expired = expiredKinds(candidates: candidates)
        if let hold = holdReason(now: now, context: context, settings: settings) {
            return InterventionDecision(deliver: nil, statuses: visible.map { ReminderStatus(reminder: $0, state: .held(hold)) }, hold: hold, expired: expired)
        }
        var statuses: [ReminderStatus] = []
        var chosen: DueReminder?
        for c in visible {
            var blocker = self.blocker(c, now: now, settings: settings, adjustments: adjustments)
            if blocker == nil, chosen != nil { blocker = .anotherFirst }
            if let blocker {
                statuses.append(ReminderStatus(reminder: c, state: .waiting(blocker)))
            } else {
                chosen = c
                statuses.append(ReminderStatus(reminder: c, state: .sent))
            }
        }
        // A new notification of the same kind replaces the stale one on
        // screen; clearing that kind as well could remove the new banner.
        return InterventionDecision(deliver: chosen, statuses: statuses, hold: nil, expired: expired.filter { $0 != chosen?.kind })
    }

    /// `decide`, then remember holds (for the settling time) and forget
    /// notifications that expired. The caller records a delivery with
    /// `recordDelivered` once it has posted it.
    public mutating func evaluate(candidates: [DueReminder], now: Date, context: InterruptionContext, settings: CoachSettings, adjustments: Adjustments = .neutral) -> InterventionDecision {
        let hold = holdReason(now: now, context: context, settings: settings)
        if hold?.settles == true { heldAt = now }
        let d = decide(candidates: candidates, now: now, context: context, settings: settings, adjustments: adjustments)
        for k in d.expired { posted[k] = nil }
        return d
    }

    /// A notification on screen is stale when its reminder is no longer due
    /// (break taken, position changed), was replaced by a newer occurrence,
    /// or has dropped back to the menu bar only.
    func expiredKinds(candidates: [DueReminder]) -> [ReminderKind] {
        posted.compactMap { kind, instance in
            let current = candidates.first { $0.instanceID == instance }
            return current == nil || current?.level == .menu ? kind : nil
        }
        .sorted { $0.rawValue < $1.rawValue }
    }

    /// Answered, or snoozed and not yet back.
    func isHidden(_ c: DueReminder, now: Date) -> Bool {
        if answeredInstances[c.instanceID] != nil { return true }
        // A snoozed reminder hides until it returns; once re-delivered
        // (marked .distantFuture) it shows again.
        if let s = snoozes[c.instanceID], s.until > now, s.until != .distantFuture { return true }
        return false
    }

    func streak(_ kind: ReminderKind, now: Date) -> Int {
        guard let s = streaks[kind], Calendar.current.isDate(s.at, inSameDayAs: now) else { return 0 }
        return s.count
    }

    /// Why `c` can't be notified now, or nil when it can.
    public func blocker(_ c: DueReminder, now: Date, settings: CoachSettings, adjustments: Adjustments = .neutral) -> Blocker? {
        if c.level == .menu { return .menuOnly }
        if c.standby { return .standby }
        let snooze = snoozes[c.instanceID]
        let returningFromSnooze = snooze != nil && snooze?.until != .distantFuture
        if deliveredInstances[c.instanceID] != nil, !returningFromSnooze { return .alreadySent }
        // Long sessions matter most: dismissals and budgets never silence
        // them; their growing cooldown and the spacing still apply.
        let important = c.kind == .longSession
        if !important, let until = silencedUntil[c.kind], until > now { return .silencedToday }
        if let h = heldAt, now.timeIntervalSince(h) < Self.settleAfterHold {
            return .settling(until: h.addingTimeInterval(Self.settleAfterHold))
        }
        if !returningFromSnooze, let last = lastDeliveredByKind[c.kind] {
            let factor = pow(2, Double(min(streak(c.kind, now: now), 2)))
            let cooldown = Self.cooldown(for: c.kind) * factor * adjustments.cooldownMultiplier(c.kind)
            if now.timeIntervalSince(last) < cooldown { return .cooldown(until: last.addingTimeInterval(cooldown)) }
        }
        if let lastAny = deliveries.last, now.timeIntervalSince(lastAny) < settings.minSpacingBetweenNotifications {
            return .spacing(until: lastAny.addingTimeInterval(settings.minSpacingBetweenNotifications))
        }
        if !important {
            let lastHour = deliveries.filter { now.timeIntervalSince($0) < 3600 }
            if lastHour.count >= settings.maxNotificationsPerHour, let first = lastHour.first {
                return .hourlyBudget(until: first.addingTimeInterval(3600))
            }
            let today = deliveries.filter { Calendar.current.isDate($0, inSameDayAs: now) }.count
            if today >= settings.maxNotificationsPerDay { return .dailyBudget }
        }
        return nil
    }

    /// Every notification was removed from screen (guided break, pause,
    /// deleted data).
    public mutating func forgetPosted() { posted = [:] }

    /// macOS refused the notification just recorded as posted: nothing of
    /// that kind is on screen any more.
    public mutating func forgetPosted(_ kind: ReminderKind) { posted[kind] = nil }

    public mutating func recordDelivered(_ r: DueReminder, at now: Date) {
        deliveries.append(now)
        deliveries.removeAll { now.timeIntervalSince($0) > 86_400 }
        lastDeliveredByKind[r.kind] = now
        deliveredInstances[r.instanceID] = now
        posted[r.kind] = r.instanceID
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

    /// Records a response. Responses to an instance that was already answered
    /// don't count again, so clicking "Dismiss" twice is one dismissal.
    public mutating func record(_ response: PromptResponse, kind: ReminderKind, instanceID: String? = nil, now: Date) {
        if let id = instanceID, response != .snoozed, response != .helpful {
            if answeredInstances[id] != nil { return }
            answeredInstances[id] = now
            if answeredInstances.count > 400 {
                answeredInstances = answeredInstances.filter { now.timeIntervalSince($0.value) < 86_400 * 2 }
            }
        }
        if posted[kind] == instanceID || instanceID == nil { posted[kind] = nil }
        switch response {
        case .accepted, .helpful:
            streaks[kind] = nil
            silencedUntil[kind] = nil
        case .snoozed:
            break
        case .dismissed, .unhelpful:
            let count = streak(kind, now: now) + (response == .unhelpful ? 2 : 1)
            streaks[kind] = Streak(count: count, at: now)
            // Long-session prompts are never silenced, so they keep their
            // growing cooldown instead of starting over.
            if count >= Self.silenceAfterStreak, kind != .longSession {
                // Back off to the menu bar for the rest of the day.
                // Next midnight, also on 23- and 25-hour daylight-saving days.
                let start = Calendar.current.startOfDay(for: now)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
                silencedUntil[kind] = endOfDay
                streaks[kind] = nil
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
