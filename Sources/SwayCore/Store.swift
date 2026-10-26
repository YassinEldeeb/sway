import Foundation

extension PostureIssue: CodingKeyRepresentable {}
extension ReminderKind: CodingKeyRepresentable {}

/// A daily comfort check-in: 0 = no discomfort, 10 = worst imaginable.
/// Every area is optional, so the user can answer only what applies.
public struct ComfortCheckIn: Codable, Equatable, Sendable {
    public enum Area: String, CaseIterable, Sendable {
        case neck, upperBack, lowerBack, eyes

        public var title: String {
            switch self {
            case .neck: return "Neck"
            case .upperBack: return "Upper back"
            case .lowerBack: return "Lower back"
            case .eyes: return "Eye fatigue"
            }
        }
    }

    public var neck: Int?
    public var upperBack: Int?
    public var lowerBack: Int?
    public var eyes: Int?
    /// Check-ins from before the back was split into upper and lower. Kept
    /// as recorded; never copied into either new area.
    public var back: Int?
    public var note: String?
    public var at: Date

    public init(neck: Int? = nil, upperBack: Int? = nil, lowerBack: Int? = nil, eyes: Int? = nil, note: String? = nil, at: Date) {
        let clamp = { (v: Int?) in v.map { min(max($0, 0), 10) } }
        self.neck = clamp(neck)
        self.upperBack = clamp(upperBack)
        self.lowerBack = clamp(lowerBack)
        self.eyes = clamp(eyes)
        self.note = note.map { String($0.prefix(500)) }
        self.at = at
    }

    public subscript(area: Area) -> Int? {
        switch area {
        case .neck: return neck
        case .upperBack: return upperBack
        case .lowerBack: return lowerBack
        case .eyes: return eyes
        }
    }

    public var isEmpty: Bool { Area.allCases.allSatisfy { self[$0] == nil } && back == nil }

    enum CodingKeys: String, CodingKey { case neck, upperBack, lowerBack, eyes, back, note, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let clamp = { (v: Int?) in v.map { min(max($0, 0), 10) } }
        neck = clamp(c.lenient(Int.self, .neck))
        upperBack = clamp(c.lenient(Int.self, .upperBack))
        lowerBack = clamp(c.lenient(Int.self, .lowerBack))
        eyes = clamp(c.lenient(Int.self, .eyes))
        back = clamp(c.lenient(Int.self, .back))
        note = c.lenient(String.self, .note)
        at = try c.decode(Date.self, forKey: .at)
    }
}

public struct LogEntry: Codable, Equatable, Sendable {
    public var at: Date
    public var text: String

    public init(at: Date, text: String) {
        self.at = at
        self.text = text
    }
}

/// Everything Sway keeps about one local day. Derived numbers only: no
/// camera frames, no input content, no app or window names.
public struct DailyRecord: Codable, Equatable, Sendable {
    public var day: String
    public var activeSeconds: Double = 0
    /// Completed uninterrupted work stretches, in seconds.
    public var stretches: [Double] = []
    public var breaks: [BreakRecord] = []
    public var postureSeconds: [PostureIssue: Double] = [:]
    public var postureEpisodes: [PostureIssue: Int] = [:]
    public var cameraSeconds: Double = 0
    public var cameraReliableSeconds: Double = 0
    public var prompts: [ReminderKind: ResponseCounts] = [:]
    public var routinesCompleted = 0
    public var comfort: ComfortCheckIn?
    public var log: [LogEntry] = []
    /// Issues that came up often today in short bouts (see
    /// `FrequentPatternDetector`), with when they were first noticed.
    public var frequentPatterns: [PostureIssue: FrequentFlag] = [:]

    public static let maxBreaks = 300
    public static let maxStretches = 300
    public static let maxLog = 300

    public init(day: String) { self.day = day }

    enum CodingKeys: String, CodingKey {
        case day, activeSeconds, stretches, breaks, postureSeconds, postureEpisodes, cameraSeconds, cameraReliableSeconds, prompts, routinesCompleted, comfort, log, frequentPatterns
    }

