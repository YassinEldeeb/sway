import Foundation

public enum BreakKind: String, Codable, Sendable {
    case micro       // stepped away briefly, or finished a short routine
    case long        // stepped away for several minutes, or took a guided break
}

public enum BreakSource: String, Codable, Sendable {
    case away            // no input observed for the whole period
    case sleep           // the Mac slept or the screen was locked
    case acknowledged    // a guided routine or break the user completed in Sway
}

public struct BreakRecord: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var kind: BreakKind
    public var source: BreakSource
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(start: Date, end: Date, kind: BreakKind, source: BreakSource) {
        self.start = start
        self.end = end
        self.kind = kind
        self.source = source
    }
}

/// What a tracker update changed. The store applies these to daily records,
/// splitting intervals that cross midnight.
public enum ActivityEvent: Equatable, Sendable {
    case active(from: Date, to: Date)
    /// Time that was credited as active but turned out to be the start of an
    /// away period (we only learn someone left once the idle timer passes the
    /// away threshold).
    case retractActive(from: Date, to: Date)
    case breakTaken(BreakRecord)
    /// An uninterrupted work stretch ended (by a break of at least micro size).
    case sessionEnded(start: Date, end: Date)
}

/// Tracks presence from the system's "seconds since last input" counter and
/// sleep/lock transitions. It never sees what was typed or where.
///
/// All methods take the current time explicitly so behaviour is
/// deterministic under test.
public struct ActivityTracker: Codable, Equatable, Sendable {
    public enum Mode: Codable, Equatable, Sendable {
        case active
        case away(since: Date)
        case asleep(since: Date)
    }

    public private(set) var mode: Mode = .active
    public private(set) var lastTick: Date?
    public private(set) var lastInputAt: Date?
    /// Start of the current uninterrupted work stretch.
    public private(set) var sessionStart: Date?
    public private(set) var lastMicroBreakEnd: Date?
    public private(set) var lastLongBreakEnd: Date?
    public private(set) var lastEyeRestAt: Date?
    /// Start of a guided break the user began in Sway, if one is running.
    public private(set) var guidedBreakStart: Date?

    /// A tick gap longer than this means the process was not running (sleep,
    /// suspension, debugger) and the gap must not be credited as work.
    public static let maxTickGap: TimeInterval = 90

    public init() {}

    public var isActive: Bool { if case .active = mode { return true } else { return false } }

    /// Reference point for "time since last movement break": the later of the
    /// last micro or long break, or the session start.
    public func lastMovement(fallback now: Date) -> Date {
        [lastMicroBreakEnd, lastLongBreakEnd, sessionStart].compactMap { $0 }.max() ?? now
    }

    public func lastLongBreak(fallback now: Date) -> Date {
        [lastLongBreakEnd, sessionStart].compactMap { $0 }.max() ?? now
    }

    public func continuousWork(at now: Date) -> TimeInterval {
        guard isActive, let s = sessionStart else { return 0 }
        return max(0, now.timeIntervalSince(s))
    }

    // MARK: Updates

    /// Regular sample. `idleSeconds` is the system's time since the last
    /// keyboard/mouse/trackpad event.
    public mutating func tick(now: Date, idleSeconds: TimeInterval, settings: CoachSettings) -> [ActivityEvent] {
        let idle = max(0, idleSeconds)
        let inputAt = now.addingTimeInterval(-idle)
        defer {
            lastTick = now
            lastInputAt = inputAt
        }
        guard let last = lastTick, now > last else {
            if lastTick == nil {
                if idle >= settings.awayThreshold {
                    mode = .away(since: inputAt)
                } else {
                    mode = .active
                    sessionStart = now
                }
            }
            return []
        }
        let gap = now.timeIntervalSince(last)
        var events: [ActivityEvent] = []

        switch mode {
        case .active:
            if gap > Self.maxTickGap {
                // We were not running. Whatever happened in between, the user
                // has been idle since `inputAt`; anything before that inside
                // the gap is unknown and treated as away.
                let awayStart = last
                if idle >= settings.awayThreshold {
                    mode = .away(since: awayStart)
                } else {
                    events += closeAway(start: awayStart, returnAt: max(last, inputAt), now: now, source: .away, settings: settings)
                }
            } else if idle >= settings.awayThreshold {
                // The user left at their last input. Retract the credit we gave
                // between that input and the previous tick.
                let leftAt = max(inputAt, sessionStart ?? inputAt)
                if leftAt < last {
                    events.append(.retractActive(from: leftAt, to: last))
                } else if leftAt > last {
                    events.append(.active(from: last, to: min(leftAt, now)))
                }
                mode = .away(since: min(leftAt, now))
            } else {
                events.append(.active(from: last, to: now))
            }

        case .away(let since), .asleep(let since):
            if idle < settings.awayThreshold {
                // Back. With regular ticks the return happened between the
                // previous tick and now; after a long gap we only know the
                // latest input, so use the earliest defensible moment.
                let returnAt = gap > Self.maxTickGap ? max(last, inputAt) : last
                let source: BreakSource
                if case .asleep = mode { source = .sleep } else { source = .away }
                events += closeAway(start: since, returnAt: max(returnAt, since), now: now, source: source, settings: settings)
            }
        }
        return events
    }

