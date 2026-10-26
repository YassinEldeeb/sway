import Foundation

public enum TrackingStatus: Equatable, Sendable {
    case off
    case notCalibrated
    /// The calibration belongs to a different camera.
    case needsRecalibration
    /// No face seen recently.
    case searching
    /// A face is visible but the estimates are not trustworthy right now
    /// (dim light, partly out of frame, someone else in view).
    case lowConfidence
    /// Turned well away from the calibrated direction (e.g. another monitor).
    case lookingAway
    /// For ten minutes the face has sat far from where it was calibrated:
    /// the screen, camera or chair probably moved. Warnings are paused.
    case calibrationSuspect
    case tracking

    public var label: String {
        switch self {
        case .off: return "Off"
        case .notCalibrated: return "Needs calibration"
        case .needsRecalibration: return "Recalibrate for this camera"
        case .searching: return "Looking for you"
        case .lowConfidence: return "Low confidence"
        case .lookingAway: return "Looking away"
        case .calibrationSuspect: return "Calibration may be out of date"
        case .tracking: return "Tracking"
        }
    }
}

public struct PostureEpisode: Codable, Equatable, Sendable {
    public var issue: PostureIssue
    public var start: Date
    public var end: Date
    public var peak: Double
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(issue: PostureIssue, start: Date, end: Date, peak: Double) {
        self.issue = issue
        self.start = start
        self.end = end
        self.peak = peak
    }
}

public enum PostureEvent: Equatable, Sendable {
    case started(PostureIssue, since: Date)
    case ended(PostureEpisode)
}

/// Smoothed deviations from baseline, for the live readout.
public struct PostureMetrics: Equatable, Sendable {
    public var headDown: Double?
    public var forwardLean: Double?
    public var lateralTilt: Double?
    public var shoulderAsymmetry: Double?
    public var motion: Double?
}

public struct ActiveIssue: Equatable, Sendable {
    public var issue: PostureIssue
    public var since: Date
    /// The user has already moved back under the exit line; the episode
    /// ends shortly unless the deviation returns.
    public var easing: Bool

    public init(issue: PostureIssue, since: Date, easing: Bool = false) {
        self.issue = issue
        self.since = since
        self.easing = easing
    }
}

/// A deviation that is over its threshold but hasn't lasted long enough to
/// count yet: it becomes an episode at `since + needed` unless it eases off.
public struct BuildingIssue: Equatable, Sendable {
    public var issue: PostureIssue
    public var since: Date
    public var needed: TimeInterval
    public func remaining(at now: Date) -> TimeInterval { max(0, needed - now.timeIntervalSince(since)) }
}

/// Converts observations into sustained-deviation episodes against the
/// user's calibration. Deterministic: same observations, same output.
public struct PostureEngine: Sendable {
    public private(set) var calibration: Calibration?
    public private(set) var cameraID: String?
    public private(set) var status: TrackingStatus = .off
    public private(set) var metrics = PostureMetrics()

    private var smoothers: [PostureIssue: Smoother] = [:]
    private var detectors: [PostureIssue: SustainedDetector] = [:]
    private var motion = MotionWindow()
    private var recent: [(t: Date, valid: Bool)] = []
    private var lastFaceAt: Date?
    public private(set) var frequency = FrequentPatternDetector()
    public private(set) var health = CalibrationHealthMonitor()
    private var frequentSettings = FrequentPatternSettings()

    /// Share of samples in the last two minutes that were usable. Below this,
    /// Sway shows "low confidence" and raises no posture prompts.
    public static let minReliability = 0.6
    /// Beyond this head turn from calibration, head-down/tilt/lean estimates
    /// are not trusted.
    public static let maxYawDelta = 28.0

    public init() {}

    public mutating func configure(calibration: Calibration?, cameraID: String?, settings: CoachSettings, adjustments: Adjustments = .neutral) {
        let changed = calibration != self.calibration || cameraID != self.cameraID
        self.calibration = calibration
        self.cameraID = cameraID
        if changed { resetSignals(includingHistory: true) }
        rebuildDetectors(settings: settings, adjustments: adjustments)
        status = baseStatus() ?? status
    }

