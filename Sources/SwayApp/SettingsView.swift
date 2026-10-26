import AVFoundation
import SwayCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            BreakSettings().tabItem { Label("Breaks", systemImage: "figure.walk") }
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell") }
            PostureSettings().tabItem { Label("Posture", systemImage: "camera") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            DiagnosticsView().tabItem { Label("Diagnostics", systemImage: "gauge.with.dots.needle.33percent") }
        }
        .padding(.top, 28)
        .frame(minWidth: 600, minHeight: 520)
    }
}

/// Minutes binding over a seconds setting.
private func minutes(_ b: Binding<TimeInterval>) -> Binding<Double> {
    Binding(get: { b.wrappedValue / 60 }, set: { b.wrappedValue = ($0 * 60).rounded() })
}

private struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        model.launchAtLoginMessage = LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                        if LaunchAtLogin.needsApproval {
                            model.launchAtLoginMessage = "Approve Sway in System Settings → General → Login Items."
                        }
                    }
                if let m = model.launchAtLoginMessage {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Show the work timer in the menu bar", isOn: $model.settings.showTimerInMenuBar)
                Toggle("Show a Dock icon", isOn: $model.settings.showDockIcon)
                Toggle("Show the daily comfort check-in on the dashboard", isOn: $model.settings.comfortCheckInEnabled)
            }
            Section("Setup") {
                Button("Workstation setup assistant…") { WindowManager.shared.show(.setup) }
                Button("Show welcome again…") { WindowManager.shared.show(.onboarding) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BreakSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                stepper("Movement break every", minutes($model.settings.microBreakInterval), 10...90, 5)
                stepper("Longer break every", minutes($model.settings.longBreakInterval), 30...180, 5)
                stepper("Flag a long session after", minutes($model.settings.longSessionThreshold), 60...360, 15)
            } header: {
                Text("Breaks")
            } footer: {
                Text("Defaults (25 / 55 / 120 min) are practical heuristics drawn from occupational guidance to break up long sitting and screen time — not medical thresholds.")
            }
            Section {
                Toggle("Eye-rest reminders (20-20-20)", isOn: $model.settings.eyeRestEnabled)
                if model.settings.eyeRestEnabled {
                    stepper("Every", minutes($model.settings.eyeRestInterval), 10...60, 5)
                }
            } footer: {
                Text("Every ~20 minutes, look ~6 m (20 ft) away for 20 seconds. Movement breaks also rest your eyes.")
            }
            Section {
                stepper("Count me as away after", minutes($model.settings.awayThreshold), 1...10, 1)
                stepper("A movement break is at least", minutes($model.settings.microBreakMinAway), 1...10, 1)
                stepper("A longer break is at least", minutes($model.settings.longBreakMinAway), 2...30, 1)
                stepper("Snooze length", minutes($model.settings.snoozeDuration), 5...30, 5)
            } header: {
                Text("What counts as a break")
            } footer: {
                Text("Timers reset only after real time away (no keyboard or mouse input), or a routine or guided break you complete. A few seconds of inactivity never count.")
            }
        }
        .formStyle(.grouped)
    }

    private func stepper(_ label: String, _ v: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double) -> some View {
        Stepper(value: v, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(v.wrappedValue)) min").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var notifications = AppModel.shared.notifications

    var body: some View {
        Form {
            Section {
                Toggle("Send notifications", isOn: $model.settings.notificationsEnabled)
                HStack {
                    Text("macOS permission")
                    Spacer()
                    Text(permissionText).foregroundStyle(.secondary)
                    if notifications.authorization == .notDetermined && notifications.isAvailable {
                        Button("Allow…") { notifications.requestAuthorization() }
                    } else if notifications.authorization == .denied {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                    }
                }
                if !notifications.isAvailable {
                    Text("Running unbundled: reminders appear in the menu bar only. Build Sway.app for system notifications.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("macOS Focus and Do Not Disturb hold Sway's notifications automatically; they stay in Notification Center.")
            }
            Section("Budget") {
                Stepper("At most \(model.settings.maxNotificationsPerHour) per hour", value: $model.settings.maxNotificationsPerHour, in: 1...6)
                Stepper("At most \(model.settings.maxNotificationsPerDay) per day", value: $model.settings.maxNotificationsPerDay, in: 3...30)
                Stepper("At least \(Int(model.settings.minSpacingBetweenNotifications / 60)) min apart", value: minutes($model.settings.minSpacingBetweenNotifications), in: 3...30, step: 1)
                Stepper("Snooze at most \(model.settings.maxSnoozesPerReminder)× per reminder", value: $model.settings.maxSnoozesPerReminder, in: 0...4)
            }
            Section {
                Toggle("Hold while the microphone or a camera is in use by another app", isOn: $model.settings.holdDuringCalls)
                Toggle("Hold while a full-screen app is in front", isOn: $model.settings.holdDuringFullScreen)
                Toggle("Quiet hours", isOn: $model.settings.quietHoursEnabled)
                if model.settings.quietHoursEnabled {
                    timePicker("From", $model.settings.quietHoursStartMinute)
                    timePicker("To", $model.settings.quietHoursEndMinute)
                }
            } header: {
                Text("Don't interrupt")
            } footer: {
                Text("macOS doesn't tell apps whether you're in a meeting or sharing your screen. Sway uses what it can see: another app using the mic or camera usually means a call; a full-screen app often means presenting. Held reminders wait in the menu bar.")
            }
        }
        .formStyle(.grouped)
    }

    private var permissionText: String {
        switch notifications.authorization {
        case .authorized, .provisional: return "Allowed"
        case .denied: return "Not allowed"
        default: return "Not requested"
        }
    }

    private func timePicker(_ label: String, _ minute: Binding<Int>) -> some View {
        let date = Binding<Date>(
            get: { Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: Date())! },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
        return DatePicker(label, selection: date, displayedComponents: .hourAndMinute)
    }
}

private struct PostureSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Posture monitoring with the camera", isOn: Binding(get: { model.settings.cameraMonitoringEnabled }, set: { model.setCameraMonitoring($0) }))
                    .disabled(model.calibration == nil)
                HStack {
                    Text("Calibration")
                    Spacer()
                    if let c = model.calibration {
                        Text("\(c.cameraName) · \(c.createdAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                    } else {
                        Text("Not calibrated").foregroundStyle(.secondary)
                    }
                    Button(model.calibration == nil ? "Calibrate…" : "Recalibrate…") { WindowManager.shared.show(.calibration) }
                }
                HStack {
                    Text("Camera access")
                    Spacer()
                    Text(authText).foregroundStyle(.secondary)
                    if model.cameraAuthorization == .denied {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                        }
                    }
                }
            } footer: {
                Text("Optional and experimental. Frames are analysed on this Mac and immediately discarded; only a few derived numbers are kept. Recalibrate whenever your desk, chair, monitor or camera changes.")
            }
            Section {
                ForEach([PostureIssue.headDown, .forwardLean, .lateralTilt, .shoulderAsymmetry], id: \.self) { issue in
                    issueRow(issue)
                }
                Toggle(isOn: $model.settings.staticEnabled) {
                    VStack(alignment: .leading) {
                        Text(PostureIssue.staticPosture.title)
                        Text("After \(Int(model.settings.staticMinDuration / 60)) min with very little head movement").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper("Notify after an issue lasts \(Int(model.settings.postureNotifyAfter / 60)) more min", value: minutes($model.settings.postureNotifyAfter), in: 0...20, step: 1)
            } header: {
                Text("What to watch for")
            } footer: {
                Text("A deviation must last several minutes before it counts, and it shows quietly in the menu bar before any notification. Lower sensitivity needs a larger change from your calibrated position.")
            }
            Section("Sampling") {
                Picker("Analyse a frame every", selection: $model.settings.sampleInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("4 seconds").tag(4.0)
                    Text("8 seconds (lowest power)").tag(8.0)
                }
                Text("Halved automatically on battery. The camera turns off while you're away, paused, or the Mac is locked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var authText: String {
        switch model.cameraAuthorization {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not requested"
        }
    }

    private func binding(_ issue: PostureIssue) -> Binding<IssueThresholds> {
        switch issue {
        case .headDown: return $model.settings.headDown
        case .forwardLean: return $model.settings.forwardLean
        case .lateralTilt: return $model.settings.lateralTilt
        case .shoulderAsymmetry: return $model.settings.shoulderAsymmetry
        case .staticPosture: return .constant(model.settings.thresholds(for: .staticPosture))
        }
    }

    private func issueRow(_ issue: PostureIssue) -> some View {
        let b = binding(issue)
        let defaults = CoachSettings().thresholds(for: issue)
        let sensitivity = Binding<Double>(
            get: { defaults.enter / b.wrappedValue.enter },
            set: { s in
                var t = b.wrappedValue
                t.enter = defaults.enter / s
                t.exit = defaults.exit / s
                b.wrappedValue = t
            })
        let measurable = model.calibration?.report.measurable[issue] ?? true
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { b.wrappedValue.enabled }, set: { var t = b.wrappedValue; t.enabled = $0; b.wrappedValue = t })) {
                VStack(alignment: .leading) {
                    Text(issue.title)
                    Text(measurable ? issue.definition : "Not measurable with your current camera view.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if b.wrappedValue.enabled && measurable {
                HStack {
                    Text("Less sensitive").font(.caption).foregroundStyle(.secondary)
                    Slider(value: sensitivity, in: 0.6...1.4)
                    Text("More").font(.caption).foregroundStyle(.secondary)
                }
                Stepper("Must last \(Int(b.wrappedValue.minDuration / 60)) min", value: Binding(get: { b.wrappedValue.minDuration / 60 }, set: { var t = b.wrappedValue; t.minDuration = $0 * 60; b.wrappedValue = t }), in: 1...30, step: 1)
                    .font(.caption)
            }
        }
    }
}

private struct PrivacySettings: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("What Sway keeps") {
                bullet("Time-based activity: when you were active or away, breaks, and session lengths. Never keystrokes, clipboard, window titles, app names or browsing.")
                bullet("Posture: a few numbers per day (seconds in each sustained deviation, episode counts) and your calibration baseline. Camera frames are never saved, recorded or uploaded.")
                bullet("Your comfort check-ins and how you responded to reminders.")
                bullet("Everything stays on this Mac. No account, no network requests, no analytics.")
            }
            Section {
                Stepper("Keep daily history for \(model.settings.retentionDays) days", value: $model.settings.retentionDays, in: 7...365, step: 7)
                HStack {
                    Text("Stored")
                    Spacer()
                    Text("\(model.store.storedDayCount()) days · \(ByteCountFormatter.string(fromByteCount: Int64(model.store.totalBytes()), countStyle: .file))").foregroundStyle(.secondary)
                    Button("Show in Finder") { NSWorkspace.shared.open(model.store.directory) }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text(model.store.directory.path).textSelection(.enabled)
            }
            Section {
                Button("Reset personalization") { model.resetPersonalization() }
                Button("Delete all Sway data…", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all Sway data?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) { model.deleteAllData() }
        } message: {
            Text("This removes your history, calibration, check-ins and settings from this Mac. It can't be undone.")
        }
    }

    private func bullet(_ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.shield").foregroundStyle(Theme.accent) }
    }
}

private struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("This app, measured live") {
                row("CPU (last 30 s)", model.resourceSample.map { String(format: "%.2f%% of one core", $0.cpuPercent) } ?? "measuring…")
                row("Memory footprint", model.resourceSample.map { String(format: "%.0f MB", $0.footprintMB) } ?? "measuring…")
                row("Camera", model.cameraState.label)
                row("Camera permission", permissionLabel)
                row("Frames analysed", "\(model.visionStats.framesProcessed)")
                row("Vision time per frame", model.visionStats.framesProcessed > 0 ? String(format: "%.1f ms avg · %.1f ms last", model.visionStats.averageMs, model.visionStats.lastMs) : "—")
                row("Tracking", "\(model.posture.status.label) · reliability \(Int(model.posture.reliability * 100))%")
            }
            Section("Live posture estimate (vs. calibration)") {
                let m = model.posture.metrics
                row("Head down score", m.headDown.map { reading(.headDown, String(format: "%.2f", $0), over: $0 >= model.settings.headDown.enter, line: String(format: "%.2f", model.settings.headDown.enter)) } ?? "—")
                row("Lean toward screen", m.forwardLean.map { reading(.forwardLean, String(format: "%+.0f%% face size", $0 * 100), over: $0 >= model.settings.forwardLean.enter, line: String(format: "%.0f%%", model.settings.forwardLean.enter * 100)) } ?? "—")
                row("Head tilt", m.lateralTilt.map { reading(.lateralTilt, String(format: "%.0f°", $0), over: $0 >= model.settings.lateralTilt.enter, line: String(format: "%.0f°", model.settings.lateralTilt.enter)) } ?? "—")
                row("Shoulder line", m.shoulderAsymmetry.map { reading(.shoulderAsymmetry, String(format: "%.0f°", $0), over: $0 >= model.settings.shoulderAsymmetry.enter, line: String(format: "%.0f°", model.settings.shoulderAsymmetry.enter)) } ?? "—")
                row("Movement (5 min)", m.motion.map { movement($0) } ?? "—")
                Text("Over the line isn't a problem yet: it has to stay there for the set time (Posture tab) before it counts, and you're told only after that.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Reminders right now") {
                if let hold = model.decision.hold { row("Held", hold.label) }
                if model.decision.statuses.isEmpty {
                    Text("Nothing is due.").foregroundStyle(.secondary)
                }
                ForEach(model.decision.statuses, id: \.reminder.instanceID) { st in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.reminder.title)
                        Text(st.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
                row("Sent in the last hour", "\(model.notificationsLastHour) of \(model.settings.maxNotificationsPerHour)")
                row("Sent today", "\(model.notificationsToday) of \(model.settings.maxNotificationsPerDay)")
            }
            Section("Calibration and patterns") {
                row("Calibration", model.calibration.map { "\($0.cameraName), \($0.createdAt.formatted(date: .abbreviated, time: .shortened))" } ?? "None")
                row("Calibration health", model.posture.health.isSuspect ? "May be out of date (warnings paused)" : "Looks consistent")
                let flags = model.today.frequentPatterns
                row("Recurring in short bouts today", flags.isEmpty ? "None" : flags.keys.map { $0.title }.sorted().joined(separator: ", "))
            }
            Section("Decision log (newest first)") {
                let entries = model.runtime.decisionLog.entries.suffix(40).reversed()
                if entries.isEmpty { Text("No decisions yet.").foregroundStyle(.secondary) }
                ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.at.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Text(e.text).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section("Signals") {
                row("Idle for", String(format: "%.0f s", SystemSignals.idleSeconds()))
                row("Mic/camera in use elsewhere", model.context.micOrCameraInUseByOthers ? "Yes" : "No")
                row("Full-screen app in front", model.context.fullScreenAppInFront ? "Yes" : "No")
                row("On battery", SystemSignals.onBattery() ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
    }

    private var permissionLabel: String {
        switch model.cameraAuthorization {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Denied (System Settings → Privacy & Security → Camera)"
        case .restricted: return "Restricted by this Mac"
        @unknown default: return "Unknown"
        }
    }

    /// Says where a reading stands: under the line, over it and being
    /// timed, or counted as a sustained episode.
    private func reading(_ issue: PostureIssue, _ value: String, over: Bool, line: String) -> String {
        if let a = model.activeIssues.first(where: { $0.issue == issue }) {
            return "\(value) · counted since \(a.since.formatted(date: .omitted, time: .shortened))"
        }
        if let b = model.buildingIssues.first(where: { $0.issue == issue }) {
            return "\(value) · over \(line), counts in \(clock(b.remaining(at: Date())))"
        }
        return over ? "\(value) · over \(line)" : "\(value) · under \(line)"
    }

    /// Little movement counts when the value is *below* the line, unlike the
    /// other readings.
    private func movement(_ v: Double) -> String {
        let line = String(format: "%.3f", model.settings.staticMotionThreshold)
        let value = String(format: "%.3f", v)
        if let a = model.activeIssues.first(where: { $0.issue == .staticPosture }) {
            return "\(value) · still since \(a.since.formatted(date: .omitted, time: .shortened))"
        }
        if let b = model.buildingIssues.first(where: { $0.issue == .staticPosture }) {
            return "\(value) · still (under \(line)), counts in \(clock(b.remaining(at: Date())))"
        }
        return v < model.settings.staticMotionThreshold ? "\(value) · still (under \(line))" : "\(value) · moving (still is under \(line))"
    }

    private func clock(_ s: TimeInterval) -> String {
        let n = Int(s.rounded(.up))
        return String(format: "%d:%02d", n / 60, n % 60)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
