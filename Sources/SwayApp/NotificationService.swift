import AppKit
import ServiceManagement
import SwayCore
import UserNotifications

/// Notification button identifiers. The strings are unchanged from earlier
/// versions so buttons on notifications already on screen keep working.
enum NotificationAction: String {
    case startRoutine = "sway.routine"
    case takeBreak = "sway.break"
    case snooze = "sway.snooze"
    case unhelpful = "sway.unhelpful"
    case recalibrate = "sway.recalibrate"
    case eyeDone = "sway.eyeDone"
    case openSetup = "sway.setup"

    var coachAction: CoachAction {
        switch self {
        case .startRoutine: return .startRoutine
        case .takeBreak: return .takeBreak
        case .snooze: return .snooze
        case .unhelpful: return .notHelpful
        case .recalibrate: return .recalibrate
        case .eyeDone: return .eyeDone
        case .openSetup: return .openSetup
        }
    }
}

/// Native notifications with one-click actions. Only works from the bundled
/// app (`Sway.app`); when run unbundled, prompts appear in the menu bar only.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    var onTap: ((NotificationTap, _ instanceID: String, _ kind: ReminderKind) -> Void)?
    private var isSetUp = false

    let isAvailable: Bool = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil

    private var center: UNUserNotificationCenter? { isAvailable ? UNUserNotificationCenter.current() : nil }

    /// Must run before launch finishes, so a click that launched Sway (it
    /// was quit) is delivered to this delegate.
    func setUp() {
        guard let center, !isSetUp else { return }
        isSetUp = true
        center.delegate = self
        let routine = UNNotificationAction(identifier: NotificationAction.startRoutine.rawValue, title: "Start 1-min routine")
        let takeBreak = UNNotificationAction(identifier: NotificationAction.takeBreak.rawValue, title: "Take a 3-min break")
        let snooze = UNNotificationAction(identifier: NotificationAction.snooze.rawValue, title: "Snooze 10 min")
        let unhelpful = UNNotificationAction(identifier: NotificationAction.unhelpful.rawValue, title: "Not helpful")
        let recalibrate = UNNotificationAction(identifier: NotificationAction.recalibrate.rawValue, title: "Recalibrate")
        let eyeDone = UNNotificationAction(identifier: NotificationAction.eyeDone.rawValue, title: "Done")
        let setup = UNNotificationAction(identifier: NotificationAction.openSetup.rawValue, title: "Check my setup")
        let opts: UNNotificationCategoryOptions = [.customDismissAction]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "break", actions: [routine, takeBreak, snooze, unhelpful], intentIdentifiers: [], options: opts),
            UNNotificationCategory(identifier: "break.final", actions: [routine, takeBreak, unhelpful], intentIdentifiers: [], options: opts),
            UNNotificationCategory(identifier: "posture", actions: [routine, snooze, recalibrate, unhelpful], intentIdentifiers: [], options: opts),
            UNNotificationCategory(identifier: "posture.final", actions: [routine, recalibrate, unhelpful], intentIdentifiers: [], options: opts),
            UNNotificationCategory(identifier: "eye", actions: [eyeDone, snooze, unhelpful], intentIdentifiers: [], options: opts),
            UNNotificationCategory(identifier: "eye.final", actions: [eyeDone, unhelpful], intentIdentifiers: [], options: opts),
            UNNotificationCategory(identifier: "review", actions: [setup, unhelpful], intentIdentifiers: [], options: opts),
        ])
        refresh()
    }

    func refresh() {
        guard let center else { return }
        center.getNotificationSettings { s in
            let status = s.authorizationStatus
            Task { @MainActor in self.authorization = status }
        }
    }

    /// Whether a posted notification would actually appear.
    var canShow: Bool {
        isAvailable && (authorization == .authorized || authorization == .provisional)
    }

    private var askedThisLaunch = false

    /// Coaching is on but macOS has no answer for Sway yet (never asked,
    /// or reset by a reinstall): ask once per launch.
    func askIfUndetermined() {
        guard let center, !askedThisLaunch else { return }
        center.getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            Task { @MainActor in
                guard !self.askedThisLaunch else { return }
                self.askedThisLaunch = true
                self.requestAuthorization()
            }
        }
    }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        guard let center else { done?(false); return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Task { @MainActor in
                self.refresh()
                done?(ok)
            }
        }
    }

    func post(_ r: DueReminder, canSnooze: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.body = r.body
        content.userInfo = ["instance": r.instanceID, "kind": r.kind.rawValue]
        content.threadIdentifier = r.kind.rawValue
        let group: String
        switch r.kind {
        case .microBreak, .longBreak, .longSession: group = "break"
        case .eyeRest: group = "eye"
        case .workstationReview: group = "review"
        default: group = "posture"
        }
        content.categoryIdentifier = (canSnooze || group == "review") ? group : group + ".final"
        if r.kind == .longSession { content.interruptionLevel = .active } else { content.interruptionLevel = .passive }
        // Replace any earlier notification of the same kind instead of stacking.
        center.removeDeliveredNotifications(withIdentifiers: [r.kind.rawValue])
        center.add(UNNotificationRequest(identifier: r.kind.rawValue, content: content, trigger: nil))
    }

    func clear(_ kind: ReminderKind) {
        center?.removeDeliveredNotifications(withIdentifiers: [kind.rawValue])
    }

    func clearAll() {
        center?.removeAllDeliveredNotifications()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let instance = info["instance"] as? String ?? ""
        let kind = (info["kind"] as? String).flatMap(ReminderKind.init(rawValue:)) ?? .microBreak
        let id = response.actionIdentifier
        let tap: NotificationTap?
        switch id {
        case UNNotificationDismissActionIdentifier: tap = .dismissed
        case UNNotificationDefaultActionIdentifier: tap = .body
        default: tap = NotificationAction(rawValue: id).map { .button($0.coachAction) }
        }
        Task { @MainActor in
            if let tap { self.onTap?(tap, instance, kind) }
            completionHandler()
        }
    }
}

/// Launch at login through the system's login items (macOS 13+).
enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static var needsApproval: Bool { status == .requiresApproval }

    /// Returns an error message, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return "Launch at login needs the bundled Sway.app (run scripts/build-app.sh)."
        }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