    /// Tolerant: a field added by a newer version, or one damaged value,
    /// never makes the whole day unreadable (which would lose it).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        activeSeconds = c.lenient(Double.self, .activeSeconds) ?? 0
        stretches = c.lenient([Double].self, .stretches) ?? []
        breaks = c.lenientList(BreakRecord.self, .breaks) ?? []
        postureSeconds = c.lenientMap(PostureIssue.self, Double.self, .postureSeconds) ?? [:]
        postureEpisodes = c.lenientMap(PostureIssue.self, Int.self, .postureEpisodes) ?? [:]
        cameraSeconds = c.lenient(Double.self, .cameraSeconds) ?? 0
        cameraReliableSeconds = c.lenient(Double.self, .cameraReliableSeconds) ?? 0
        prompts = c.lenientMap(ReminderKind.self, ResponseCounts.self, .prompts) ?? [:]
        routinesCompleted = c.lenient(Int.self, .routinesCompleted) ?? 0
        comfort = c.lenient(ComfortCheckIn.self, .comfort)
        log = c.lenientList(LogEntry.self, .log) ?? []
        frequentPatterns = c.lenientMap(PostureIssue.self, FrequentFlag.self, .frequentPatterns) ?? [:]
    }

    public var longestStretch: Double { stretches.max() ?? 0 }

    public var meaningfulBreaks: Int { breaks.count }

    public var medianStretch: Double? {
        guard !stretches.isEmpty else { return nil }
        return stretches.sorted()[stretches.count / 2]
    }

    public var totalPostureSeconds: Double { postureSeconds.values.reduce(0, +) }

    mutating func appendLog(_ text: String, at: Date) {
        log.append(LogEntry(at: at, text: text))
        if log.count > Self.maxLog { log.removeFirst(log.count - Self.maxLog) }
    }
}

public enum DayKey {
    public static func key(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Splits [from, to) at local midnights.
    public static func split(from: Date, to: Date, calendar: Calendar = .current) -> [(day: String, seconds: Double)] {
        guard to > from else { return [] }
        var out: [(String, Double)] = []
        var cursor = from
        while cursor < to {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? to
            let end = min(midnight, to)
            out.append((key(cursor, calendar: calendar), end.timeIntervalSince(cursor)))
            cursor = end
        }
        return out
    }
}

/// Applies tracker and posture events to daily records. Pure value type so
/// accounting is testable without the file system.
public struct Ledger: Equatable {
    public var records: [String: DailyRecord] = [:]
    /// Loads a day that isn't in memory, so an event for an earlier day (an
    /// overnight absence closing in the morning) updates that day's saved
    /// record instead of replacing it with an empty one.
    public var loader: ((String) -> DailyRecord?)?

    public init(records: [String: DailyRecord] = [:], loader: ((String) -> DailyRecord?)? = nil) {
        self.records = records
        self.loader = loader
    }

    public static func == (a: Ledger, b: Ledger) -> Bool { a.records == b.records }

    public func record(_ day: String) -> DailyRecord {
        records[day] ?? loader?(day) ?? DailyRecord(day: day)
    }

    public mutating func note(_ text: String, at: Date, calendar: Calendar = .current) {
        update(DayKey.key(at, calendar: calendar)) { $0.appendLog(text, at: at) }
    }

    public mutating func update(_ day: String, _ f: (inout DailyRecord) -> Void) {
        var r = record(day)
        f(&r)
        records[day] = r
    }

