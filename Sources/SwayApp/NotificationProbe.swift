import Foundation
import UserNotifications

/// `Sway --notification-probe`: prints what macOS allows for Sway's
/// notifications, posts one test notification and reports whether macOS
/// accepted and kept it. Run the binary inside the installed app so macOS
/// sees Sway's bundle: /Applications/Sway.app/Contents/MacOS/Sway --notification-probe
enum NotificationProbe {
    static func run() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            func setting(_ v: UNNotificationSetting) -> String {
                switch v {
                case .enabled: return "on"
                case .disabled: return "off"
                case .notSupported: return "not supported"
                @unknown default: return "unknown"
                }
            }
            let auth: String
            switch s.authorizationStatus {
            case .authorized: auth = "allowed"
            case .denied: auth = "denied"
            case .notDetermined: auth = "never asked"
            case .provisional: auth = "provisional"
            @unknown default: auth = "unknown"
            }
            let style: String
            switch s.alertStyle {
            case .banner: style = "banners"
            case .alert: style = "alerts"
            case .none: style = "none"
            @unknown default: style = "unknown"
            }
            print("permission: \(auth)")
            print("style: \(style)")
            print("alerts: \(setting(s.alertSetting))  notification centre: \(setting(s.notificationCenterSetting))  sound: \(setting(s.soundSetting))")
            print("time sensitive: \(setting(s.timeSensitiveSetting))")
            let content = UNMutableNotificationContent()
            content.title = "Sway test notification"
            content.body = "If you can read this, Sway's reminders can reach you."
            content.interruptionLevel = .active
            let id = "sway.probe"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                if let error {
                    print("posted: no, macOS refused it: \(error.localizedDescription)")
                    exit(1)
                }
                print("posted: yes")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    center.getDeliveredNotifications { list in
                        let kept = list.contains { $0.request.identifier == id }
                        print("in Notification Centre after 2 s: \(kept ? "yes" : "no")")
                        print("other Sway notifications there: \(list.filter { $0.request.identifier != id }.map(\.request.identifier))")
                        // Banners need permission and a style other than None;
                        // Notification Centre is information only.
                        exit(s.alertStyle == .none ? 1 : 0)
                    }
                }
            }
        }
    }
}
