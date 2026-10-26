import Foundation

public struct Point2: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// One processed camera frame, reduced to the few numbers Sway uses. The
/// frame itself is discarded before this exists. Coordinates are normalized
/// to the image (0...1, origin bottom-left, as Vision reports them); angles
/// are in degrees.
public struct PostureObservation: Equatable, Sendable {
    public var timestamp: Date
    public var faceCount: Int
    public var faceConfidence: Double
    public var faceCenter: Point2?
    public var faceHeight: Double?
    public var pitch: Double?
    public var yaw: Double?
    public var roll: Double?
    public var leftShoulder: Point2?
    public var rightShoulder: Point2?
    public var shoulderConfidence: Double

    public init(timestamp: Date, faceCount: Int = 1, faceConfidence: Double, faceCenter: Point2?, faceHeight: Double?,
                pitch: Double? = nil, yaw: Double? = nil, roll: Double? = nil,
                leftShoulder: Point2? = nil, rightShoulder: Point2? = nil, shoulderConfidence: Double = 0) {
        self.timestamp = timestamp
        self.faceCount = faceCount
        self.faceConfidence = faceConfidence
        self.faceCenter = faceCenter
        self.faceHeight = faceHeight
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.shoulderConfidence = shoulderConfidence
    }

    public static func noFace(at t: Date) -> PostureObservation {
        PostureObservation(timestamp: t, faceCount: 0, faceConfidence: 0, faceCenter: nil, faceHeight: nil)
    }

    /// Degrees; positive when the user's left shoulder (image right) is higher.
    public var shoulderSlope: Double? {
        guard let l = leftShoulder, let r = rightShoulder, shoulderConfidence >= 0.4 else { return nil }
        let dx = l.x - r.x
        guard abs(dx) > 0.02 else { return nil }
        return atan2(l.y - r.y, dx) * 180 / .pi
    }
}

/// Exponential moving average that respects irregular sample spacing.
public struct Smoother: Codable, Equatable, Sendable {
    public var tau: TimeInterval
    public var resetAfter: TimeInterval
    public private(set) var value: Double?
    private var at: Date?

    public init(tau: TimeInterval = 8, resetAfter: TimeInterval = 30) {
        self.tau = tau
        self.resetAfter = resetAfter
    }

    @discardableResult
    public mutating func update(_ x: Double, at t: Date) -> Double {
        if let v = value, let last = at {
            let dt = t.timeIntervalSince(last)
            if dt > resetAfter || dt < 0 {
                value = x
            } else {
                let alpha = 1 - exp(-dt / tau)
                value = v + alpha * (x - v)
            }
        } else {
            value = x
        }
        at = t
        return value!
    }

    public mutating func reset() {
        value = nil
        at = nil
    }
}

/// Turns a noisy per-sample deviation into sustained episodes.
///
/// - The value must stay at or above `enter` for `minDuration` (dips shorter
///   than `dipTolerance` are ignored) before an episode starts.
/// - An episode ends only after the value stays below `exit` (< `enter`) for
///   `exitDuration` — the hysteresis band stops oscillation.
/// - Unknown samples (no face, low confidence) never count as deviation. A
///   gap of unknown longer than `maxUnknownGap` cancels a pending episode and
///   ends an active one at the last time it was actually observed.
public struct SustainedDetector: Codable, Equatable, Sendable {
    public enum Phase: Codable, Equatable, Sendable {
        case idle
        case pending(since: Date, lastAbove: Date)
        case active(since: Date, lastAbove: Date, peak: Double)
    }

    public enum Event: Equatable, Sendable {
        case started(since: Date)
        case ended(start: Date, end: Date, peak: Double)
    }

    public var enter: Double
    public var exit: Double
    public var minDuration: TimeInterval
    public var exitDuration: TimeInterval
    public var dipTolerance: TimeInterval
    public var maxUnknownGap: TimeInterval
    public private(set) var phase: Phase = .idle
    public private(set) var lastKnown: Date?
    private var belowSince: Date?

