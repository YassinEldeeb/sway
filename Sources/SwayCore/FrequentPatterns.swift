import Foundation

/// Conservative limits for noticing an issue that keeps coming back in short
/// bouts within one session, none long enough to count as sustained.
public struct FrequentPatternSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// The rolling window looked at.
    public var window: TimeInterval = 60 * 60
    /// Reliable camera time needed inside the window before anything counts.
    public var minObserved: TimeInterval = 30 * 60
    /// A bout over the line shorter than this is ordinary movement.
    public var minBout: TimeInterval = 30
    /// Separate bouts needed (head down, leaning in).
    public var minBouts = 4
    /// Share of observed time spent in such bouts (head down, leaning in).
    public var minShare = 0.35
    /// Share of observed time with very little movement.
    public var stillShare = 0.7

    public init() {}

    func sanitized() -> FrequentPatternSettings {
        var s = self
        s.window = s.window.clamped(20 * 60, 4 * 3600)
        s.minObserved = s.minObserved.clamped(10 * 60, s.window)
        s.minBout = s.minBout.clamped(10, 10 * 60)
        s.minBouts = s.minBouts.clamped(2, 50)
        s.minShare = s.minShare.clamped(0.15, 0.9)
        s.stillShare = s.stillShare.clamped(0.4, 0.95)
        return s
    }
}

/// What was noticed: share of reliable camera time over the line, how many
/// separate bouts, and how much reliable time the estimate rests on.
public struct FrequentFlag: Codable, Equatable, Sendable {
    public var at: Date
    public var share: Double
    public var bouts: Int
    public var observedMinutes: Double

    public init(at: Date, share: Double, bouts: Int, observedMinutes: Double) {
        self.at = at
        self.share = share
        self.bouts = bouts
        self.observedMinutes = observedMinutes
    }
}

/// Rolling-window counterpart of `SustainedDetector`. It doesn't produce
/// posture reminders; a flag feeds the once-a-day workstation suggestion.
///
/// - Only reliable observations count; unknown time (no face, low
///   confidence, camera off) is neither "over" nor "observed".
/// - Time over the line counts only inside bouts of at least `minBout`
///   (brief glances and shifts are ordinary movement). A dip of up to 10 s
///   doesn't end a bout; a 45 s gap in observation does.
/// - Deterministic: time is passed in.
public struct FrequentPatternDetector: Codable, Equatable, Sendable {
    struct Minute: Codable, Equatable, Sendable {
        var observed: Double = 0
        var over: Double = 0
        var bouts = 0
    }

    struct Track: Codable, Equatable, Sendable {
        var minutes: [Int: Minute] = [:]
        var boutStart: Date?
        var lastOver: Date?
        var lastKnown: Date?
    }

    /// The issues watched this way.
    public static let issues: [PostureIssue] = [.headDown, .forwardLean, .staticPosture]
    static let dipTolerance: TimeInterval = 10
    static let maxGap: TimeInterval = 45
    static let maxStep: TimeInterval = 10

    private var tracks: [PostureIssue: Track] = [:]

    public init() {}

    /// `over`: nil when unknown, else whether the value is over the line.
    public mutating func update(_ issue: PostureIssue, over: Bool?, at t: Date, settings: FrequentPatternSettings) {
        var tr = tracks[issue] ?? Track()
        if let known = tr.lastKnown, t.timeIntervalSince(known) > Self.maxGap {
            close(&tr, end: tr.lastOver ?? known, settings: settings)
            tr.lastKnown = nil
        }
        if let over {
            let step = tr.lastKnown.map { min(max(0, t.timeIntervalSince($0)), Self.maxStep) } ?? 0
            tr.minutes[Self.minute(t), default: Minute()].observed += step
            tr.lastKnown = t
            if over {
                if tr.boutStart == nil { tr.boutStart = t }
                tr.lastOver = t
            } else if tr.boutStart != nil, let last = tr.lastOver, t.timeIntervalSince(last) > Self.dipTolerance {
                close(&tr, end: last, settings: settings)
            }
        }
        let oldest = Self.minute(t.addingTimeInterval(-settings.window)) - 2
        tr.minutes = tr.minutes.filter { $0.key >= oldest }
        tracks[issue] = tr
    }

    /// Camera stopped: bouts in progress end where they were last seen.
    public mutating func stop(settings: FrequentPatternSettings) {
        for (issue, var tr) in tracks {
            close(&tr, end: tr.lastOver ?? tr.lastKnown ?? .distantPast, settings: settings)
            tr.lastKnown = nil
            tracks[issue] = tr
        }
    }

    public mutating func reset() { tracks = [:] }

    private mutating func close(_ tr: inout Track, end: Date, settings: FrequentPatternSettings) {
        defer { tr.boutStart = nil; tr.lastOver = nil }
        guard let start = tr.boutStart else { return }
        let length = end.timeIntervalSince(start)
        guard length >= settings.minBout else { return }
        tr.minutes[Self.minute(end), default: Minute()].over += length
        tr.minutes[Self.minute(end), default: Minute()].bouts += 1
    }

    /// The flag for `issue` over the window ending at `now`, or nil when the
    /// evidence isn't strong enough.
    public func assess(_ issue: PostureIssue, now: Date, settings: FrequentPatternSettings) -> FrequentFlag? {
        guard settings.enabled, let tr = tracks[issue] else { return nil }
        let from = Self.minute(now.addingTimeInterval(-settings.window))
        var observed = 0.0, over = 0.0, bouts = 0
        for (m, v) in tr.minutes where m > from {
            observed += v.observed
            over += v.over
            bouts += v.bouts
        }
        if let start = tr.boutStart, let last = tr.lastOver, last.timeIntervalSince(start) >= settings.minBout {
            over += last.timeIntervalSince(start)
            bouts += 1
        }
        guard observed >= settings.minObserved else { return nil }
        let share = min(1, over / observed)
        let flagged = issue == .staticPosture
            ? share >= settings.stillShare
            : share >= settings.minShare && bouts >= settings.minBouts
        return flagged ? FrequentFlag(at: now, share: share, bouts: bouts, observedMinutes: observed / 60) : nil
    }

    static func minute(_ t: Date) -> Int { Int((t.timeIntervalSince1970 / 60).rounded(.down)) }
}
