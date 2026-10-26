import Foundation
import SwayCore

// P0/P2: notification correctness. Each test names the defect it pins.

private func posture(_ issue: PostureIssue, since: Date, easing: Bool = false) -> ActiveIssue {
    ActiveIssue(issue: issue, since: since, easing: easing)
}

/// Engine + scheduler + posture candidates, evaluated the way AppModel does
/// every 5 s, with a record of what was posted and removed.
private struct Coach {
    var sim = Sim()
    var engine = InterventionEngine()
    var context = InterruptionContext()
    var active: [ActiveIssue] = []
    var setupIssues: Set<PostureIssue> = []
    var posted: [(Date, DueReminder)] = []
    var removed: [(Date, ReminderKind)] = []
    var log = DecisionLog()
    var last = InterventionDecision.empty

    mutating func evaluate() {
        var c = BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings)
        let breakDueAt = c.filter(\.kind.isBreak).map(\.dueAt).max()
        c += PostureReminders.candidates(active: active, setupIssues: setupIssues, breakDueAt: breakDueAt,
                                         nextBreakAt: BreakScheduler.next(now: sim.now, tracker: sim.tracker, settings: sim.settings)?.at,
                                         now: sim.now, settings: sim.settings)
        last = engine.evaluate(candidates: c, now: sim.now, context: context, settings: sim.settings)
        for k in last.expired { removed.append((sim.now, k)) }
        if let r = last.deliver {
            engine.recordDelivered(r, at: sim.now)
            posted.append((sim.now, r))
        }
        log.record(last, now: sim.now)
    }

    mutating func work(_ seconds: TimeInterval) {
        var left = seconds
        while left > 0 { sim.work(5); left -= 5; evaluate() }
    }

    mutating func idle(_ seconds: TimeInterval) {
        var left = seconds
        while left > 0 { sim.idle(5); left -= 5; evaluate() }
    }

    func count(_ k: ReminderKind) -> Int { posted.filter { $0.1.kind == k }.count }
}

