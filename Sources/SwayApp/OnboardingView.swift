import SwayCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var notifications = AppModel.shared.notifications
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                switch page {
                case 0: welcome
                case 1: notificationsPage
                default: posturePage
                }
            }
            .transition(.opacity)
            Spacer()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in Circle().fill(i == page ? Theme.accent : Color.secondary.opacity(0.3)).frame(width: 6, height: 6) }
                }
                Spacer()
                if page > 0 { Button("Back") { withAnimation { page -= 1 } } }
                Button(page == 2 ? "Done" : "Continue") {
                    if page == 2 {
                        model.settings.onboardingComplete = true
                        NSApp.keyWindow?.close()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .padding(.top, 8)
        .frame(minWidth: 520, minHeight: 520)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "figure.stand").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text("Sway").font(.system(size: 30, weight: .semibold))
            Text("A quiet coach for long days at the computer.").font(.system(size: 16)).foregroundStyle(.secondary)
            point("figure.walk", "Movement over perfect posture", "No single posture is right for hours. Sway nudges you to change position and move — at sensible intervals, never constantly.")
            point("bell.badge", "Few, useful reminders", "Budgets, cooldowns and snooze limits keep it quiet. It holds reminders during calls and full-screen work, and backs off if you keep dismissing something.")
            point("lock.shield", "Private by design", "Everything stays on this Mac. It tracks only how long you've been active — never what you type or which apps you use.")
            Text("Sway is not a medical device. For persistent, severe or worsening pain, see a qualified clinician.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private var notificationsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "bell").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text("Allow notifications").font(.system(size: 22, weight: .semibold))
            Text("Sway sends at most \(model.settings.maxNotificationsPerHour) an hour, each with one concrete suggestion and one-click actions: start a 1-minute routine, take a break, snooze, or mark it not helpful.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if notifications.isAvailable {
                switch notifications.authorization {
                case .authorized, .provisional:
                    Label("Notifications allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                case .denied:
                    Label("Notifications are off for Sway. You can turn them on in System Settings → Notifications; reminders still show in the menu bar.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                default:
                    Button("Allow notifications") { notifications.requestAuthorization() }.buttonStyle(PillButtonStyle(prominent: true))
                }
            } else {
                Label("Running outside the app bundle: reminders will appear in the menu bar only.", systemImage: "info.circle").foregroundStyle(.secondary)
            }
        }
    }

    private var posturePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "camera.metering.center.weighted.average").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text("Optional: posture monitoring").font(.system(size: 22, weight: .semibold))
            Text("With your permission, Sway can use the camera to notice sustained patterns — head tilted down for a long time, leaning in, or barely moving — compared with a position you calibrate.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            point("cpu", "On-device only", "Frames are analysed in memory by Apple Vision and discarded. Nothing is recorded or uploaded.")
            point("video", "Always visible", "A camera mark appears in the menu bar whenever the camera is on. It turns off while you're away or paused.")
            point("questionmark.circle", "Experimental", "Camera estimates are approximate and relative to your calibration. Breaks and activity work fully without the camera.")
            HStack {
                Button("Calibrate now…") { WindowManager.shared.show(.calibration) }.buttonStyle(PillButtonStyle(prominent: true))
                Button("Workstation setup…") { WindowManager.shared.show(.setup) }.buttonStyle(PillButtonStyle())
            }
            Text("You can do either later from the menu bar.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
