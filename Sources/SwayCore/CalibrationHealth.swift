import Foundation

/// Notices when the calibration probably no longer describes the setup:
/// for ten minutes the face has sat far from where it was calibrated (much
/// further left or right, or a very different size), more than leaning or
/// sitting back explains. That usually means the laptop, monitor, camera or
/// chair moved. Ordinary posture changes stay well inside these limits, and
/// a brief period never counts.
///
/// While suspect, camera posture warnings stop; it clears by itself once the
/// position looks familiar again for a few minutes, or on recalibration.
public struct CalibrationHealthMonitor: Codable, Equatable, Sendable {
    struct Minute: Codable, Equatable, Sendable {
        var observed: Double = 0
        var off: Double = 0
    }

    /// Horizontal offset of the face centre, in image widths.
    public static let maxOffset = 0.22
    /// Face size relative to calibration.
    public static let maxSize = 1.8
    public static let minSize = 0.6

    static let window: TimeInterval = 10 * 60
    static let minObserved: TimeInterval = 5 * 60
    static let enterShare = 0.85
    static let clearWindow: TimeInterval = 3 * 60
    static let clearMinObserved: TimeInterval = 60
    static let clearShare = 0.3
    /// Longer than any frame interval in use (8 s, doubled on battery).
    static let maxStep: TimeInterval = 20

    private var seconds: [Int: Minute] = [:]   // keyed by 10-second slot
    private var lastAt: Date?
    public private(set) var suspectSince: Date?

    public init() {}

    public var isSuspect: Bool { suspectSince != nil }

    /// Whether a frame is far from the calibrated geometry.
    public static func isOff(offset: Double, sizeRatio: Double) -> Bool {
        offset > maxOffset || sizeRatio > maxSize || sizeRatio < minSize
    }

    /// `off`: nil when no single clear face was seen.
    public mutating func update(off: Bool?, at t: Date) {
        if let off {
            let step = lastAt.map { min(max(0, t.timeIntervalSince($0)), Self.maxStep) } ?? 0
            let slot = Self.slot(t)
            seconds[slot, default: Minute()].observed += step
            if off { seconds[slot, default: Minute()].off += step }
            lastAt = t
        } else if let last = lastAt, t.timeIntervalSince(last) > 45 {
            lastAt = nil
        }
        let oldest = Self.slot(t.addingTimeInterval(-Self.window)) - 1
        seconds = seconds.filter { $0.key >= oldest }

        if suspectSince == nil {
            let (obs, off) = sums(since: t.addingTimeInterval(-Self.window))
            if obs >= Self.minObserved, off / obs >= Self.enterShare { suspectSince = t }
        } else {
            let (obs, off) = sums(since: t.addingTimeInterval(-Self.clearWindow))
            if obs >= Self.clearMinObserved, off / obs <= Self.clearShare { suspectSince = nil }
        }
    }

    public mutating func reset() { self = CalibrationHealthMonitor() }

    private func sums(since: Date) -> (Double, Double) {
        let from = Self.slot(since)
        var obs = 0.0, off = 0.0
        for (k, v) in seconds where k > from {
            obs += v.observed
            off += v.off
        }
        return (obs, off)
    }

    static func slot(_ t: Date) -> Int { Int((t.timeIntervalSince1970 / 10).rounded(.down)) }
}
