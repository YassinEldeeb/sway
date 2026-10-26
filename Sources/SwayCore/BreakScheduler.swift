import Foundation

/// A reminder that is due now. `instanceID` identifies this particular
/// occurrence (e.g. "the micro break owed since 10:05"), which is what
/// deduplication and snoozing key on.
public struct DueReminder: Equatable, Sendable {
    public var kind: ReminderKind
    public var dueAt: Date
    public var instanceID: String
    public var level: InterventionLevel
    public var title: String
    public var body: String
    /// Higher wins when several are due at once.
    public var priority: Int
    /// For a menu-only reminder: why it isn't a notification (yet).
    public var note: String?

    public init(kind: ReminderKind, dueAt: Date, instanceID: String, level: InterventionLevel, title: String, body: String, priority: Int, note: String? = nil) {
        self.kind = kind
        self.dueAt = dueAt
        self.instanceID = instanceID
        self.level = level
        self.title = title
        self.body = body
        self.priority = priority
        self.note = note
    }
}

public struct UpcomingBreak: Equatable, Sendable {
    public var kind: ReminderKind
    public var at: Date
}

/// Decides which break reminders are owed, from the tracker's state alone.
/// Whether a due reminder actually becomes a notification is the
/// `InterventionEngine`'s decision.
public enum BreakScheduler {
    /// A micro break is skipped when a long break is due within this window.
    static let microYieldWindow: TimeInterval = 10 * 60
    /// An eye-rest reminder is skipped when a movement break is this close.
    static let eyeYieldWindow: TimeInterval = 3 * 60
    /// After the long-session threshold, re-offer at most this often.
    static let longSessionRepeat: TimeInterval = 30 * 60

    public static func due(now: Date, tracker: ActivityTracker, settings: CoachSettings, adjustments: Adjustments = .neutral) -> [DueReminder] {
        guard tracker.isActive else { return [] }
        var out: [DueReminder] = []
        let longRef = tracker.lastLongBreak(fallback: now)
        let moveRef = tracker.lastMovement(fallback: now)
        let sinceLong = now.timeIntervalSince(longRef)
        let longInterval = settings.longBreakInterval * adjustments.intervalMultiplier(.longBreak)
        let longDueAt = longRef.addingTimeInterval(longInterval)
        let longDue = now >= longDueAt

        if sinceLong >= settings.longSessionThreshold {
            let over = sinceLong - settings.longSessionThreshold
            let bucket = Int(over / longSessionRepeat)
            let dueAt = longRef.addingTimeInterval(settings.longSessionThreshold + Double(bucket) * longSessionRepeat)
            out.append(DueReminder(
                kind: .longSession, dueAt: dueAt,
                instanceID: "longSession@\(stamp(longRef))#\(bucket)",
                level: .notify,
                title: "You've been at it for \(Format.duration(sinceLong))",
                body: "That's an unusually long stretch without a real break. A few minutes away from the desk — a short walk, water, daylight — is a good reset.",
                priority: 100))
        } else if longDue {
            out.append(DueReminder(
                kind: .longBreak, dueAt: longDueAt,
                instanceID: "longBreak@\(stamp(longRef))",
                level: .notify,
                title: "Time for a longer break",
                body: "You've been working continuously for \(Format.duration(sinceLong)). A short walk could help.",
                priority: 80))
        }

        let microInterval = settings.microBreakInterval * adjustments.intervalMultiplier(.microBreak)
        let microDueAt = moveRef.addingTimeInterval(microInterval)
        let longSoon = longDueAt.timeIntervalSince(now) < microYieldWindow
        if now >= microDueAt, !longDue, !longSoon, sinceLong < settings.longSessionThreshold {
            out.append(DueReminder(
                kind: .microBreak, dueAt: microDueAt,
                instanceID: "micro@\(stamp(moveRef))",
                level: .notify,
                title: "Quick movement break",
                body: "\(Format.duration(now.timeIntervalSince(moveRef))) since you last moved away. Stand up, roll your shoulders, or try a 1-minute routine.",
                priority: 50))
        }

        if settings.eyeRestEnabled {
            let eyeRef = [tracker.lastEyeRestAt, moveRef].compactMap { $0 }.max() ?? now
            let eyeDueAt = eyeRef.addingTimeInterval(settings.eyeRestInterval)
            let movementSoon = microDueAt.timeIntervalSince(now) < eyeYieldWindow || longDueAt.timeIntervalSince(now) < eyeYieldWindow
            if now >= eyeDueAt, out.isEmpty, !movementSoon {
                out.append(DueReminder(
                    kind: .eyeRest, dueAt: eyeDueAt,
                    instanceID: "eye@\(stamp(eyeRef))",
                    level: .notify,
                    title: "Rest your eyes",
                    body: "Look at something about 6 metres (20 feet) away for 20 seconds, and blink a few times.",
                    priority: 20))
            }
        }
        return out.sorted { $0.priority > $1.priority }
    }

    /// The next break reminder that will come due, for "next movement in 8 min".
    public static func next(now: Date, tracker: ActivityTracker, settings: CoachSettings, adjustments: Adjustments = .neutral) -> UpcomingBreak? {
        guard tracker.isActive else { return nil }
        let longRef = tracker.lastLongBreak(fallback: now)
        let moveRef = tracker.lastMovement(fallback: now)
        let longAt = longRef.addingTimeInterval(settings.longBreakInterval * adjustments.intervalMultiplier(.longBreak))
        let microAt = moveRef.addingTimeInterval(settings.microBreakInterval * adjustments.intervalMultiplier(.microBreak))
        // Mirror `due`: a movement break that would land within the yield
        // window of the longer break is folded into it.
        if microAt < longAt, longAt.timeIntervalSince(max(microAt, now)) >= microYieldWindow {
            return UpcomingBreak(kind: .microBreak, at: microAt)
        }
        return UpcomingBreak(kind: .longBreak, at: longAt)
    }

    static func stamp(_ d: Date) -> String { String(Int(d.timeIntervalSince1970)) }
}

public enum Format {
    public static func duration(_ t: TimeInterval) -> String {
        let minutes = Int((max(0, t) / 60).rounded(.down))
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    public static func short(_ t: TimeInterval) -> String {
        let minutes = Int((max(0, t) / 60).rounded(.down))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
}