    /// Threshold changes keep the detectors' running state.
    public mutating func rebuildDetectors(settings: CoachSettings, adjustments: Adjustments) {
        for issue in PostureIssue.allCases {
            let t = settings.thresholds(for: issue)
            let scale = adjustments.thresholdScale(issue)
            var d: SustainedDetector
            if issue == .staticPosture {
                d = SustainedDetector(enter: 0.5, exit: 0.5, minDuration: t.minDuration, exitDuration: 15, dipTolerance: 60, maxUnknownGap: 90)
            } else {
                d = SustainedDetector(enter: t.enter * scale, exit: t.exit * scale, minDuration: t.minDuration)
            }
            if let old = detectors[issue], old.enter == d.enter, old.exit == d.exit, old.minDuration == d.minDuration {
                continue
            }
            if let old = detectors[issue] {
                // Keep an in-progress episode across a sensitivity change.
                d = old.retuned(enter: d.enter, exit: d.exit, minDuration: d.minDuration)
            }
            detectors[issue] = d
        }
    }

    private func baseStatus() -> TrackingStatus? {
        guard let cal = calibration else { return .notCalibrated }
        if let id = cameraID, id != cal.cameraID { return .needsRecalibration }
        return nil
    }

    /// A camera stop keeps the rolling history (patterns across a short
    /// interruption, a moved camera); a new calibration clears it.
    private mutating func resetSignals(includingHistory: Bool = false) {
        smoothers = [:]
        motion.clear()
        recent = []
        lastFaceAt = nil
        metrics = PostureMetrics()
        if includingHistory {
            frequency.reset()
            health.reset()
        }
    }