    public mutating func apply(_ events: [ActivityEvent], calendar: Calendar = .current) {
        for e in events {
            switch e {
            case .active(let from, let to):
                for part in DayKey.split(from: from, to: to, calendar: calendar) {
                    update(part.day) { $0.activeSeconds += part.seconds }
                }
            case .retractActive(let from, let to):
                for part in DayKey.split(from: from, to: to, calendar: calendar) {
                    update(part.day) { $0.activeSeconds = max(0, $0.activeSeconds - part.seconds) }
                }
            case .breakTaken(let b):
                update(DayKey.key(b.end, calendar: calendar)) { r in
                    r.breaks.append(b)
                    if r.breaks.count > DailyRecord.maxBreaks { r.breaks.removeFirst(r.breaks.count - DailyRecord.maxBreaks) }
                    r.appendLog("\(b.kind == .long ? "Break" : "Short break") (\(Format.duration(b.duration)), \(b.source.rawValue))", at: b.end)
                }
            case .sessionEnded(let start, let end):
                update(DayKey.key(end, calendar: calendar)) { r in
                    r.stretches.append(end.timeIntervalSince(start))
                    if r.stretches.count > DailyRecord.maxStretches { r.stretches.removeFirst(r.stretches.count - DailyRecord.maxStretches) }
                }
            }
        }
    }

    public mutating func apply(_ episode: PostureEpisode, calendar: Calendar = .current) {
        for part in DayKey.split(from: episode.start, to: episode.end, calendar: calendar) {
            update(part.day) { $0.postureSeconds[episode.issue, default: 0] += part.seconds }
        }
        update(DayKey.key(episode.start, calendar: calendar)) { r in
            r.postureEpisodes[episode.issue, default: 0] += 1
            r.appendLog("\(episode.issue.title) for \(Format.duration(episode.duration))", at: episode.end)
        }
    }

    public mutating func addCamera(seconds: Double, reliable: Bool, at: Date, calendar: Calendar = .current) {
        update(DayKey.key(at, calendar: calendar)) { r in
            r.cameraSeconds += seconds
            if reliable { r.cameraReliableSeconds += seconds }
        }
    }

    public mutating func prompted(_ kind: ReminderKind, at: Date, calendar: Calendar = .current) {
        update(DayKey.key(at, calendar: calendar)) { r in
            r.prompts[kind, default: ResponseCounts()].prompts += 1
            r.appendLog("Reminder: \(kind.title)", at: at)
        }
    }

    public mutating func responded(_ kind: ReminderKind, _ response: PromptResponse, at: Date, calendar: Calendar = .current) {
        update(DayKey.key(at, calendar: calendar)) { r in
            r.prompts[kind, default: ResponseCounts()].add(response)
        }
    }

    public mutating func routineCompleted(at: Date, calendar: Calendar = .current) {
        update(DayKey.key(at, calendar: calendar)) { $0.routinesCompleted += 1 }
    }

    /// Records the first time today an issue was found recurring in short
    /// bouts. Later flags the same day change nothing.
    @discardableResult
    public mutating func flagFrequent(_ issue: PostureIssue, _ flag: FrequentFlag, calendar: Calendar = .current) -> Bool {
        let day = DayKey.key(flag.at, calendar: calendar)
        guard record(day).frequentPatterns[issue] == nil else { return false }
        update(day) { r in
            r.frequentPatterns[issue] = flag
            r.appendLog("Recurring in short bouts: \(issue.title.lowercased()) (\(Int((flag.share * 100).rounded()))% of \(Int(flag.observedMinutes.rounded())) min observed, \(flag.bouts) bouts)", at: flag.at)
        }
        return true
    }

    public mutating func setComfort(_ c: ComfortCheckIn, calendar: Calendar = .current) {
        update(DayKey.key(c.at, calendar: calendar)) { $0.comfort = c }
    }
}

/// State that survives an app restart so timers don't reset on relaunch.
public struct RuntimeState: Codable, Equatable, Sendable {
    public var tracker = ActivityTracker()
    public var engine = InterventionEngine()
    public var pausedUntil: Date?
    public var setupChecklist: [String: String] = [:]
    public var setupMeasurements: [String: Double] = [:]
    /// What Sway decided about reminders, newest last.
    public var decisionLog = DecisionLog()
    public init() {}

    enum CodingKeys: String, CodingKey { case tracker, engine, pausedUntil, setupChecklist, setupMeasurements, decisionLog }

