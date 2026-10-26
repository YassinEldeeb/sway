import Foundation
import SwayCore

// Each test pins a defect found in review (see PROGRESS.md, "Review fixes").

let regressionTests: [TestCase] = [
    TestCase(name: "an overnight absence closing in the morning keeps yesterday's saved record") {
        var saved: [String: DailyRecord] = [:]
        var yesterday = DailyRecord(day: "2026-03-02")
        yesterday.activeSeconds = 30_000
        yesterday.stretches = [3600, 5400]
        saved["2026-03-02"] = yesterday
        var ledger = Ledger(loader: { saved[$0] })
        // Morning: the stretch that ended last night is filed under yesterday.
        let lastNight = t0.addingTimeInterval(9 * 3600)   // 18:00 on 03-02
        ledger.apply([.sessionEnded(start: lastNight - 7200, end: lastNight)], calendar: utc)
        let r = ledger.records["2026-03-02"]
        expectEqual(r?.activeSeconds, 30_000, "yesterday's active time survives")
        expectEqual(r?.stretches.count, 3)
    },
    TestCase(name: "a guided break left over from a relaunch never retracts later work") {
        var sim = Sim()
        sim.work(10 * 60)
        let start = sim.now
        sim.tracker.beginGuidedBreak(at: start, until: start + 180)
        // Relaunch mid-break: nothing finishes it. The user keeps working.
        sim.work(2 * 3600)
        sim.idle(6 * 60)
        sim.work(60)
        expectEqual(sim.breaks.count, 1)
        expectEqual(sim.breaks.first?.source, .away, "not the stale guided break")
        expect((sim.breaks.first?.start ?? start) > start + 3600, "break starts when the user left")
        expectClose(sim.today.activeSeconds, (10 + 120 + 1) * 60, tolerance: 10)
    },
    TestCase(name: "a late timer while awake and typing is work, not a break") {
        var sim = Sim()
        sim.work(10 * 60)
        sim.now += 150
        sim.lastInput = sim.now - 1
        let e = sim.tracker.tick(now: sim.now, idleSeconds: 1, settings: sim.settings, sleptDuringGap: 0)
        sim.ledger.apply(e, calendar: utc)
        expect(e.allSatisfy { if case .breakTaken = $0 { return false } else { return true } })
        expectClose(sim.ledger.records["2026-03-02"]?.activeSeconds ?? 0, 12.5 * 60, tolerance: 2)
        // The same gap with the Mac asleep is a break.
        sim.now += 600
        sim.lastInput = sim.now - 1
        let e2 = sim.tracker.tick(now: sim.now, idleSeconds: 1, settings: sim.settings, sleptDuringGap: 590)
        expect(e2.contains { if case .breakTaken = $0 { return true } else { return false } })
    },
    TestCase(name: "dismissing long-session prompts keeps their growing cooldown") {
        var e = InterventionEngine()
        let s = CoachSettings()
        var last = t0
        for i in 0..<4 {
            let r = reminder(.longSession, "ls#\(i)", at: last, priority: 100)
            e.recordDelivered(r, at: last)
            e.record(.dismissed, kind: .longSession, instanceID: r.instanceID, now: last)
            last += 90 * 60
        }
        let next = reminder(.longSession, "ls#9", at: last, priority: 100)
        let delivered = last - 90 * 60
        expect(e.decide(candidates: [next], now: delivered + 30 * 60, context: .init(), settings: s).deliver == nil, "still backed off at 30 min")
        expect(e.decide(candidates: [next], now: delivered + 81 * 60, context: .init(), settings: s).deliver != nil, "4x cooldown, then allowed")
    },
    TestCase(name: "menu-card responses hide the card and count once per reminder") {
        var e = InterventionEngine()
        let s = CoachSettings()
        let r = reminder(.microBreak, "micro@1", at: t0)
        for _ in 0..<3 { e.record(.dismissed, kind: .microBreak, instanceID: r.instanceID, now: t0) }
        expect(!e.isSilenced(.microBreak, now: t0), "three clicks on one card are one dismissal")
        let d = e.decide(candidates: [r], now: t0, context: .init(), settings: s)
        expect(d.deliver == nil && d.passive.isEmpty, "answered reminder leaves the menu")
        // Snoozed from the menu: hidden until it comes back, then shown again.
        let m = reminder(.microBreak, "micro@2", at: t0)
        e.snooze("micro@2", kind: .microBreak, now: t0, settings: s)
        expect(e.decide(candidates: [m], now: t0 + 60, context: .init(), settings: s).passive.isEmpty)
        let back = e.decide(candidates: [m], now: t0 + 11 * 60, context: .init(), settings: s)
        expect(back.deliver != nil || !back.passive.isEmpty)
    },
    TestCase(name: "a guided break taken at the desk is not also counted as work") {
        var sim = Sim()
        sim.work(55 * 60)
        let before = sim.today.activeSeconds
        sim.tracker.beginGuidedBreak(at: sim.now, until: sim.now + 180)
        sim.idle(100)
        sim.work(80)
        let e = sim.tracker.finishGuidedBreak(at: sim.now, idleFraction: 0.7)
        sim.ledger.apply(e, calendar: utc)
        expectClose(sim.today.activeSeconds, before, tolerance: 1)
    },
    TestCase(name: "a tiny or upward look-down reference is rejected") {
        var s = Synth()
        let base = s.baselineSamples()
        for drop in [0.125, -0.6] {
            let ld = (0..<5).map { _ in s.obs(drop: drop) }
            guard case .success(let c) = CalibrationBuilder.build(samples: base, lookDown: ld, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0) else { return expect(false) }
            expect(c.lookDown == nil, "drop \(drop) rejected")
            expect(c.report.warnings.contains { $0.contains("cautious default") })
        }
    },
    TestCase(name: "a small accepted reference can't make head-down hypersensitive") {
        var s = Synth()
        let base = s.baselineSamples()
        let ld = (0..<5).map { _ in s.obs(drop: 0.16) }
        guard case .success(let c) = CalibrationBuilder.build(samples: base, lookDown: ld, cameraID: "cam-1", cameraName: "", minConfidence: 0.6, now: t0) else { return expect(false) }
        expect(c.lookDown != nil)
        var run = PostureRun()
        run.engine.configure(calibration: c, cameraID: "cam-1", settings: run.settings)
        run.feed(8 * 60) { $0.obs(drop: 0.1) }
        expect(!run.startedIssues().contains(.headDown), "about 2 cm lower is normal variation")
    },
    TestCase(name: "the clock stepping backwards doesn't credit time twice") {
        var sim = Sim()
        sim.work(10 * 60)
        sim.now -= 30        // small correction
        sim.lastInput = sim.now
        sim.tick()
        sim.work(60)
        expectClose(sim.today.activeSeconds, 10.5 * 60, tolerance: 6)
    },
]