    public var reliability: Double {
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter(\.valid).count) / Double(recent.count)
    }

    /// Camera stopped (paused, user away, disconnected). Ends active episodes
    /// at the last time they were actually observed.
    public mutating func stop(status newStatus: TrackingStatus = .off) -> [PostureEvent] {
        var events: [PostureEvent] = []
        for issue in PostureIssue.allCases {
            guard var d = detectors[issue] else { continue }
            for e in d.expire(lastSeen: d.lastKnown) { events += map(e, issue) }
            detectors[issue] = d
        }
        frequency.stop(settings: frequentSettings)
        resetSignals()
        status = baseStatus() ?? newStatus
        return events
    }

    public mutating func process(_ o: PostureObservation, settings: CoachSettings) -> [PostureEvent] {
        if let s = baseStatus() {
            status = s
            return []
        }
        guard let cal = calibration else { return [] }
        let b = cal.baseline
        let t = o.timestamp
        var events: [PostureEvent] = []

        let hasFace = o.faceCount >= 1 && o.faceCenter != nil && (o.faceHeight ?? 0) > 0
        if hasFace { lastFaceAt = t }
        let sizeRatio = (o.faceHeight ?? 0) / b.faceHeight
        let plausible = hasFace && o.faceCount == 1 && o.faceConfidence >= settings.minFaceConfidence && sizeRatio > 0.5 && sizeRatio < 2.2
        let yawDelta = (o.yaw.flatMap { y in b.yaw.map { abs(y - $0) } }) ?? 0
        let facingScreen = yawDelta <= Self.maxYawDelta

        if hasFace, o.faceCount == 1, o.faceConfidence >= settings.minFaceConfidence, let c = o.faceCenter {
            health.update(off: CalibrationHealthMonitor.isOff(offset: abs(c.x - b.faceCenter.x), sizeRatio: sizeRatio), at: t)
        } else {
            health.update(off: nil, at: t)
        }
        frequentSettings = settings.frequentPatterns

        recent.append((t, plausible))
        recent.removeAll { t.timeIntervalSince($0.t) > 120 }
        let reliable = reliability >= Self.minReliability && recent.count >= 5

        // Deviation values; nil means "unknown" and never counts as deviation.
        var values: [PostureIssue: Double?] = [:]
        if plausible, facingScreen, let c = o.faceCenter, let h = o.faceHeight {
            let drop = (b.faceCenter.y - c.y) / b.faceHeight
            let dPitch = (o.pitch.flatMap { p in b.pitch.map { p - $0 } }) ?? 0
            let headDown: Double
            if let ref = cal.lookDown {
                // Projection onto the user's own "looking at the keyboard"
                // movement: 1.0 means as far down as that reference.
                // The reference drop is floored at 0.3 face heights so a
                // small reference can't make detection hypersensitive.
                let refDrop = max(ref.x, 0.3)
                let refPitch = ref.y / 20, curPitch = dPitch / 20
                let denom = refDrop * refDrop + refPitch * refPitch
                headDown = denom > 0 ? (drop * refDrop + curPitch * refPitch) / denom : drop / 0.5
            } else {
                // Without a reference the pitch sign is not trusted; half a
                // face height lower than baseline scores 1.0.
                headDown = drop / 0.5
            }
            values[.headDown] = smooth(.headDown, headDown, t)
            values[.forwardLean] = smooth(.forwardLean, h / b.faceHeight - 1, t)
            if let r = o.roll, let br = b.roll {
                values[.lateralTilt] = smooth(.lateralTilt, abs(angleDelta(r, br)), t)
            } else {
                values[.lateralTilt] = .some(nil)
            }
            if let s = o.shoulderSlope, let bs = b.shoulderSlope {
                values[.shoulderAsymmetry] = smooth(.shoulderAsymmetry, abs(angleDelta(s, bs)), t)
            } else {
                values[.shoulderAsymmetry] = .some(nil)
            }
        }
        if !reliable || health.isSuspect {
            // Not enough good data recently, or the calibration no longer
            // fits the setup: treat everything as unknown.
            values = [:]
        }

        // Stillness uses presence, not facing direction: turning to another
        // screen is movement.
        if plausible, let c = o.faceCenter {
            motion.add(t: t, x: c.x / b.faceHeight, y: c.y / b.faceHeight, roll: o.roll ?? 0)
        }
        var staticValue: Double?
        if plausible, reliable, !health.isSuspect, motion.covers(0.8) {
            staticValue = motion.motion < settings.staticMotionThreshold ? 1 : 0
        }

        for issue in PostureIssue.allCases {
            guard var d = detectors[issue] else { continue }
            let enabled = settings.thresholds(for: issue).enabled && (cal.report.measurable[issue] ?? false)
            let v: Double? = !enabled ? nil : (issue == .staticPosture ? staticValue : (values[issue] ?? nil))
            for e in d.update(v, at: t) { events += map(e, issue) }
            detectors[issue] = d
            if FrequentPatternDetector.issues.contains(issue) {
                let over = v.map { issue == .staticPosture ? $0 >= 0.5 : $0 >= d.enter }
                frequency.update(issue, over: over, at: t, settings: frequentSettings)
            }
        }

        metrics = PostureMetrics(
            headDown: values[.headDown] ?? nil, forwardLean: values[.forwardLean] ?? nil,
            lateralTilt: values[.lateralTilt] ?? nil, shoulderAsymmetry: values[.shoulderAsymmetry] ?? nil,
            motion: motion.count >= 3 ? motion.motion : nil)

        if !hasFace {
            status = (lastFaceAt.map { t.timeIntervalSince($0) < 10 } ?? false) ? status : .searching
        } else if health.isSuspect {
            status = .calibrationSuspect
        } else if !reliable || !plausible {
            status = .lowConfidence
        } else if !facingScreen {
            status = .lookingAway
        } else {
            status = .tracking
        }
        return events
    }

    /// Issues currently in a sustained episode. Empty unless tracking is
    /// reliable, so a low-confidence period never produces a warning.
    public func activeIssues() -> [ActiveIssue] {
        guard status == .tracking || status == .lookingAway else { return [] }
        return PostureIssue.allCases.compactMap { issue in
            guard let d = detectors[issue], let since = d.activeSince else { return nil }
            return ActiveIssue(issue: issue, since: since, easing: d.isEasing)
        }
    }

    /// Deviations over their threshold that are still being timed. Same
    /// reliability gate as `activeIssues()`.
    public func buildingIssues() -> [BuildingIssue] {
        guard status == .tracking || status == .lookingAway else { return [] }
        return PostureIssue.allCases.compactMap { issue in
            guard let d = detectors[issue], let since = d.pendingSince else { return nil }
            return BuildingIssue(issue: issue, since: since, needed: d.minDuration)
        }
    }

    /// Issues that came up often in short bouts over the rolling window.
    /// Same reliability gate as the other estimates (unknown time never
    /// counts), and only for issues that are enabled and measurable.
    public func frequentFlags(now: Date, settings: CoachSettings) -> [PostureIssue: FrequentFlag] {
        guard let cal = calibration, status != .calibrationSuspect else { return [:] }
        var out: [PostureIssue: FrequentFlag] = [:]
        for issue in FrequentPatternDetector.issues where settings.thresholds(for: issue).enabled && (cal.report.measurable[issue] ?? false) {
            if let f = frequency.assess(issue, now: now, settings: settings.frequentPatterns) { out[issue] = f }
        }
        return out
    }

    private mutating func smooth(_ issue: PostureIssue, _ x: Double, _ t: Date) -> Double {
        var s = smoothers[issue] ?? Smoother()
        let v = s.update(x, at: t)
        smoothers[issue] = s
        return v
    }

    private func map(_ e: SustainedDetector.Event, _ issue: PostureIssue) -> [PostureEvent] {
        switch e {
        case .started(let since): return [.started(issue, since: since)]
        case .ended(let start, let end, let peak):
            return [.ended(PostureEpisode(issue: issue, start: start, end: end, peak: peak))]
        }
    }

    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }
}

