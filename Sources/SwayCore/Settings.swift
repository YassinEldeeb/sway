import Foundation

/// Thresholds for one posture issue. Enter/exit form a hysteresis band so a
/// value hovering near the threshold cannot flip the state back and forth.
public struct IssueThresholds: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var enter: Double
    public var exit: Double
    /// How long the deviation must hold before it counts as sustained.
    public var minDuration: TimeInterval

    public init(enabled: Bool = true, enter: Double, exit: Double, minDuration: TimeInterval) {
        self.enabled = enabled
        self.enter = enter
        self.exit = exit
        self.minDuration = minDuration
    }
}

public struct CoachSettings: Codable, Equatable, Sendable {
    // MARK: Breaks (configurable heuristics, not medical thresholds)
    public var microBreakInterval: TimeInterval = 25 * 60
    public var longBreakInterval: TimeInterval = 55 * 60
    public var longSessionThreshold: TimeInterval = 120 * 60
    public var eyeRestEnabled = false
    public var eyeRestInterval: TimeInterval = 20 * 60
    /// No input for this long means the user stepped away.
    public var awayThreshold: TimeInterval = 120
    /// An away period this long counts as a movement break.
    public var microBreakMinAway: TimeInterval = 120
    /// An away period this long counts as a longer break.
    public var longBreakMinAway: TimeInterval = 5 * 60
    public var snoozeDuration: TimeInterval = 10 * 60
    public var maxSnoozesPerReminder = 2

    // MARK: Notifications
    public var notificationsEnabled = true
    public var maxNotificationsPerHour = 3
    public var maxNotificationsPerDay = 14
    public var minSpacingBetweenNotifications: TimeInterval = 8 * 60
    public var holdDuringCalls = true
    public var holdDuringFullScreen = true
    public var quietHoursEnabled = false
    public var quietHoursStartMinute = 22 * 60   // minutes after local midnight
    public var quietHoursEndMinute = 7 * 60

    // MARK: Posture (experimental camera estimates)
    public var cameraMonitoringEnabled = false
    public var preferredCameraID: String?
    public var sampleInterval: TimeInterval = 2
    public var minFaceConfidence: Double = 0.6
    public var headDown = IssueThresholds(enter: 0.55, exit: 0.35, minDuration: 5 * 60)
    public var forwardLean = IssueThresholds(enter: 0.16, exit: 0.09, minDuration: 5 * 60)
    public var lateralTilt = IssueThresholds(enter: 12, exit: 7, minDuration: 5 * 60)
    public var shoulderAsymmetry = IssueThresholds(enter: 7, exit: 4, minDuration: 10 * 60)
    /// Head movement (in face-heights, std dev over a 5-minute window) below
    /// this counts as "still".
    public var staticMotionThreshold: Double = 0.06
    public var staticMinDuration: TimeInterval = 45 * 60
    public var staticEnabled = true
    /// A sustained issue stays passive (menu bar only) this long before it
    /// may become a notification.
    public var postureNotifyAfter: TimeInterval = 3 * 60
    /// Noticing an issue that keeps coming back in short bouts. It leads to
    /// a workstation suggestion, never to posture reminders.
    public var frequentPatterns = FrequentPatternSettings()
    /// Show the daily comfort check-in on the dashboard.
    public var comfortCheckInEnabled = true

    // MARK: App
    public var showDockIcon = false
    public var showTimerInMenuBar = true
    public var retentionDays = 90
    public var onboardingComplete = false

    public init() {}

    public func thresholds(for issue: PostureIssue) -> IssueThresholds {
        switch issue {
        case .headDown: return headDown
        case .forwardLean: return forwardLean
        case .lateralTilt: return lateralTilt
        case .shoulderAsymmetry: return shoulderAsymmetry
        case .staticPosture:
            return IssueThresholds(enabled: staticEnabled, enter: 0, exit: 0, minDuration: staticMinDuration)
        }
    }

