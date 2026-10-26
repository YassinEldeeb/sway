import Foundation
import SwayCore

let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-03-02 09:00:00 UTC
let t0 = Date(timeIntervalSince1970: 1_772_442_000)

/// Drives the tracker the way the app does: a tick every few seconds with
/// the system idle time.
struct Sim {
    var tracker = ActivityTracker()
    var ledger = Ledger()
    var settings = CoachSettings()
    var now: Date
    var lastInput: Date
    var events: [ActivityEvent] = []

    init(start: Date = t0, settings: CoachSettings = CoachSettings()) {
        now = start
        lastInput = start
        self.settings = settings
        tick()
    }

    mutating func tick() {
        let e = tracker.tick(now: now, idleSeconds: now.timeIntervalSince(lastInput), settings: settings)
        events += e
        ledger.apply(e, calendar: utc)
    }

    mutating func work(_ seconds: TimeInterval, step: TimeInterval = 5) {
        var left = seconds
        while left > 0 {
            let s = min(step, left)
            now += s
            lastInput = now - 0.5
            tick()
            left -= s
        }
    }

    mutating func idle(_ seconds: TimeInterval, step: TimeInterval = 5) {
        var left = seconds
        while left > 0 {
            let s = min(step, left)
            now += s
            tick()
            left -= s
        }
    }

    mutating func sleep(_ seconds: TimeInterval) {
        let e = tracker.suspend(now: now, idleSeconds: now.timeIntervalSince(lastInput), settings: settings)
        events += e
        ledger.apply(e, calendar: utc)
        now += seconds
        tracker.resume(now: now)
    }

    var breaks: [BreakRecord] {
        events.compactMap { if case .breakTaken(let b) = $0 { return b } else { return nil } }
    }

    var stretches: [TimeInterval] {
        events.compactMap { if case .sessionEnded(let s, let e) = $0 { return e.timeIntervalSince(s) } else { return nil } }
    }

    var today: DailyRecord { ledger.records[DayKey.key(t0, calendar: utc)] ?? DailyRecord(day: "") }
}

