import Foundation

/// Per-kind prompt outcomes, summed over a rolling window of daily records.
public struct ResponseCounts: Codable, Equatable, Sendable {
    public var prompts = 0
    public var accepted = 0
    public var snoozed = 0
    public var dismissed = 0
    public var unhelpful = 0
    public var helpful = 0

    public init() {}

    public mutating func add(_ r: PromptResponse) {
        switch r {
        case .accepted: accepted += 1
        case .snoozed: snoozed += 1
        case .dismissed: dismissed += 1
        case .unhelpful: unhelpful += 1
        case .helpful: helpful += 1
        }
    }

    public static func + (a: Self, b: Self) -> Self {
        var c = a
        c.prompts += b.prompts
        c.accepted += b.accepted
        c.snoozed += b.snoozed
        c.dismissed += b.dismissed
        c.unhelpful += b.unhelpful
        c.helpful += b.helpful
        return c
    }
}

/// What personalization changed, with a plain-language reason for each
/// change. Deterministic and bounded: it can space reminders out by at most
/// 50% and make posture detection at most 60% less sensitive. It never makes
/// Sway more insistent than the user's settings.
public struct Adjustments: Equatable, Sendable {
    public var intervalMultipliers: [ReminderKind: Double] = [:]
    public var cooldownMultipliers: [ReminderKind: Double] = [:]
    public var thresholdScales: [PostureIssue: Double] = [:]
    public var explanations: [String] = []

    public static let neutral = Adjustments()

    public init() {}

    public func intervalMultiplier(_ k: ReminderKind) -> Double { intervalMultipliers[k] ?? 1 }
    public func cooldownMultiplier(_ k: ReminderKind) -> Double { cooldownMultipliers[k] ?? 1 }
    public func thresholdScale(_ i: PostureIssue) -> Double { thresholdScales[i] ?? 1 }
}

public enum Personalization {
    /// Fewer prompts than this in the window: not enough evidence to adapt.
    public static let minPrompts = 4

    public static func compute(counts: [ReminderKind: ResponseCounts], naturalStretches: [TimeInterval] = []) -> Adjustments {
        var adj = Adjustments()
        for (kind, c) in counts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let n = max(c.prompts, c.accepted + c.snoozed + c.dismissed + c.unhelpful)
            guard n >= minPrompts else { continue }
            let negative = Double(c.dismissed + c.unhelpful) / Double(n)
            let accepted = Double(c.accepted) / Double(n)
            let snoozed = Double(c.snoozed) / Double(n)

            if kind.isBreak || kind == .eyeRest {
                var m = 1.0
                if negative > 0.5, accepted < 0.4 {
                    m = 1 + min(0.5, (negative - 0.5))   // up to 1.5x at 100% dismissals
                } else if snoozed >= 0.5 {
                    m = 1.15
                }
                if m > 1.001 {
                    adj.intervalMultipliers[kind] = m
                    adj.explanations.append("\(kind.title) reminders come \(Int(((m - 1) * 100).rounded()))% later: you \(negative > 0.5 ? "dismissed" : "snoozed") most of the last \(n).")
                }
            }

            if let issue = kind.postureIssue {
                let net = c.unhelpful - c.helpful
                if net >= 2 {
                    let scale = min(1.6, 1 + 0.15 * Double(net))
                    adj.thresholdScales[issue] = scale
                    adj.explanations.append("\(issue.title) needs a \(Int(((scale - 1) * 100).rounded()))% larger deviation before it counts: you marked \(c.unhelpful) of these not helpful.")
                }
                if negative > 0.5 {
                    adj.cooldownMultipliers[kind] = 2
                    adj.explanations.append("\(issue.title) notifications are spaced twice as far apart.")
                }
            }
        }
        if naturalStretches.count >= 5 {
            let median = naturalStretches.sorted()[naturalStretches.count / 2]
            adj.explanations.append("On your own you usually take a break after about \(Format.duration(median)) of work.")
        }
        return adj
    }
}