    /// Clamp values a hand-edited or old settings file could get wrong.
    public func sanitized() -> CoachSettings {
        var s = self
        s.microBreakInterval = s.microBreakInterval.clamped(5 * 60, 120 * 60)
        s.longBreakInterval = s.longBreakInterval.clamped(15 * 60, 240 * 60)
        s.longSessionThreshold = max(s.longSessionThreshold.clamped(30 * 60, 600 * 60), s.longBreakInterval)
        s.eyeRestInterval = s.eyeRestInterval.clamped(5 * 60, 120 * 60)
        s.awayThreshold = s.awayThreshold.clamped(30, 15 * 60)
        s.microBreakMinAway = max(s.microBreakMinAway.clamped(30, 30 * 60), s.awayThreshold)
        s.longBreakMinAway = max(s.longBreakMinAway.clamped(60, 60 * 60), s.microBreakMinAway)
        s.snoozeDuration = s.snoozeDuration.clamped(60, 60 * 60)
        s.maxSnoozesPerReminder = min(max(s.maxSnoozesPerReminder, 0), 5)
        s.maxNotificationsPerHour = min(max(s.maxNotificationsPerHour, 1), 12)
        s.maxNotificationsPerDay = min(max(s.maxNotificationsPerDay, 1), 60)
        s.minSpacingBetweenNotifications = s.minSpacingBetweenNotifications.clamped(60, 60 * 60)
        s.sampleInterval = s.sampleInterval.clamped(0.5, 30)
        s.minFaceConfidence = s.minFaceConfidence.clamped(0.3, 0.95)
        s.retentionDays = min(max(s.retentionDays, 7), 3650)
        for issue in [PostureIssue.headDown, .forwardLean, .lateralTilt, .shoulderAsymmetry] {
            var t = s.thresholds(for: issue)
            t.enter = max(t.enter, 0.0001)
            t.exit = min(max(t.exit, 0), t.enter)
            t.minDuration = t.minDuration.clamped(30, 60 * 60)
            switch issue {
            case .headDown: s.headDown = t
            case .forwardLean: s.forwardLean = t
            case .lateralTilt: s.lateralTilt = t
            case .shoulderAsymmetry: s.shoulderAsymmetry = t
            case .staticPosture: break
            }
        }
        s.staticMinDuration = s.staticMinDuration.clamped(10 * 60, 180 * 60)
        s.postureNotifyAfter = s.postureNotifyAfter.clamped(0, 30 * 60)
        s.frequentPatterns = s.frequentPatterns.sanitized()
        return s
    }

    public func isQuietHours(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if quietHoursStartMinute == quietHoursEndMinute { return false }
        if quietHoursStartMinute < quietHoursEndMinute {
            return minute >= quietHoursStartMinute && minute < quietHoursEndMinute
        }
        return minute >= quietHoursStartMinute || minute < quietHoursEndMinute
    }
}

extension CoachSettings {
    // Decode tolerantly: a settings file from an older version that lacks a
    // key keeps that key's default instead of resetting everything.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: AnyKey.self)
        func read<T: Decodable>(_ key: String, _ into: inout T) {
            if let v = try? c.decode(T.self, forKey: AnyKey(key)) { into = v }
        }
        read("microBreakInterval", &microBreakInterval)
        read("longBreakInterval", &longBreakInterval)
        read("longSessionThreshold", &longSessionThreshold)
        read("eyeRestEnabled", &eyeRestEnabled)
        read("eyeRestInterval", &eyeRestInterval)
        read("awayThreshold", &awayThreshold)
        read("microBreakMinAway", &microBreakMinAway)
        read("longBreakMinAway", &longBreakMinAway)
        read("snoozeDuration", &snoozeDuration)
        read("maxSnoozesPerReminder", &maxSnoozesPerReminder)
        read("notificationsEnabled", &notificationsEnabled)
        read("maxNotificationsPerHour", &maxNotificationsPerHour)
        read("maxNotificationsPerDay", &maxNotificationsPerDay)
        read("minSpacingBetweenNotifications", &minSpacingBetweenNotifications)
        read("holdDuringCalls", &holdDuringCalls)
        read("holdDuringFullScreen", &holdDuringFullScreen)
        read("quietHoursEnabled", &quietHoursEnabled)
        read("quietHoursStartMinute", &quietHoursStartMinute)
        read("quietHoursEndMinute", &quietHoursEndMinute)
        read("cameraMonitoringEnabled", &cameraMonitoringEnabled)
        read("preferredCameraID", &preferredCameraID)
        read("sampleInterval", &sampleInterval)
        read("minFaceConfidence", &minFaceConfidence)
        read("headDown", &headDown)
        read("forwardLean", &forwardLean)
        read("lateralTilt", &lateralTilt)
        read("shoulderAsymmetry", &shoulderAsymmetry)
        read("staticMotionThreshold", &staticMotionThreshold)
        read("staticMinDuration", &staticMinDuration)
        read("staticEnabled", &staticEnabled)
        read("postureNotifyAfter", &postureNotifyAfter)
        read("frequentPatterns", &frequentPatterns)
        read("comfortCheckInEnabled", &comfortCheckInEnabled)
        read("showDockIcon", &showDockIcon)
        read("showTimerInMenuBar", &showTimerInMenuBar)
        read("retentionDays", &retentionDays)
        read("onboardingComplete", &onboardingComplete)
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