let notificationTests: [TestCase] = [
    TestCase(name: "clicking a notification does the reminder's own main action") {
        expectEqual(NotificationRouting.route(.body, kind: .workstationReview).action, .openSetup, "setup suggestion opens setup, not a routine")
        expectEqual(NotificationRouting.route(.body, kind: .longBreak).action, .takeBreak)
        expectEqual(NotificationRouting.route(.body, kind: .longSession).action, .takeBreak)
        expectEqual(NotificationRouting.route(.body, kind: .microBreak).action, .startRoutine)
        expectEqual(NotificationRouting.route(.body, kind: .forwardLean).action, .startRoutine)
        expectEqual(NotificationRouting.route(.body, kind: .eyeRest).action, .startRoutine)
        expectEqual(NotificationRouting.route(.body, kind: .headDown).response, .accepted)
        expect(NotificationRouting.route(.dismissed, kind: .microBreak) == (nil, .dismissed))
        expect(NotificationRouting.route(.button(.notHelpful), kind: .microBreak) == (.notHelpful, .unhelpful))
        expect(NotificationRouting.route(.button(.snooze), kind: .headDown) == (.snooze, .snoozed))
        expect(NotificationRouting.route(.button(.openSetup), kind: .workstationReview) == (.openSetup, .accepted))
    },
    TestCase(name: "a recurring-pattern suggestion points at the matching setup item") {
        let r = PostureReminders.candidates(active: [], setupIssues: [.headDown], breakDueAt: nil, nextBreakAt: nil, now: t0, settings: CoachSettings())
        expectEqual(r.map(\.kind), [.workstationReview])
        expectEqual(r.first?.level, .setup)
        let issue = PostureReminders.setupIssue(of: r.first?.instanceID ?? "")
        expectEqual(issue, .headDown)
        expectEqual(issue.map(ReminderKind.setupItem(for:)), "monitor-height")
        expectEqual(PostureReminders.setupIssue(of: "micro@123"), nil)
        for issue in PostureIssue.allCases {
            let id = ReminderKind.setupItem(for: issue)
            expectEqual(WorkstationGuide.item(id)?.id, id, "\(issue) opens a setup item that exists")
        }
    },
    TestCase(name: "a posture notification is removed once the user has changed position") {
        var c = Coach()
        c.work(60)
        let since = c.sim.now
        c.active = [posture(.forwardLean, since: since)]
        c.work(8 * 60 + 10)
        expectEqual(c.count(.forwardLean), 1, "sent at about 8 min")
        // Sat back: the episode eases, then ends.
        c.active = [posture(.forwardLean, since: since, easing: true)]
        c.evaluate()
        expect(c.removed.contains { $0.1 == .forwardLean }, "removed as soon as the user moved back")
        c.active = []
        c.work(60)
        expectEqual(c.count(.forwardLean), 1)
        expect(c.engine.posted[.forwardLean] == nil)
    },
    TestCase(name: "a posture deviation the user already corrected never becomes a notification") {
        var c = Coach()
        c.work(60)
        let since = c.sim.now
        c.active = [posture(.forwardLean, since: since)]
        c.work(7 * 60 + 50)
        c.active = [posture(.forwardLean, since: since, easing: true)]   // moved back just before 8 min
        c.work(30)
        expectEqual(c.count(.forwardLean), 0)
        expect(!c.last.statuses.contains { $0.reminder.kind == .forwardLean }, "gone from the menu as soon as the user moved back")
    },
    TestCase(name: "a break reminder is removed when the user takes a real break, and not re-sent") {
        var c = Coach()
        c.work(25 * 60 + 10)
        expectEqual(c.count(.microBreak), 1)
        c.idle(3 * 60)
        expect(c.removed.contains { $0.1 == .microBreak }, "obsolete once the user is away")
        c.work(10 * 60)
        expectEqual(c.count(.microBreak), 1, "no stale reminder after the break")
    },
    TestCase(name: "a snoozed break reminder doesn't come back after a real break") {
        var c = Coach()
        c.work(25 * 60 + 10)
        let r = c.posted.last!.1
        c.engine.snooze(r.instanceID, kind: r.kind, now: c.sim.now, settings: c.sim.settings)
        c.engine.record(.snoozed, kind: r.kind, instanceID: r.instanceID, now: c.sim.now)
        c.idle(4 * 60)
        c.work(8 * 60)
        expectEqual(c.count(.microBreak), 1)
    },
    TestCase(name: "after a call ends, Sway waits, then sends one reminder, not a burst") {
        var c = Coach()
        c.context.micOrCameraInUseByOthers = true
        c.work(60 * 60)   // a one-hour call: a movement and a longer break became due
        expectEqual(c.posted.count, 0)
        expect(c.last.hold == .likelyInCall)
        c.context.micOrCameraInUseByOthers = false
        let ended = c.sim.now
        c.work(2 * 60 + 50)
        expectEqual(c.posted.count, 0, "settling time after the call")
        expect(c.last.statuses.contains { if case .waiting(.settling) = $0.state { return true } else { return false } })
        c.work(5 * 60)
        expectEqual(c.posted.count, 1, "then exactly one")
        expectEqual(c.posted.first?.1.kind, .longBreak, "the most important one")
        expect((c.posted.first?.0 ?? ended).timeIntervalSince(ended) >= InterventionEngine.settleAfterHold)
    },
    TestCase(name: "while macOS blocks notifications, nothing counts as sent and reminders stay in the menu") {
        var c = Coach()
        c.context.systemNotificationsAllowed = false
        c.work(26 * 60)
        expectEqual(c.posted.count, 0, "an invisible notification is never 'sent'")
        expectEqual(c.last.hold, .systemNotificationsOff)
        expectEqual(c.last.statuses.first?.reminder.kind, .microBreak, "still shown in the menu")
        c.context.systemNotificationsAllowed = true
        c.work(10)
        expectEqual(c.posted.count, 1, "allowed again: sent at once, no settling wait (the user was never in a call)")
    },
    TestCase(name: "every waiting reminder says why, with when it can go out") {
        var e = InterventionEngine()
        var s = CoachSettings()
        s.maxNotificationsPerHour = 2
        let a = reminder(.microBreak, "a", at: t0)
        e.recordDelivered(a, at: t0)
        let b = reminder(.headDown, "b", at: t0)
        expectEqual(e.blocker(b, now: t0 + 60, settings: s), .spacing(until: t0 + 8 * 60))
        e.recordDelivered(b, at: t0 + 9 * 60)
        let c = reminder(.forwardLean, "c", at: t0)
        expectEqual(e.blocker(c, now: t0 + 20 * 60, settings: s), .hourlyBudget(until: t0 + 3600))
        let a2 = reminder(.microBreak, "a2", at: t0)
        expectEqual(e.blocker(a2, now: t0 + 10 * 60, settings: s), .cooldown(until: t0 + 15 * 60))
        expectEqual(e.blocker(a, now: t0 + 70 * 60, settings: s), .alreadySent)
        let m = DueReminder(kind: .headDown, dueAt: t0, instanceID: "m", level: .menu, title: "", body: "", priority: 60, note: "why")
        expectEqual(e.blocker(m, now: t0 + 70 * 60, settings: s), .menuOnly)
        expect(Blocker.hourlyBudget(until: t0).label.hasPrefix("Hourly limit reached; next possible at"))
        expectEqual(ReminderStatus(reminder: m, state: .waiting(.menuOnly)).explanation, "why")
    },
    TestCase(name: "dismissals silence a reminder for the rest of the day only") {
        var e = InterventionEngine()
        let s = CoachSettings()
        for i in 0..<3 {
            let r = reminder(.headDown, "h\(i)", at: t0)
            e.recordDelivered(r, at: t0 + Double(i) * 1800)
            e.record(.dismissed, kind: .headDown, instanceID: r.instanceID, now: t0 + Double(i) * 1800)
        }
        let later = reminder(.headDown, "h9", at: t0)
        expectEqual(e.blocker(later, now: t0 + 3 * 3600, settings: s), .silencedToday)
        let tomorrow = t0 + 86_400
        expectEqual(e.blocker(later, now: tomorrow, settings: s), nil, "back the next day")
    },
    TestCase(name: "yesterday's dismissals don't lengthen today's cooldown") {
        var e = InterventionEngine()
        let s = CoachSettings()
        let r = reminder(.microBreak, "m1", at: t0)
        e.recordDelivered(r, at: t0)
        e.record(.dismissed, kind: .microBreak, instanceID: "m1", now: t0)
        e.record(.dismissed, kind: .microBreak, instanceID: "m1b", now: t0)
        let next = reminder(.microBreak, "m2", at: t0)
        expect(e.blocker(next, now: t0 + 20 * 60, settings: s) != nil, "4x cooldown today")
        let morning = Calendar.current.startOfDay(for: t0 + 86_400).addingTimeInterval(9 * 3600)
        var e2 = e
        e2.recordDelivered(reminder(.microBreak, "m3", at: morning), at: morning)
        expectEqual(e2.blocker(next, now: morning + 16 * 60, settings: s), nil, "normal 15 min cooldown the next day")
    },
    TestCase(name: "budgets and dismissals never block the long-session reminder") {
        var e = InterventionEngine()
        var s = CoachSettings()
        s.maxNotificationsPerHour = 1
        s.maxNotificationsPerDay = 1
        e.recordDelivered(reminder(.microBreak, "m", at: t0), at: t0)
        for i in 0..<5 { e.record(.dismissed, kind: .longSession, instanceID: "x\(i)", now: t0) }
        let ls = reminder(.longSession, "ls", at: t0, priority: 100)
        expectEqual(e.blocker(ls, now: t0 + 9 * 60, settings: s), nil)
        let other = reminder(.longBreak, "lb", at: t0, priority: 80)
        expectEqual(e.blocker(other, now: t0 + 9 * 60, settings: s), .hourlyBudget(until: t0 + 3600))
    },
    TestCase(name: "a posture reminder yields to a break that just fell due or is about to") {
        let s = CoachSettings()
        let a = posture(.headDown, since: t0)
        let at = t0 + 9 * 60
        expectEqual(PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: nil, nextBreakAt: nil, now: at, settings: s).first?.level, .notify)
        expectEqual(PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: at - 60, nextBreakAt: nil, now: at, settings: s).first?.level, .menu)
        expectEqual(PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: at - 6 * 60, nextBreakAt: nil, now: at, settings: s).first?.level, .notify,
                    "a break ignored for a while no longer holds posture back")
        expectEqual(PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: nil, nextBreakAt: at - 6 * 60, now: at, settings: s).first?.level, .notify,
                    "a next-break time already past doesn't either")
        expectEqual(PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: nil, nextBreakAt: at + 4 * 60, now: at, settings: s).first?.level, .menu)
        expectEqual(PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: nil, nextBreakAt: at + 20 * 60, now: at, settings: s).first?.level, .notify)
        let early = PostureReminders.candidates(active: [a], setupIssues: [], breakDueAt: nil, nextBreakAt: nil, now: t0 + 6 * 60, settings: s).first
        expectEqual(early?.level, .menu)
        expect(early?.note?.hasPrefix("A notification follows at") == true)
        let recurring = PostureReminders.candidates(active: [a], setupIssues: [.headDown], breakDueAt: nil, nextBreakAt: nil, now: at, settings: s)
        expectEqual(recurring.map(\.level), [.menu, .setup], "the setup suggestion speaks instead")
    },
    TestCase(name: "ignoring a break does not silence posture reminders") {
        var c = Coach()
        c.work(25 * 60 + 10)
        expectEqual(c.count(.microBreak), 1, "movement break sent at 25 min and ignored")
        c.active = [posture(.forwardLean, since: c.sim.now)]
        c.work(9 * 60)
        expectEqual(c.count(.forwardLean), 1, "the lean is notified while the ignored break is still due")
    },
    TestCase(name: "the decision log records changes once, with reasons") {
        var c = Coach()
        c.work(25 * 60 + 10)
        c.work(5 * 60)
        let micro = c.log.entries.filter { $0.kind == .microBreak }
        expectEqual(micro.filter { $0.text.contains("Sent as a notification") }.count, 1)
        expectEqual(micro.filter { $0.text.contains("Already sent") }.count, 1, "one line while it waits, not one per evaluation")
        c.context.fullScreenAppInFront = true
        c.work(60)
        c.context.fullScreenAppInFront = false
        c.work(60)
        expectEqual(c.log.entries.filter { $0.text.hasPrefix("Reminders held") }.count, 1)
        expectEqual(c.log.entries.filter { $0.text.hasPrefix("Hold ended") }.count, 1)
        c.idle(3 * 60)
        expect(c.log.entries.contains { $0.text.contains("notification removed because it no longer applies") })
        expect(c.log.entries.contains { $0.text.contains("no longer due") })
        var big = DecisionLog()
        for i in 0..<500 { big.note("n\(i)", kind: nil, at: t0) }
        expectEqual(big.entries.count, DecisionLog.maxEntries)
    },
    TestCase(name: "the menu shows the current reminder and drops answered ones") {
        var c = Coach()
        c.work(25 * 60 + 10)
        expectEqual(c.last.statuses.first?.reminder.kind, .microBreak)
        let r = c.posted.last!.1
        c.engine.record(.dismissed, kind: r.kind, instanceID: r.instanceID, now: c.sim.now)
        c.evaluate()
        expect(c.last.statuses.isEmpty, "answered: gone from the menu")
        expect(c.engine.posted[.microBreak] == nil)
    },
    TestCase(name: "notification responses still work after a relaunch") {
        var e = InterventionEngine()
        let r = reminder(.headDown, "h@1", at: t0)
        e.recordDelivered(r, at: t0)
        let data = try JSONEncoder().encode(e)
        var back = try JSONDecoder().decode(InterventionEngine.self, from: data)
        expectEqual(back.posted[.headDown], "h@1")
        back.snooze("h@1", kind: .headDown, now: t0 + 60, settings: CoachSettings())
        back.record(.snoozed, kind: .headDown, instanceID: "h@1", now: t0 + 60)
        expect(back.decide(candidates: [r], now: t0 + 2 * 60, context: .init(), settings: CoachSettings()).statuses.isEmpty, "snoozed and hidden")
        let returned = back.decide(candidates: [r], now: t0 + 12 * 60, context: .init(), settings: CoachSettings())
        expectEqual(returned.deliver?.instanceID, "h@1", "comes back after the snooze")
    },
]