    public init(enter: Double, exit: Double, minDuration: TimeInterval, exitDuration: TimeInterval = 20, dipTolerance: TimeInterval = 20, maxUnknownGap: TimeInterval = 45) {
        self.enter = enter
        self.exit = min(exit, enter)
        self.minDuration = minDuration
        self.exitDuration = exitDuration
        self.dipTolerance = dipTolerance
        self.maxUnknownGap = maxUnknownGap
    }

    public var isActive: Bool { if case .active = phase { return true } else { return false } }

    public var activeSince: Date? { if case .active(let s, _, _) = phase { return s } else { return nil } }

    public mutating func update(_ value: Double?, at t: Date) -> [Event] {
        var events: [Event] = []
        if let last = lastKnown, t.timeIntervalSince(last) > maxUnknownGap {
            events += expire(lastSeen: last)
        }
        guard let v = value else { return events }
        lastKnown = t

        switch phase {
        case .idle:
            if v >= enter {
                phase = .pending(since: t, lastAbove: t)
                if minDuration <= 0 {
                    phase = .active(since: t, lastAbove: t, peak: v)
                    events.append(.started(since: t))
                }
            }
        case .pending(let since, let lastAbove):
            if v >= enter {
                if t.timeIntervalSince(since) >= minDuration {
                    phase = .active(since: since, lastAbove: t, peak: v)
                    belowSince = nil
                    events.append(.started(since: since))
                } else {
                    phase = .pending(since: since, lastAbove: t)
                }
            } else if t.timeIntervalSince(lastAbove) > dipTolerance {
                phase = .idle
            }
        case .active(let since, _, let peak):
            if v >= exit {
                phase = .active(since: since, lastAbove: t, peak: max(peak, v))
                belowSince = nil
            } else {
                let below = belowSince ?? t
                belowSince = below
                if t.timeIntervalSince(below) >= exitDuration {
                    events.append(.ended(start: since, end: below, peak: peak))
                    phase = .idle
                    belowSince = nil
                }
            }
        }
        return events
    }

    /// Ends or cancels the current state because observation stopped (camera
    /// paused, user away). An active episode ends where it was last seen.
    public mutating func expire(lastSeen: Date? = nil) -> [Event] {
        defer {
            phase = .idle
            belowSince = nil
            lastKnown = nil
        }
        if case .active(let since, let lastAbove, let peak) = phase {
            let end = min(lastSeen ?? lastAbove, belowSince ?? .distantFuture)
            return [.ended(start: since, end: max(end, since), peak: peak)]
        }
        return []
    }
}

/// Head-movement variability over a rolling window, in face heights.
public struct MotionWindow: Codable, Equatable, Sendable {
    public var span: TimeInterval
    private var samples: [Sample] = []

    struct Sample: Codable, Equatable, Sendable {
        var t: Date
        var x: Double
        var y: Double
        var roll: Double
    }

    public init(span: TimeInterval = 5 * 60) { self.span = span }

    public mutating func add(t: Date, x: Double, y: Double, roll: Double) {
        samples.append(Sample(t: t, x: x, y: y, roll: roll))
        samples.removeAll { t.timeIntervalSince($0.t) > span }
        if samples.count > 600 { samples.removeFirst(samples.count - 600) }
    }

    public mutating func clear() { samples.removeAll() }

    public var count: Int { samples.count }

    /// Window covers at least this fraction of `span`.
    public func covers(_ fraction: Double) -> Bool {
        guard let first = samples.first, let last = samples.last else { return false }
        return last.t.timeIntervalSince(first.t) >= span * fraction
    }

    /// Combined standard deviation of position (face heights) plus head roll
    /// (scaled so 30° counts like one face height).
    public var motion: Double {
        guard samples.count >= 3 else { return .infinity }
        func sd(_ k: KeyPath<Sample, Double>) -> Double {
            let xs = samples.map { $0[keyPath: k] }
            let m = xs.reduce(0, +) / Double(xs.count)
            return sqrt(xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count))
        }
        let pos = sqrt(pow(sd(\.x), 2) + pow(sd(\.y), 2))
        return pos + sd(\.roll) / 30
    }
}