    /// The Mac is about to sleep, or the screen locked / user switched out.
    public mutating func suspend(now: Date, idleSeconds: TimeInterval, settings: CoachSettings) -> [ActivityEvent] {
        var events = tick(now: now, idleSeconds: idleSeconds, settings: settings)
        switch mode {
        case .active:
            mode = .asleep(since: now)
        case .away(let since):
            mode = .asleep(since: since)
        case .asleep:
            break
        }
        lastTick = now
        return events
    }

    /// The Mac woke or the screen unlocked. Presence resumes with the next
    /// tick that shows input.
    public mutating func resume(now: Date) {
        if case .active = mode {
            mode = .asleep(since: lastTick ?? now)
        }
        lastTick = now
    }

    /// A guided routine finished inside Sway (done at the desk, so clicking
    /// through steps is expected). Counts as a movement break.
    public mutating func completeRoutine(start: Date, end: Date) -> [ActivityEvent] {
        guard isActive, end.timeIntervalSince(start) >= 25 else { return [] }
        let record = BreakRecord(start: start, end: end, kind: .micro, source: .acknowledged)
        apply(record)
        return [.breakTaken(record)]
    }

    /// The user started a guided break ("Take 3 minutes").
    public mutating func beginGuidedBreak(at now: Date) {
        guidedBreakStart = now
    }

    public mutating func cancelGuidedBreak() {
        guidedBreakStart = nil
    }

    /// The guided break's timer ended. If the user is still away, the break
    /// is closed when they return (and counts from the guided start). If they
    /// stayed at the desk, it counts only when they were mostly not using the
    /// computer, so a "break" spent working does not reset the timers.
    public mutating func finishGuidedBreak(at now: Date, idleFraction: Double) -> [ActivityEvent] {
        guard let start = guidedBreakStart else { return [] }
        guard isActive else { return [] }
        guidedBreakStart = nil
        guard now.timeIntervalSince(start) >= 150, idleFraction >= 0.6 else { return [] }
        let record = BreakRecord(start: start, end: now, kind: .long, source: .acknowledged)
        var events: [ActivityEvent] = []
        if let s = sessionStart, start > s {
            events.append(.sessionEnded(start: s, end: start))
        }
        events.append(.breakTaken(record))
        apply(record)
        sessionStart = now
        return events
    }

    public mutating func acknowledgeEyeRest(at now: Date) {
        lastEyeRestAt = now
    }

    // MARK: Internals

    private mutating func closeAway(start awayStart: Date, returnAt: Date, now: Date, source awaySource: BreakSource, settings: CoachSettings) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        var start = awayStart
        var source = awaySource
        var longMin = settings.longBreakMinAway
        if let guided = guidedBreakStart {
            // The user left during a guided break: count it from the guided
            // start, and a guided break of 2.5+ minutes counts as long.
            guidedBreakStart = nil
            if guided < start {
                // The guided start was credited as active by earlier ticks.
                events.append(.retractActive(from: max(guided, sessionStart ?? guided), to: start))
                start = guided
            }
            source = .acknowledged
            longMin = min(longMin, 150)
        }
        let away = returnAt.timeIntervalSince(start)
        let kind: BreakKind?
        if away >= longMin {
            kind = .long
        } else if away >= settings.microBreakMinAway {
            kind = .micro
        } else {
            kind = nil
        }
        if let kind {
            let record = BreakRecord(start: start, end: returnAt, kind: kind, source: source)
            if let s = sessionStart, start > s {
                events.append(.sessionEnded(start: s, end: start))
            }
            events.append(.breakTaken(record))
            apply(record)
            sessionStart = returnAt
        } else if sessionStart == nil {
            sessionStart = returnAt
        }
        // A short absence (under the micro-break size) is not a break: the
        // work stretch continues and the time counts as work, matching how a
        // person thinking away from the keyboard is still working.
        if kind == nil, returnAt > start {
            events.append(.active(from: start, to: returnAt))
        }
        if now > returnAt {
            events.append(.active(from: returnAt, to: now))
        }
        mode = .active
        return events
    }

    private mutating func apply(_ record: BreakRecord) {
        switch record.kind {
        case .micro:
            lastMicroBreakEnd = max(lastMicroBreakEnd ?? record.end, record.end)
        case .long:
            lastLongBreakEnd = max(lastLongBreakEnd ?? record.end, record.end)
            lastMicroBreakEnd = max(lastMicroBreakEnd ?? record.end, record.end)
        }
        // Stepping away for a couple of minutes rests the eyes too.
        lastEyeRestAt = max(lastEyeRestAt ?? record.end, record.end)
    }
}
