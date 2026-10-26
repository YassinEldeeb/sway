import Foundation

/// A sustained posture pattern the camera can estimate. These are
/// camera-relative estimates against the user's own calibrated baseline,
/// not measurements of the spine.
public enum PostureIssue: String, Codable, CaseIterable, Sendable {
    case headDown
    case forwardLean
    case lateralTilt
    case shoulderAsymmetry
    case staticPosture

    public var title: String {
        switch self {
        case .headDown: return "Head tilted down"
        case .forwardLean: return "Leaning toward the screen"
        case .lateralTilt: return "Head tilted to one side"
        case .shoulderAsymmetry: return "Uneven shoulders"
        case .staticPosture: return "Little movement"
        }
    }

    /// How the estimate is made, shown next to every number in the UI.
    public var definition: String {
        switch self {
        case .headDown:
            return "Your head is lower and/or pitched down compared with your calibrated working position, for several minutes in a row."
        case .forwardLean:
            return "Your face appears noticeably larger to the camera than in your calibrated position, which usually means you moved closer to the screen."
        case .lateralTilt:
            return "Your head is rolled to one side compared with your calibrated position."
        case .shoulderAsymmetry:
            return "The line between your shoulders is tilted compared with calibration. Only measured when both shoulders are clearly visible."
        case .staticPosture:
            return "Your head position has barely changed for a long stretch. Varying position matters more than any single 'correct' posture."
        }
    }
}

/// Everything Sway can prompt about.
public enum ReminderKind: String, Codable, CaseIterable, Sendable, Hashable {
    case microBreak
    case longBreak
    case longSession
    case eyeRest
    case headDown
    case forwardLean
    case lateralTilt
    case shoulderAsymmetry
    case staticPosture
    case workstationReview

    public init(_ issue: PostureIssue) {
        switch issue {
        case .headDown: self = .headDown
        case .forwardLean: self = .forwardLean
        case .lateralTilt: self = .lateralTilt
        case .shoulderAsymmetry: self = .shoulderAsymmetry
        case .staticPosture: self = .staticPosture
        }
    }

    public var postureIssue: PostureIssue? {
        switch self {
        case .headDown: return .headDown
        case .forwardLean: return .forwardLean
        case .lateralTilt: return .lateralTilt
        case .shoulderAsymmetry: return .shoulderAsymmetry
        case .staticPosture: return .staticPosture
        default: return nil
        }
    }

    public var isBreak: Bool { self == .microBreak || self == .longBreak || self == .longSession }

    public var title: String {
        switch self {
        case .microBreak: return "Movement break"
        case .longBreak: return "Longer break"
        case .longSession: return "Long session"
        case .eyeRest: return "Eye rest"
        case .workstationReview: return "Workstation check"
        default: return postureIssue?.title ?? rawValue
        }
    }
}

/// How the user responded to a prompt. Drives personalization.
public enum PromptResponse: String, Codable, CaseIterable, Sendable {
    case accepted     // started a routine or break from the prompt
    case snoozed
    case dismissed    // closed it without acting
    case unhelpful    // explicitly marked "not helpful"
    case helpful      // explicitly said it helped
}

/// Intervention levels from the product spec.
public enum InterventionLevel: Int, Codable, Comparable, Sendable {
    case passive = 1       // menu-bar indication only
    case gentle = 2        // a notification with one concrete suggestion
    case actionable = 3    // a notification with one-click actions
    case pattern = 4       // repeated pattern: suggest fixing the setup instead

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Where a recommendation comes from, shown next to it in the UI.
public enum EvidenceLevel: String, Codable, Sendable {
    case evidenceInformed = "Evidence-informed"
    case heuristic = "Practical heuristic"
    case preference = "Your preference"
    case experimental = "Experimental camera estimate"
}
