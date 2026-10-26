import Foundation

public struct DecisionLogEntry: Codable, Equatable, Sendable {
    public var at: Date
    public var kind: ReminderKind?
    public var text: String

    public init(at: Date, kind: ReminderKind?, text: String) {
        self.at = at
        self.kind = kind
        self.text = text
    }
}

/// A plain record of what Sway decided about reminders and why: sent,
/// waiting (with the reason), held, removed as no longer relevant, answered.
/// Only changes are written, so a reminder that waits for ten minutes is one
/// line, not 120.
public struct DecisionLog: Codable, Equatable, Sendable {
    public private(set) var entries: [DecisionLogEntry] = []
    /// Last logged state per reminder occurrence.
    private var lastState: [String: String] = [:]
    private var lastKind: [String: ReminderKind] = [:]
    private var lastHold: String?

    public static let maxEntries = 200

    public init() {}

    enum CodingKeys: String, CodingKey { case entries, lastState, lastKind, lastHold }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = c.lenientList(DecisionLogEntry.self, .entries) ?? []
        lastState = c.lenient([String: String].self, .lastState) ?? [:]
        lastKind = (c.lenient([String: Lossy<ReminderKind>].self, .lastKind) ?? [:]).compactMapValues(\.value)
        lastHold = c.lenient(String.self, .lastHold)
    }

    public mutating func record(_ d: InterventionDecision, now: Date) {
        let hold = d.hold?.label
        if hold != lastHold {
            if let hold {
                add(now, nil, "Reminders held: \(hold)")
            } else if lastHold != nil {
                add(now, nil, "Hold ended; reminders resume after a short pause")
            }
            lastHold = hold
        }
        var seen = Set<String>()
        for s in d.statuses {
            let id = s.reminder.instanceID
            seen.insert(id)
            lastKind[id] = s.reminder.kind
            // While held, the hold line above says it all.
            if case .held = s.state { continue }
            let label = s.explanation
            if lastState[id] != label {
                add(now, s.reminder.kind, "\(s.reminder.title): \(label)")
                lastState[id] = label
            }
        }
        for k in d.expired {
            add(now, k, "\(k.title): notification removed because it no longer applies")
        }
        for (id, _) in lastState where !seen.contains(id) {
            if let k = lastKind[id] { add(now, k, "\(k.title): no longer due") }
            lastState[id] = nil
            lastKind[id] = nil
        }
        lastKind = lastKind.filter { lastState[$0.key] != nil || seen.contains($0.key) }
    }

    /// A user response or another event worth keeping next to the decisions.
    public mutating func note(_ text: String, kind: ReminderKind?, at: Date) {
        add(at, kind, text)
    }

    /// The occurrence was answered: forget its state so the disappearance
    /// isn't logged as "no longer due".
    public mutating func answered(_ instanceID: String) {
        lastState[instanceID] = nil
        lastKind[instanceID] = nil
    }

    private mutating func add(_ at: Date, _ kind: ReminderKind?, _ text: String) {
        entries.append(DecisionLogEntry(at: at, kind: kind, text: text))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }
}
