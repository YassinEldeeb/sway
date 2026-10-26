import Foundation
import SwayCore

func reminder(_ kind: ReminderKind, _ id: String, at: Date, priority: Int = 50) -> DueReminder {
    DueReminder(kind: kind, dueAt: at, instanceID: id, level: .actionable, title: kind.title, body: "", priority: priority)
}

/// Runs the full loop (tracker → scheduler → policy) the way the app does,
/// with a response callback for each delivered notification.
struct Loop {
    var sim: Sim
    var engine = InterventionEngine()
    var context = InterruptionContext()
    var delivered: [(Date, DueReminder)] = []

    init(settings: CoachSettings = CoachSettings()) {
        sim = Sim(settings: settings)
    }

    mutating func evaluate(respond: (DueReminder) -> PromptResponse?) {
        let due = BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings)
        let decision = engine.decide(candidates: due, now: sim.now, context: context, settings: sim.settings)
        if let r = decision.deliver {
            engine.recordDelivered(r, at: sim.now)
            delivered.append((sim.now, r))
            if let response = respond(r) {
                if response == .snoozed {
                    engine.snooze(r.instanceID, kind: r.kind, now: sim.now, settings: sim.settings)
                }
                engine.record(response, kind: r.kind, now: sim.now)
            }
        }
    }

    /// Work for `seconds`, evaluating every 5 s like the app's timer.
    mutating func work(_ seconds: TimeInterval, respond: (DueReminder) -> PromptResponse? = { _ in nil }) {
        var left = seconds
        while left > 0 {
            sim.work(5)
            left -= 5
            evaluate(respond: respond)
        }
    }

    func count(_ kind: ReminderKind) -> Int { delivered.filter { $0.1.kind == kind }.count }
}

