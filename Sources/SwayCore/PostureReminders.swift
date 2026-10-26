import Foundation

/// Turns sustained posture episodes and recurring issues into reminder
/// candidates for the `InterventionEngine`.
public enum PostureReminders {
    /// A posture reminder stays in the menu bar while a movement break is
    /// due or this close: the break covers it, and one reminder is enough.
    public static let yieldToBreak: TimeInterval = 5 * 60

    /// - `active`: sustained episodes now (empty when the camera isn't
    ///   tracking reliably or the calibration looks out of date).
    /// - `setupIssues`: issues that keep recurring today; they get a
    ///   once-a-day workstation suggestion instead of repeated reminders.
    /// - `breakDueAt`: when the break that is due now became due, from
    ///   `BreakScheduler` (nil when none is due); `nextBreakAt`: the next one.
    ///
    /// A posture reminder gives way only around a break's own moment, from
    /// 5 min before it until 5 min after it fell due. An ignored break stays
    /// due until a break is taken, so yielding to "a break is due" alone
    /// would silence posture reminders for as long as breaks are ignored.
    ///
    /// With short break intervals the window shrinks (a fifth of the
    /// movement-break interval), so a break is never always "soon".
    public static func candidates(active: [ActiveIssue], setupIssues: Set<PostureIssue>, breakDueAt: Date?, nextBreakAt: Date?, now: Date, settings: CoachSettings) -> [DueReminder] {
        var out: [DueReminder] = []
        let window = min(yieldToBreak, settings.microBreakInterval / 5)
        let breakSoon = (breakDueAt.map { now.timeIntervalSince($0) < window } ?? false)
            || (nextBreakAt.map { $0 > now && $0.timeIntervalSince(now) < window } ?? false)
        for a in active {
            let t = settings.thresholds(for: a.issue)
            let detectedAt = a.since.addingTimeInterval(t.minDuration)
            let notifyAt = detectedAt.addingTimeInterval(settings.postureNotifyAfter)
            // Menu bar only while it's new, while the user has already moved
            // back (it's about to end), when a break is about to cover it, or
            // when it keeps recurring (the setup suggestion speaks instead).
            // Little movement is always worth a nudge to move, so a pattern
            // of it adds the setup suggestion without demoting the reminder.
            let demoted = setupIssues.contains(a.issue) && a.issue != .staticPosture
            let note: String?
            if demoted {
                note = "This keeps coming back today, so Sway suggests a setup change instead of repeating it."
            } else if breakSoon {
                note = "A break is due soon and covers this."
            } else if now < notifyAt {
                note = "A notification follows at \(Clock.time(notifyAt)) if this continues."
            } else {
                note = nil
            }
            let text = Self.text(a.issue, lasting: now.timeIntervalSince(a.since))
            var r = DueReminder(kind: ReminderKind(a.issue), dueAt: detectedAt, instanceID: "\(a.issue.rawValue)@\(Int(a.since.timeIntervalSince1970))",
                                level: note == nil ? .notify : .menu, title: text.title, body: text.body, priority: 60, note: note)
            // Once the user has moved back, nothing new is sent or shown; a
            // notification already on screen goes when the episode ends.
            r.standby = a.easing
            out.append(r)
        }
        for issue in setupIssues.sorted(by: { $0.rawValue < $1.rawValue }) {
            out.append(DueReminder(kind: .workstationReview, dueAt: now, instanceID: "review-\(issue.rawValue)-\(DayKey.key(now))",
                                   level: .setup, title: "\(issue.title) keeps coming back", body: PatternDetector.advice(for: issue), priority: 30))
        }
        return out
    }

    /// The issue a workstation suggestion is about, from its instance id.
    public static func setupIssue(of instanceID: String) -> PostureIssue? {
        let parts = instanceID.split(separator: "-")
        guard parts.count >= 2, parts[0] == "review" else { return nil }
        return PostureIssue(rawValue: String(parts[1]))
    }

    public static func text(_ issue: PostureIssue, lasting: TimeInterval) -> (title: String, body: String) {
        let d = Format.duration(lasting)
        switch issue {
        case .headDown:
            return ("Your head has been tilted downward for a while", "About \(d). Try changing position: sit back and bring your gaze up. If this happens a lot, the screen may be too low.")
        case .forwardLean:
            return ("You've been leaning toward the screen", "About \(d). Sit back against your chair; if text is hard to read, enlarge it (⌘+) instead of moving closer.")
        case .lateralTilt:
            return ("Your head has been tilted to one side", "About \(d). Re-centre your head, and check whether what you're looking at sits off to one side.")
        case .shoulderAsymmetry:
            return ("One shoulder has been raised for a while", "About \(d). Let both shoulders drop. Check the mouse isn't too far out or too high.")
        case .staticPosture:
            return ("Your neck position has stayed very still", "About \(d) with little movement. Try a comfortable movement break — roll your shoulders, look around, or stand for a minute.")
        }
    }
}

/// How a click on a notification maps to an action and a response.
public enum NotificationTap: Equatable, Sendable {
    /// The notification itself was clicked.
    case body
    /// Closed with its close control.
    case dismissed
    case button(CoachAction)
}

public enum NotificationRouting {
    public static func route(_ tap: NotificationTap, kind: ReminderKind) -> (action: CoachAction?, response: PromptResponse) {
        switch tap {
        case .body: return (kind.primaryAction, .accepted)
        case .dismissed: return (nil, .dismissed)
        case .button(let a):
            switch a {
            case .snooze: return (a, .snoozed)
            case .notHelpful: return (a, .unhelpful)
            case .startRoutine, .takeBreak, .recalibrate, .eyeDone, .openSetup: return (a, .accepted)
            }
        }
    }
}