    /// Tolerant: missing or damaged parts fall back to defaults one by one,
    /// so timers survive an upgrade.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracker = c.lenient(ActivityTracker.self, .tracker) ?? ActivityTracker()
        engine = c.lenient(InterventionEngine.self, .engine) ?? InterventionEngine()
        pausedUntil = c.lenient(Date.self, .pausedUntil)
        setupChecklist = c.lenient([String: String].self, .setupChecklist) ?? [:]
        setupMeasurements = c.lenient([String: Double].self, .setupMeasurements) ?? [:]
        decisionLog = c.lenient(DecisionLog.self, .decisionLog) ?? DecisionLog()
    }
}

/// JSON files under Application Support. Small, human-inspectable, written
/// atomically, pruned by retention.
public final class SwayStore {
    public let directory: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(SwayStore.iso.string(from: date))
        }
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let text = try c.decode(String.self)
            if let date = SwayStore.iso.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(text)")
        }
        return d
    }()

    /// ISO 8601 with milliseconds, so timers restored after a relaunch don't
    /// shift by a fraction of a second.
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Sway", isDirectory: true)
    }

    private var daysDir: URL { directory.appendingPathComponent("days", isDirectory: true) }

    private func ensureDirs() throws {
        try fm.createDirectory(at: daysDir, withIntermediateDirectories: true)
    }

    private func read<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ url: URL) throws {
        try ensureDirs()
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    public func loadSettings() -> CoachSettings {
        (read(CoachSettings.self, directory.appendingPathComponent("settings.json")) ?? CoachSettings()).sanitized()
    }

    public func save(_ s: CoachSettings) throws { try write(s, directory.appendingPathComponent("settings.json")) }

    public func loadCalibration() -> Calibration? { read(Calibration.self, directory.appendingPathComponent("calibration.json")) }

    public func save(_ c: Calibration?) throws {
        let url = directory.appendingPathComponent("calibration.json")
        if let c { try write(c, url) } else { try? fm.removeItem(at: url) }
    }

    public func loadRuntime() -> RuntimeState { read(RuntimeState.self, directory.appendingPathComponent("state.json")) ?? RuntimeState() }

    public func save(_ r: RuntimeState) throws { try write(r, directory.appendingPathComponent("state.json")) }

    /// A day file that exists but can't be read is moved aside, never
    /// overwritten, so a bug can't silently erase a day.
    public func loadDay(_ day: String) -> DailyRecord? {
        let url = daysDir.appendingPathComponent("\(day).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let r = try? decoder.decode(DailyRecord.self, from: data) { return r }
        let aside = daysDir.appendingPathComponent("\(day).unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? fm.moveItem(at: url, to: aside)
        return nil
    }

    public func save(_ r: DailyRecord) throws { try write(r, daysDir.appendingPathComponent("\(r.day).json")) }

    /// Most recent `days` local days ending today, oldest first, including
    /// empty records for days with no file.
    public func recent(days: Int, now: Date, calendar: Calendar = .current) -> [DailyRecord] {
        (0..<days).reversed().map { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let key = DayKey.key(d, calendar: calendar)
            return loadDay(key) ?? DailyRecord(day: key)
        }
    }

    /// Deletes daily files older than the retention window. Returns the
    /// number removed.
    @discardableResult
    public func prune(retentionDays: Int, now: Date, calendar: Calendar = .current) -> Int {
        guard let files = try? fm.contentsOfDirectory(at: daysDir, includingPropertiesForKeys: nil) else { return 0 }
        let cutoff = DayKey.key(calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now, calendar: calendar)
        var removed = 0
        for f in files where f.pathExtension == "json" {
            let day = f.deletingPathExtension().lastPathComponent
            if day < cutoff {
                if (try? fm.removeItem(at: f)) != nil { removed += 1 }
            }
        }
        return removed
    }

    /// Removes every file Sway stored.
    public func deleteAll() throws {
        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
    }

    public func storedDayCount() -> Int {
        (try? fm.contentsOfDirectory(atPath: daysDir.path).filter { $0.hasSuffix(".json") && $0.count == 15 }.count) ?? 0
    }

    public func totalBytes() -> Int {
        guard let e = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in e {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
