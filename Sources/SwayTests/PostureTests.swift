import Foundation
import SwayCore

/// Deterministic synthetic landmark sequences. "Normal" is a face centred at
/// (0.5, 0.55), 0.25 of the frame tall, looking straight ahead, with a
/// little sensor noise.
struct Synth {
    var t: Date = t0
    var step: TimeInterval = 2
    var seed: UInt64 = 42

    mutating func noise(_ amp: Double) -> Double {
        // xorshift: deterministic, no Foundation randomness.
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return (Double(seed % 10_000) / 10_000 - 0.5) * 2 * amp
    }

    mutating func obs(lean: Double = 0, drop: Double = 0, roll: Double = 0, pitch: Double = 0, yaw: Double = 0,
                      shoulderTilt: Double = 0, confidence: Double = 0.95, faces: Int = 1, jitter: Double = 0.004) -> PostureObservation {
        let h = 0.25 * (1 + lean) + noise(jitter)
        let cy = 0.55 - drop * 0.25 + noise(jitter)
        let cx = 0.5 + noise(jitter)
        let lift = tan(shoulderTilt * .pi / 180) * 0.4
        let o = PostureObservation(
            timestamp: t, faceCount: faces, faceConfidence: confidence,
            faceCenter: Point2(cx, cy), faceHeight: h,
            pitch: pitch + noise(0.5), yaw: yaw + noise(0.5), roll: roll + noise(0.5),
            leftShoulder: Point2(0.7, 0.2 + lift / 2), rightShoulder: Point2(0.3, 0.2 - lift / 2), shoulderConfidence: 0.8)
        t += step
        return o
    }

    mutating func noFace() -> PostureObservation {
        let o = PostureObservation.noFace(at: t)
        t += step
        return o
    }

    mutating func baselineSamples(_ n: Int = 15) -> [PostureObservation] {
        (0..<n).map { _ in obs() }
    }
}

func calibrated(_ synth: inout Synth, lookDown: Bool = false) -> Calibration {
    let base = synth.baselineSamples()
    let ld = lookDown ? (0..<5).map { _ in synth.obs(drop: 0.6, pitch: -15) } : []
    guard case .success(let c) = CalibrationBuilder.build(samples: base, lookDown: ld, cameraID: "cam-1", cameraName: "Test", minConfidence: 0.6, now: t0) else {
        fatalError("calibration failed")
    }
    return c
}

struct PostureRun {
    var engine = PostureEngine()
    var settings = CoachSettings()
    var synth = Synth()
    var started: [(PostureIssue, Date)] = []
    var ended: [PostureEpisode] = []

    init(lookDown: Bool = false, settings: CoachSettings = CoachSettings()) {
        self.settings = settings
        let cal = calibrated(&synth, lookDown: lookDown)
        engine.configure(calibration: cal, cameraID: "cam-1", settings: settings)
    }

    mutating func feed(_ seconds: TimeInterval, _ make: (inout Synth) -> PostureObservation) {
        let n = Int(seconds / synth.step)
        for _ in 0..<n {
            let o = make(&synth)
            record(engine.process(o, settings: settings))
        }
    }

    mutating func record(_ events: [PostureEvent]) {
        for e in events {
            switch e {
            case .started(let i, let s): started.append((i, s))
            case .ended(let ep): ended.append(ep)
            }
        }
    }

    func startedIssues() -> [PostureIssue] { started.map(\.0) }
}