let schedulingTests: [TestCase] = [
    TestCase(name: "micro break is due after 25 minutes, not before") {
        var sim = Sim()
        sim.work(24 * 60)
        expect(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).isEmpty)
        sim.work(61)
        let due = BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings)
        expectEqual(due.map(\.kind), [.microBreak])
    },
    TestCase(name: "a natural break resets the movement timer") {
        var sim = Sim()
        sim.work(20 * 60)
        sim.idle(3 * 60)
        sim.work(20 * 60)
        expect(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).isEmpty, "only 20 min since the break")
        sim.work(6 * 60)
        expectEqual(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).map(\.kind), [.microBreak])
    },
    TestCase(name: "long break replaces the micro break, and micro yields when long is close") {
        var sim = Sim()
        sim.work(26 * 60)
        _ = sim.tracker.completeRoutine(start: sim.now - 60, end: sim.now)
        sim.work(24 * 60)   // 50 min since start, 24 since routine
        sim.work(2 * 60)    // micro would be due at 51 but long is due at 55
        let due = BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings)
        expect(due.isEmpty, "micro yields to the imminent long break: \(due.map(\.kind))")
        sim.work(4 * 60)
        expectEqual(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).map(\.kind), [.longBreak])
    },
    TestCase(name: "nothing is due while the user is away") {
        var sim = Sim()
        sim.work(60 * 60)
        sim.idle(3 * 60)
        expect(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).isEmpty)
    },
    TestCase(name: "eye rest is off by default and works when enabled") {
        var s = CoachSettings()
        var sim = Sim(settings: s)
        sim.work(20 * 60 + 5)
        expect(!BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).contains { $0.kind == .eyeRest })
        s.eyeRestEnabled = true
        s.microBreakInterval = 40 * 60
        sim = Sim(settings: s)
        sim.work(20 * 60 + 5)
        expectEqual(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).map(\.kind), [.eyeRest])
        sim.tracker.acknowledgeEyeRest(at: sim.now)
        expect(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).isEmpty)
    },
    TestCase(name: "the next break is reported for the countdown") {
        var sim = Sim()
        sim.work(10 * 60)
        let next = BreakScheduler.next(now: sim.now, tracker: sim.tracker, settings: sim.settings)
        expectEqual(next?.kind, .microBreak)
        expectClose(next?.at.timeIntervalSince(sim.now) ?? 0, 15 * 60, tolerance: 6)
    },
    TestCase(name: "the countdown agrees with what is due when a micro break yields") {
        var sim = Sim()
        sim.work(47 * 60)   // micro passed at 25, but the long break is 8 min away
        expect(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings).isEmpty)
        let next = BreakScheduler.next(now: sim.now, tracker: sim.tracker, settings: sim.settings)
        expectEqual(next?.kind, .longBreak)
        expectClose(next?.at.timeIntervalSince(sim.now) ?? 0, 8 * 60, tolerance: 6)
    },
    TestCase(name: "four hours of continuous work: escalates, but stays within budget") {
        var loop = Loop()
        loop.work(4 * 3600) { _ in .dismissed }
        expect(loop.count(.longSession) >= 1, "long session prompt delivered")
        expect(loop.delivered.count <= 12, "at most 3/hour: \(loop.delivered.count)")
        for (i, d) in loop.delivered.enumerated() where i > 0 {
            expect(d.0.timeIntervalSince(loop.delivered[i - 1].0) >= loop.sim.settings.minSpacingBetweenNotifications - 0.1)
        }
        let ids = loop.delivered.map(\.1.instanceID)
        expectEqual(Set(ids).count, ids.count, "no instance delivered twice")
    },
    TestCase(name: "repeatedly dismissing the same reminder backs off to the menu bar") {
        var settings = CoachSettings()
        settings.microBreakInterval = 10 * 60
        settings.longBreakInterval = 300 * 60
        settings.longSessionThreshold = 600 * 60
        var loop = Loop(settings: settings)
        // A short routine every 12 min starts a new micro-break instance each time.
        for _ in 0..<16 {
            loop.work(12 * 60) { _ in .dismissed }
            _ = loop.sim.tracker.completeRoutine(start: loop.sim.now - 30, end: loop.sim.now)
        }
        expectEqual(loop.count(.microBreak), InterventionEngine.silenceAfterStreak, "silenced after \(InterventionEngine.silenceAfterStreak) dismissals")
        expect(loop.engine.isSilenced(.microBreak, now: loop.sim.now))
    },
    TestCase(name: "accepting a reminder resets the dismissal streak") {
        var e = InterventionEngine()
        e.record(.dismissed, kind: .microBreak, now: t0)
        e.record(.dismissed, kind: .microBreak, now: t0)
        e.record(.accepted, kind: .microBreak, now: t0)
        e.record(.dismissed, kind: .microBreak, now: t0)
        expect(!e.isSilenced(.microBreak, now: t0))
    },
    TestCase(name: "same instance is never delivered twice") {
        var e = InterventionEngine()
        let s = CoachSettings()
        let r = reminder(.microBreak, "micro@1", at: t0)
        let d1 = e.decide(candidates: [r], now: t0, context: .init(), settings: s)
        expectEqual(d1.deliver?.instanceID, "micro@1")
        e.recordDelivered(r, at: t0)
        let d2 = e.decide(candidates: [r], now: t0 + 3600, context: .init(), settings: s)
        expect(d2.deliver == nil)
        expectEqual(d2.passive.count, 1, "still shown passively")
    },
    TestCase(name: "per-kind cooldown and global spacing") {
        var e = InterventionEngine()
        let s = CoachSettings()
        e.recordDelivered(reminder(.microBreak, "a", at: t0), at: t0)
        expect(e.decide(candidates: [reminder(.microBreak, "b", at: t0)], now: t0 + 10 * 60, context: .init(), settings: s).deliver == nil, "kind cooldown")
        expect(e.decide(candidates: [reminder(.eyeRest, "c", at: t0)], now: t0 + 5 * 60, context: .init(), settings: s).deliver == nil, "global spacing")
        expect(e.decide(candidates: [reminder(.eyeRest, "c", at: t0)], now: t0 + 9 * 60, context: .init(), settings: s).deliver != nil)
        expect(e.decide(candidates: [reminder(.microBreak, "b", at: t0)], now: t0 + 16 * 60, context: .init(), settings: s).deliver != nil)
    },
    TestCase(name: "hourly and daily budgets") {
        var e = InterventionEngine()
        var s = CoachSettings()
        s.minSpacingBetweenNotifications = 60
        let kinds: [ReminderKind] = [.microBreak, .eyeRest, .headDown, .forwardLean, .lateralTilt]
        var delivered = 0
        for i in 0..<5 {
            let now = t0 + Double(i) * 120
            let r = reminder(kinds[i], "k\(i)", at: now)
            if e.decide(candidates: [r], now: now, context: .init(), settings: s).deliver != nil {
                e.recordDelivered(r, at: now)
                delivered += 1
            }
        }
        expectEqual(delivered, s.maxNotificationsPerHour)
        s.maxNotificationsPerDay = 3
        let later = t0 + 2 * 3600
        expect(e.decide(candidates: [reminder(.staticPosture, "z", at: later)], now: later, context: .init(), settings: s).deliver == nil, "daily budget")
    },
    TestCase(name: "calls, full screen, pause and quiet hours hold notifications") {
        let e = InterventionEngine()
        var s = CoachSettings()
        let r = [reminder(.longBreak, "l", at: t0)]
        let call = e.decide(candidates: r, now: t0, context: .init(micOrCameraInUseByOthers: true), settings: s)
        expectEqual(call.hold, .likelyInCall)
        expect(call.deliver == nil)
        expectEqual(call.passive.count, 1)
        expectEqual(e.decide(candidates: r, now: t0, context: .init(fullScreenAppInFront: true), settings: s).hold, .fullScreen)
        expectEqual(e.decide(candidates: r, now: t0, context: .init(pausedUntil: t0 + 60), settings: s).hold, .paused(until: t0 + 60))
        expect(e.decide(candidates: r, now: t0 + 61, context: .init(pausedUntil: t0 + 60), settings: s).deliver != nil, "pause expires")
        s.holdDuringCalls = false
        expect(e.decide(candidates: r, now: t0, context: .init(micOrCameraInUseByOthers: true), settings: s).deliver != nil, "user turned the call hold off")
        s.quietHoursEnabled = true
        s.quietHoursStartMinute = 8 * 60
        s.quietHoursEndMinute = 10 * 60
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: t0)!
        expectEqual(e.decide(candidates: r, now: nine, context: .init(), settings: s).hold, .quietHours)
    },
    TestCase(name: "snooze delays, re-delivers once, and is limited") {
        var e = InterventionEngine()
        let s = CoachSettings()
        let r = reminder(.microBreak, "m", at: t0)
        e.recordDelivered(r, at: t0)
        expect(e.snooze("m", kind: .microBreak, now: t0, settings: s))
        expect(e.decide(candidates: [r], now: t0 + 5 * 60, context: .init(), settings: s).deliver == nil, "snoozed")
        expect(e.decide(candidates: [r], now: t0 + 10 * 60 + 1, context: .init(), settings: s).deliver != nil, "back after snooze")
        e.recordDelivered(r, at: t0 + 601)
        expect(e.decide(candidates: [r], now: t0 + 30 * 60, context: .init(), settings: s).deliver == nil, "not again without another snooze")
        expect(e.snooze("m", kind: .microBreak, now: t0 + 601, settings: s))
        expect(!e.canSnooze("m", settings: s))
        expect(!e.snooze("m", kind: .microBreak, now: t0 + 700, settings: s), "limit reached")
    },
    TestCase(name: "long-session prompts are never silenced by dismissals") {
        var e = InterventionEngine()
        for _ in 0..<4 { e.record(.dismissed, kind: .longSession, now: t0) }
        let r = reminder(.longSession, "ls", at: t0, priority: 100)
        expect(e.decide(candidates: [r], now: t0, context: .init(), settings: CoachSettings()).deliver != nil)
    },
    TestCase(name: "personalization needs evidence and is bounded") {
        var few = ResponseCounts()
        few.prompts = 2
        few.dismissed = 2
        expect(Personalization.compute(counts: [.microBreak: few]).intervalMultipliers.isEmpty)
        var many = ResponseCounts()
        many.prompts = 10
        many.dismissed = 10
        let adj = Personalization.compute(counts: [.microBreak: many])
        expectClose(adj.intervalMultiplier(.microBreak), 1.5, tolerance: 0.001)
        expect(!adj.explanations.isEmpty)
        var posture = ResponseCounts()
        posture.prompts = 6
        posture.unhelpful = 3
        let p = Personalization.compute(counts: [.headDown: posture])
        expectClose(p.thresholdScale(.headDown), 1.45, tolerance: 0.001)
        var lots = ResponseCounts()
        lots.prompts = 30
        lots.unhelpful = 30
        expectClose(Personalization.compute(counts: [.forwardLean: lots]).thresholdScale(.forwardLean), 1.6, tolerance: 0.001)
        var good = ResponseCounts()
        good.prompts = 10
        good.accepted = 8
        good.dismissed = 2
        expect(Personalization.compute(counts: [.microBreak: good]).intervalMultipliers.isEmpty, "accepted reminders keep their timing")
    },
    TestCase(name: "personalized intervals move the schedule") {
        var sim = Sim()
        sim.work(26 * 60)
        var adj = Adjustments()
        adj.intervalMultipliers[.microBreak] = 1.2
        expect(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings, adjustments: adj).isEmpty)
        sim.work(5 * 60)
        expectEqual(BreakScheduler.due(now: sim.now, tracker: sim.tracker, settings: sim.settings, adjustments: adj).map(\.kind), [.microBreak])
    },
]