let activityTests: [TestCase] = [
    TestCase(name: "continuous work counts every second and takes no break") {
        var sim = Sim()
        sim.work(30 * 60)
        expectClose(sim.today.activeSeconds, 1800, tolerance: 1)
        expect(sim.breaks.isEmpty)
        expectClose(sim.tracker.continuousWork(at: sim.now), 1800, tolerance: 1)
    },
    TestCase(name: "a few seconds of inactivity is not a break") {
        var sim = Sim()
        sim.work(10 * 60)
        sim.idle(45)
        sim.work(10 * 60)
        expect(sim.breaks.isEmpty, "45 s idle must not reset timers")
        expectClose(sim.tracker.continuousWork(at: sim.now), 20 * 60 + 45, tolerance: 6)
        expectClose(sim.today.activeSeconds, 20 * 60 + 45, tolerance: 6)
    },
    TestCase(name: "stepping away 3 minutes is a short break and is not counted as work") {
        var sim = Sim()
        sim.work(20 * 60)
        sim.idle(3 * 60)
        sim.work(60)
        expectEqual(sim.breaks.count, 1)
        expectEqual(sim.breaks.first?.kind, .micro)
        expectClose(sim.breaks.first?.duration ?? 0, 180, tolerance: 6)
        expectClose(sim.today.activeSeconds, 21 * 60, tolerance: 6)
        expectEqual(sim.stretches.count, 1)
        expectClose(sim.stretches.first ?? 0, 20 * 60, tolerance: 6)
        expectClose(sim.tracker.continuousWork(at: sim.now), 60, tolerance: 6)
    },
    TestCase(name: "stepping away 6 minutes is a long break") {
        var sim = Sim()
        sim.work(50 * 60)
        sim.idle(6 * 60)
        sim.work(5 * 60)
        expectEqual(sim.breaks.map(\.kind), [.long])
        expectEqual(sim.tracker.lastLongBreakEnd, sim.breaks.first?.end)
        expectClose(sim.today.activeSeconds, 55 * 60, tolerance: 6)
    },
    TestCase(name: "Mac sleeps for two hours: a long break, no work credited") {
        var sim = Sim()
        sim.work(40 * 60)
        sim.sleep(2 * 3600)
        sim.work(10 * 60)
        expectEqual(sim.breaks.count, 1)
        expectEqual(sim.breaks.first?.source, .sleep)
        expectEqual(sim.breaks.first?.kind, .long)
        expectClose(sim.breaks.first?.duration ?? 0, 7200, tolerance: 6)
        expectClose(sim.today.activeSeconds, 50 * 60, tolerance: 6)
        expectClose(sim.tracker.continuousWork(at: sim.now), 10 * 60, tolerance: 6)
    },
    TestCase(name: "missed sleep notification: a long tick gap is not credited as work") {
        var sim = Sim()
        sim.work(30 * 60)
        // Process suspended for two hours; the user types right after.
        sim.now += 2 * 3600
        sim.lastInput = sim.now - 1
        sim.tick()
        sim.work(60)
        expectEqual(sim.breaks.count, 1)
        expectEqual(sim.breaks.first?.kind, .long)
        expectClose(sim.today.activeSeconds, 31 * 60, tolerance: 6)
    },
    TestCase(name: "sleep while already away keeps the original away start") {
        var sim = Sim()
        sim.work(10 * 60)
        sim.idle(4 * 60)
        sim.sleep(30 * 60)
        sim.work(60)
        expectEqual(sim.breaks.count, 1)
        expectClose(sim.breaks.first?.duration ?? 0, 34 * 60, tolerance: 10)
    },
    TestCase(name: "active time splits at local midnight") {
        let late = t0.addingTimeInterval(14 * 3600 + 50 * 60)   // 23:50 UTC
        var sim = Sim(start: late)
        sim.work(20 * 60)
        let d1 = sim.ledger.records["2026-03-02"]?.activeSeconds ?? 0
        let d2 = sim.ledger.records["2026-03-03"]?.activeSeconds ?? 0
        expectClose(d1, 600, tolerance: 6)
        expectClose(d2, 600, tolerance: 6)
    },
    TestCase(name: "a completed routine counts as a movement break") {
        var sim = Sim()
        sim.work(24 * 60)
        let e = sim.tracker.completeRoutine(start: sim.now - 60, end: sim.now)
        expectEqual(e.count, 1)
        expectEqual(sim.tracker.lastMicroBreakEnd, sim.now)
        let tooShort = sim.tracker.completeRoutine(start: sim.now - 10, end: sim.now)
        expect(tooShort.isEmpty, "a 10 s routine is not a break")
    },
    TestCase(name: "guided break spent away counts once, from its start") {
        var sim = Sim()
        sim.work(55 * 60)
        let start = sim.now
        sim.tracker.beginGuidedBreak(at: start, until: start + 180)
        sim.idle(3 * 60)      // timer ends while away
        _ = sim.tracker.finishGuidedBreak(at: sim.now, idleFraction: 1)
        sim.idle(60)
        sim.work(60)
        expectEqual(sim.breaks.count, 1, "no double count")
        expectEqual(sim.breaks.first?.kind, .long)
        expectEqual(sim.breaks.first?.source, .acknowledged)
        expectClose(sim.breaks.first?.start.timeIntervalSince(start) ?? 99, 0, tolerance: 1)
        expectClose(sim.today.activeSeconds, 56 * 60, tolerance: 8)
    },
    TestCase(name: "a guided break spent typing does not reset the timers") {
        var sim = Sim()
        sim.work(55 * 60)
        sim.tracker.beginGuidedBreak(at: sim.now, until: sim.now + 180)
        sim.work(3 * 60)
        let e = sim.tracker.finishGuidedBreak(at: sim.now, idleFraction: 0.1)
        expect(e.isEmpty)
        expect(sim.tracker.lastLongBreakEnd == nil)
    },
    TestCase(name: "a guided break taken at the desk while mostly idle counts") {
        var sim = Sim()
        sim.work(55 * 60)
        sim.tracker.beginGuidedBreak(at: sim.now, until: sim.now + 180)
        sim.idle(100)   // under the away threshold
        sim.work(80)
        let e = sim.tracker.finishGuidedBreak(at: sim.now, idleFraction: 0.7)
        expect(e.contains { if case .breakTaken(let b) = $0 { return b.kind == .long } else { return false } })
    },
    TestCase(name: "launching while the user is away waits for them") {
        var sim = Sim()
        sim.tracker = ActivityTracker()
        sim.now += 3600
        sim.tick()   // first tick: idle for an hour
        expect(!sim.tracker.isActive)
        sim.work(60)
        expect(sim.tracker.isActive)
        expectClose(sim.tracker.continuousWork(at: sim.now), 60, tolerance: 6)
    },
    TestCase(name: "tracker state survives an encode/decode round trip") {
        var sim = Sim()
        sim.work(10 * 60)
        sim.idle(3 * 60)
        sim.work(5 * 60)
        let data = try JSONEncoder().encode(sim.tracker)
        let back = try JSONDecoder().decode(ActivityTracker.self, from: data)
        expectEqual(back, sim.tracker)
    },
]