let postureTests: [TestCase] = [
    TestCase(name: "calibration from a steady sequence is good and reports what it can measure") {
        var s = Synth()
        let c = calibrated(&s)
        expectEqual(c.report.quality, .good)
        expectEqual(c.report.measurable[.shoulderAsymmetry], true)
        expectEqual(c.report.measurable[.lateralTilt], true)
        expectClose(c.baseline.faceHeight, 0.25, tolerance: 0.01)
        expect(c.report.notes.contains { $0.contains("not measurements of your spine") })
    },
    TestCase(name: "calibration refuses missing faces, crowds, movement and distance") {
        var s = Synth()
        let mostlyNoFace = (0..<15).map { i in i % 3 == 0 ? s.obs() : s.noFace() }
        expectEqual(CalibrationBuilder.build(samples: mostlyNoFace, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0).failure, .notEnoughFace(valid: 5, total: 15))
        let crowd = (0..<15).map { _ in s.obs(faces: 2) }
        expectEqual(CalibrationBuilder.build(samples: crowd, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0).failure, .multipleFaces)
        let moving = (0..<15).map { i in s.obs(drop: i % 2 == 0 ? 0.8 : -0.8) }
        expectEqual(CalibrationBuilder.build(samples: moving, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0).failure, .tooMuchMovement)
        let far = (0..<15).map { _ in s.obs(lean: -0.8) }
        expectEqual(CalibrationBuilder.build(samples: far, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0).failure, .tooFar)
        let dim = (0..<15).map { _ in s.obs(confidence: 0.3) }
        expect(CalibrationBuilder.build(samples: dim, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0).failure != nil, "low confidence")
    },
    TestCase(name: "head-only framing turns shoulder detection off, honestly") {
        var s = Synth()
        let samples = (0..<15).map { _ -> PostureObservation in
            var o = s.obs()
            o.leftShoulder = nil
            o.rightShoulder = nil
            o.shoulderConfidence = 0
            return o
        }
        guard case .success(let c) = CalibrationBuilder.build(samples: samples, cameraID: "c", cameraName: "", minConfidence: 0.6, now: t0) else { return expect(false) }
        expectEqual(c.report.measurable[.shoulderAsymmetry], false)
        expect(c.report.notes.contains { $0.contains("Shoulders weren't clearly visible") })
    },
    TestCase(name: "leaning forward for 5 seconds does nothing") {
        var run = PostureRun()
        run.feed(60) { $0.obs() }
        run.feed(6) { $0.obs(lean: 0.35) }
        run.feed(10 * 60) { $0.obs() }
        expect(run.started.isEmpty, "\(run.startedIssues())")
    },
    TestCase(name: "leaning forward for several minutes becomes one sustained episode") {
        var run = PostureRun()
        run.feed(60) { $0.obs() }
        let leanStart = run.synth.t
        run.feed(8 * 60) { $0.obs(lean: 0.3) }
        expectEqual(run.startedIssues(), [.forwardLean])
        // The episode is dated from when the lean began (smoothing lag aside).
        expectClose(run.started.first?.1.timeIntervalSince(leanStart) ?? 999, 0, tolerance: 15)
        expectEqual(run.engine.activeIssues().map(\.issue), [.forwardLean])
        run.feed(2 * 60) { $0.obs() }
        expectEqual(run.ended.count, 1)
        expectClose(run.ended.first?.duration ?? 0, 8 * 60, tolerance: 40)
        expect(run.engine.activeIssues().isEmpty)
    },
    TestCase(name: "a lean over the line shows as building until it has lasted long enough") {
        var run = PostureRun()
        run.feed(60) { $0.obs() }
        expect(!run.engine.buildingIssues().contains { $0.issue == .forwardLean })
        let leanStart = run.synth.t
        run.feed(2 * 60) { $0.obs(lean: 0.3) }
        let b = run.engine.buildingIssues().filter { $0.issue == .forwardLean }
        expectEqual(b.count, 1)
        expectEqual(b.first?.needed, 5 * 60)
        expectClose(b.first?.remaining(at: run.synth.t) ?? 0, 3 * 60, tolerance: 15)
        expectClose(b.first?.since.timeIntervalSince(leanStart) ?? 999, 0, tolerance: 15)
        expect(run.engine.activeIssues().isEmpty, "not counted yet")
        run.feed(4 * 60) { $0.obs(lean: 0.3) }
        expect(!run.engine.buildingIssues().contains { $0.issue == .forwardLean }, "now an episode instead")
        expectEqual(run.engine.activeIssues().map(\.issue), [.forwardLean])
    },
    TestCase(name: "changing position frequently produces no posture episode") {
        var run = PostureRun()
        for i in 0..<20 {
            run.feed(90) { i % 2 == 0 ? $0.obs(lean: 0.3, drop: 0.4) : $0.obs(roll: 3) }
        }
        let nonStatic = run.startedIssues().filter { $0 != .staticPosture }
        expect(nonStatic.isEmpty, "\(nonStatic)")
        expect(!run.startedIssues().contains(.staticPosture), "moving is not static")
    },
    TestCase(name: "sitting still for 45 minutes is flagged as little movement") {
        var run = PostureRun()
        run.feed(44 * 60) { $0.obs(jitter: 0.002) }
        expect(!run.startedIssues().contains(.staticPosture), "not before 45 min")
        run.feed(6 * 60) { $0.obs(jitter: 0.002) }
        expectEqual(run.startedIssues(), [.staticPosture])
        // Standing up / moving ends it.
        run.feed(60) { s in s.obs(lean: s.noise(0.4), drop: s.noise(0.8), roll: s.noise(15)) }
        expectEqual(run.ended.map(\.issue), [.staticPosture])
    },
    TestCase(name: "brief tracking loss keeps an episode; a long loss ends it where last seen") {
        var run = PostureRun()
        run.feed(8 * 60) { $0.obs(lean: 0.3) }
        expectEqual(run.startedIssues(), [.forwardLean])
        run.feed(20) { $0.noFace() }
        run.feed(30) { $0.obs(lean: 0.3) }
        expect(run.ended.isEmpty, "20 s without a face is tolerated")
        let lastSeen = run.synth.t - run.synth.step
        run.feed(3 * 60) { $0.noFace() }
        expectEqual(run.ended.count, 1)
        expectClose(run.ended.first?.end.timeIntervalSince(lastSeen) ?? 999, 0, tolerance: 0.1)
        expectEqual(run.engine.status, .searching)
        expect(run.engine.activeIssues().isEmpty)
        // Coming back still leaning needs a fresh sustained period.
        run.feed(60) { $0.obs(lean: 0.3) }
        expectEqual(run.started.count, 1)
    },
    TestCase(name: "low-confidence frames never produce warnings") {
        var run = PostureRun()
        run.feed(15 * 60) { $0.obs(lean: 0.35, drop: 0.8, roll: 20, confidence: 0.35) }
        expect(run.started.isEmpty)
        expectEqual(run.engine.status, .lowConfidence)
    },
    TestCase(name: "someone else in view makes estimates unknown") {
        var run = PostureRun()
        run.feed(15 * 60) { $0.obs(lean: 0.35, faces: 2) }
        expect(run.started.isEmpty)
    },
    TestCase(name: "mostly-missing landmarks: reliability gate holds back warnings") {
        var run = PostureRun()
        var i = 0
        run.feed(15 * 60) { s in
            i += 1
            return i % 2 == 0 ? s.obs(lean: 0.35) : s.noFace()
        }
        expect(run.started.filter { $0.0 != .staticPosture }.isEmpty, "50% usable frames is below the reliability bar")
    },
    TestCase(name: "camera disconnect ends the episode and stops tracking") {
        var run = PostureRun()
        run.feed(8 * 60) { $0.obs(lean: 0.3) }
        let lastSeen = run.synth.t - run.synth.step
        run.record(run.engine.stop(status: .off))
        expectEqual(run.ended.count, 1)
        expectClose(run.ended.first?.end.timeIntervalSince(lastSeen) ?? 999, 0, tolerance: 0.1)
        expectEqual(run.engine.status, .off)
        expect(run.engine.activeIssues().isEmpty)
    },
    TestCase(name: "a different camera requires recalibration and yields nothing") {
        var run = PostureRun()
        let cal = run.engine.calibration
        run.engine.configure(calibration: cal, cameraID: "external-2", settings: run.settings)
        run.feed(10 * 60) { $0.obs(lean: 0.4) }
        expectEqual(run.engine.status, .needsRecalibration)
        expect(run.started.isEmpty)
    },
    TestCase(name: "hysteresis: hovering near the threshold does not flap") {
        var run = PostureRun()
        run.feed(6 * 60) { $0.obs(lean: 0.22) }
        expectEqual(run.startedIssues(), [.forwardLean])
        // Oscillate between just below enter (0.16) and above exit (0.09).
        for i in 0..<30 {
            run.feed(20) { $0.obs(lean: i % 2 == 0 ? 0.11 : 0.15) }
        }
        expectEqual(run.started.count, 1)
        expect(run.ended.isEmpty, "stays one episode")
    },
    TestCase(name: "head down: tuned by the look-at-keyboard reference") {
        var run = PostureRun(lookDown: true)
        expect(run.engine.calibration?.lookDown != nil)
        run.feed(7 * 60) { $0.obs(drop: 0.5, pitch: -12) }
        expectEqual(run.startedIssues(), [.headDown])
        let v = run.engine.metrics.headDown ?? 0
        expect(v > 0.6 && v < 1.2, "close to the reference: \(v)")
    },
    TestCase(name: "head down without a reference uses the cautious default") {
        var run = PostureRun()
        run.feed(7 * 60) { $0.obs(drop: 0.15) }
        expect(run.started.isEmpty, "a small drop is normal variation")
        run.feed(7 * 60) { $0.obs(drop: 0.45) }
        expectEqual(run.startedIssues(), [.headDown])
    },
    TestCase(name: "looking at another monitor is not a posture issue") {
        var run = PostureRun()
        run.feed(10 * 60) { $0.obs(drop: 0.5, roll: 15, yaw: 40) }
        expect(run.started.filter { $0.0 != .staticPosture }.isEmpty, "\(run.startedIssues())")
        expectEqual(run.engine.status, .lookingAway)
    },
    TestCase(name: "lateral tilt and shoulder asymmetry") {
        var run = PostureRun()
        run.feed(7 * 60) { $0.obs(roll: 18) }
        expectEqual(run.startedIssues(), [.lateralTilt])
        var run2 = PostureRun()
        run2.feed(12 * 60) { $0.obs(shoulderTilt: 10) }
        expectEqual(run2.startedIssues(), [.shoulderAsymmetry])
    },
    TestCase(name: "disabled issues and personal sensitivity are respected") {
        var s = CoachSettings()
        s.forwardLean.enabled = false
        var run = PostureRun(settings: s)
        run.feed(8 * 60) { $0.obs(lean: 0.3) }
        expect(run.started.isEmpty)
        var run2 = PostureRun()
        var adj = Adjustments()
        adj.thresholdScales[.forwardLean] = 1.6   // needs a 25.6% lean
        run2.engine.rebuildDetectors(settings: run2.settings, adjustments: adj)
        run2.feed(8 * 60) { $0.obs(lean: 0.2) }
        expect(run2.started.isEmpty)
    },
    TestCase(name: "smoother: irregular spacing and reset after gaps") {
        var s = Smoother(tau: 8, resetAfter: 30)
        expectEqual(s.update(0, at: t0), 0)
        let v = s.update(1, at: t0 + 8)
        expectClose(v, 1 - exp(-1), tolerance: 1e-9)
        expectEqual(s.update(5, at: t0 + 100), 5, "reset after a long gap")
    },
    TestCase(name: "persistent patterns escalate to a workstation suggestion") {
        expectEqual(PatternDetector.persistent(todayEpisodes: [.headDown: 3], recentDays: []), [.headDown])
        expectEqual(PatternDetector.persistent(todayEpisodes: [.headDown: 1], recentDays: [[.headDown], [], [.headDown]]), [.headDown])
        expect(PatternDetector.persistent(todayEpisodes: [.headDown: 1], recentDays: [[], [.headDown]]).isEmpty)
        expect(PatternDetector.persistent(todayEpisodes: [.staticPosture: 5], recentDays: []).isEmpty, "stillness is a habit, not a setup problem")
    },
]

extension Result {
    var failure: Failure? { if case .failure(let f) = self { return f } else { return nil } }
}
