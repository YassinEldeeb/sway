import Foundation
import SwayCore

// P1: recurring short deviations (rolling window). P3: calibration health.

/// Ordinary head movement: enough variation that it never reads as "still".
private let moving = 0.03

let patternTests: [TestCase] = [
    TestCase(name: "repeated short leans over an hour are noticed, without any posture reminder") {
        var run = PostureRun()
        run.feed(60) { $0.obs(jitter: moving) }
        for _ in 0..<6 {
            run.feed(4 * 60) { $0.obs(lean: 0.3, jitter: moving) }   // under the 5-min sustained limit
            run.feed(6 * 60) { $0.obs(jitter: moving) }
        }
        expect(!run.startedIssues().contains(.forwardLean), "no single lean lasted long enough to be sustained")
        let f = run.engine.frequentFlags(now: run.synth.t, settings: run.settings)
        expect(f[.forwardLean] != nil, "\(f)")
        expect((f[.forwardLean]?.bouts ?? 0) >= 4)
        expect(f[.headDown] == nil && f[.staticPosture] == nil, "\(f.keys)")
    },
    TestCase(name: "repeated short head-down bouts are noticed") {
        var run = PostureRun()
        run.feed(60) { $0.obs(jitter: moving) }
        for _ in 0..<6 {
            run.feed(4 * 60) { $0.obs(drop: 0.4, jitter: moving) }
            run.feed(6 * 60) { $0.obs(jitter: moving) }
        }
        expect(!run.startedIssues().contains(.headDown))
        expect(run.engine.frequentFlags(now: run.synth.t, settings: run.settings)[.headDown] != nil)
    },
    TestCase(name: "ordinary movement, including brief leans and glances down, is never a pattern") {
        var run = PostureRun()
        for i in 0..<45 {
            run.feed(100) { $0.obs(jitter: moving) }
            if i % 2 == 0 { run.feed(16) { $0.obs(lean: 0.35, jitter: moving) } } else { run.feed(16) { $0.obs(drop: 0.5, jitter: moving) } }
        }
        expect(run.engine.frequentFlags(now: run.synth.t, settings: run.settings).isEmpty)
        expect(run.started.isEmpty, "\(run.startedIssues())")
    },
    TestCase(name: "bouts shorter than the minimum never count, however often they happen") {
        func run(minBout: TimeInterval) -> FrequentFlag? {
            var d = FrequentPatternDetector()
            var s = FrequentPatternSettings()
            s.minBout = minBout
            var t = t0
            for _ in 0..<90 {   // an hour: 20 s over, 20 s under
                for _ in 0..<10 { d.update(.forwardLean, over: true, at: t, settings: s); t += 2 }
                for _ in 0..<10 { d.update(.forwardLean, over: false, at: t, settings: s); t += 2 }
            }
            return d.assess(.forwardLean, now: t, settings: s)
        }
        expect(run(minBout: 30) == nil, "20-s bouts are ordinary movement")
        expect(run(minBout: 10) != nil, "the same hour with a 10-s minimum would be flagged, so the minimum is what decides")
    },
    TestCase(name: "low-confidence observations never build a pattern") {
        var run = PostureRun()
        for _ in 0..<7 {
            run.feed(4 * 60) { $0.obs(lean: 0.3, confidence: 0.4, jitter: moving) }
            run.feed(6 * 60) { $0.obs(confidence: 0.4, jitter: moving) }
        }
        expect(run.engine.frequentFlags(now: run.synth.t, settings: run.settings).isEmpty)
    },
    TestCase(name: "camera interruptions don't count as observed time or join bouts") {
        var d = FrequentPatternDetector()
        var s = FrequentPatternSettings()
        s.minObserved = 2 * 60
        s.minBouts = 1
        var t = t0
        // 20 s over, a 60 s gap with no observations, 20 s over: two short
        // bouts, not one 100 s bout.
        for _ in 0..<10 { d.update(.forwardLean, over: true, at: t, settings: s); t += 2 }
        t += 60
        for _ in 0..<10 { d.update(.forwardLean, over: true, at: t, settings: s); t += 2 }
        for _ in 0..<60 { d.update(.forwardLean, over: false, at: t, settings: s); t += 2 }
        expect(d.assess(.forwardLean, now: t, settings: s) == nil, "no qualifying bout")
        // Many interrupted sessions: an hour of wall time but little observed.
        var e = FrequentPatternDetector()
        var u = t0
        for _ in 0..<6 {
            for _ in 0..<60 { e.update(.forwardLean, over: true, at: u, settings: FrequentPatternSettings()); u += 2 }
            e.stop(settings: FrequentPatternSettings())
            u += 8 * 60
        }
        expect(e.assess(.forwardLean, now: u, settings: FrequentPatternSettings()) == nil, "12 min observed is not enough evidence")
    },
    TestCase(name: "long stretches of very little movement are noticed even with short interruptions") {
        var run = PostureRun()
        for _ in 0..<3 {
            run.feed(24 * 60) { $0.obs() }                  // very still
            run.feed(60) { $0.obs(jitter: 0.06) }           // a minute of movement
        }
        expect(!run.startedIssues().contains(.staticPosture), "never 45 min in a row")
        expect(run.engine.frequentFlags(now: run.synth.t, settings: run.settings)[.staticPosture] != nil)
    },
    TestCase(name: "a recurring issue is recorded once a day") {
        var ledger = Ledger()
        let f = FrequentFlag(at: t0, share: 0.4, bouts: 6, observedMinutes: 55)
        expect(ledger.flagFrequent(.forwardLean, f, calendar: utc))
        expect(!ledger.flagFrequent(.forwardLean, FrequentFlag(at: t0 + 3600, share: 0.5, bouts: 8, observedMinutes: 60), calendar: utc))
        expectEqual(ledger.records["2026-03-02"]?.frequentPatterns[.forwardLean], f)
        expectEqual(ledger.records["2026-03-02"]?.log.count, 1)
    },
    TestCase(name: "a moved camera pauses posture warnings with an explanation, then recovers") {
        var run = PostureRun()
        run.feed(60) { $0.obs(jitter: moving) }
        // Laptop moved closer and to the side: the face is bigger and far off-centre.
        run.feed(12 * 60) { $0.obs(lean: 0.3, jitter: moving, dx: 0.3) }
        expectEqual(run.engine.status, .calibrationSuspect)
        expect(run.started.isEmpty, "no posture warning from a moved camera: \(run.startedIssues())")
        expect(run.engine.activeIssues().isEmpty)
        expect(run.engine.frequentFlags(now: run.synth.t, settings: run.settings).isEmpty)
        run.feed(4 * 60) { $0.obs(jitter: moving) }   // back where it was
        expectEqual(run.engine.status, .tracking)
    },
    TestCase(name: "ordinary posture changes never look like a moved camera") {
        var run = PostureRun()
        run.feed(60) { $0.obs(jitter: moving) }
        run.feed(12 * 60) { $0.obs(lean: 0.35, jitter: moving, dx: 0.1) }   // a real lean, slightly to one side
        expect(run.engine.status != .calibrationSuspect)
        expect(run.startedIssues().contains(.forwardLean))
        var turned = PostureRun()
        turned.feed(60) { $0.obs(jitter: moving) }
        turned.feed(15 * 60) { $0.obs(yaw: 40, jitter: moving) }   // working on a side monitor
        expect(turned.engine.status != .calibrationSuspect, "looking at another screen is ordinary")
        var brief = PostureRun()
        brief.feed(60) { $0.obs(jitter: moving) }
        brief.feed(4 * 60) { $0.obs(jitter: moving, dx: 0.3) }
        expect(brief.engine.status != .calibrationSuspect, "a few minutes off to the side is not enough")
    },
]