extension SustainedDetector {
    func retuned(enter: Double, exit: Double, minDuration: TimeInterval) -> SustainedDetector {
        var d = self
        d.enter = enter
        d.exit = min(exit, enter)
        d.minDuration = minDuration
        return d
    }
}

/// Level 4: when the same issue keeps coming back, the setup (not the
/// person) is the likely cause, and repeating the same reminder won't help.
public enum PatternDetector {
    public static let episodesPerDay = 3
    public static let daysInWeek = 3

    /// `todayEpisodes`: episode count per issue today. `recentDays`: one
    /// entry per earlier day (most recent last) with the issues seen that day.
    public static func persistent(todayEpisodes: [PostureIssue: Int], recentDays: [Set<PostureIssue>]) -> Set<PostureIssue> {
        var out = Set<PostureIssue>()
        for issue in PostureIssue.allCases where issue != .staticPosture {
            let today = todayEpisodes[issue] ?? 0
            let days = recentDays.suffix(6).filter { $0.contains(issue) }.count + (today > 0 ? 1 : 0)
            if today >= episodesPerDay || (days >= daysInWeek && today > 0) {
                out.insert(issue)
            }
        }
        return out
    }

    public static func advice(for issue: PostureIssue) -> String {
        switch issue {
        case .headDown:
            return "Your head keeps tilting down for long stretches. That usually means the screen is too low — on a laptop especially. Raising the screen so its top sits around eye level, with an external keyboard, often helps more than reminders."
        case .forwardLean:
            return "You keep leaning toward the screen. Text size, screen distance or glasses can be the cause: try a larger font or moving the screen a little closer rather than bringing yourself to it."
        case .lateralTilt:
            return "Your head often tilts to one side. Check whether your main screen or a document sits off to one side, and centre what you look at most."
        case .shoulderAsymmetry:
            return "One shoulder often sits higher. Check that the mouse isn't far out to the side or too high, and that both forearms are supported."
        case .staticPosture:
            return "Long still stretches keep recurring. Consider a sit-stand routine or moving a frequent task (calls, reading) away from the desk."
        }
    }
}
