import SwayCore
import SwiftUI

/// The popover from the menu bar. Answers, top to bottom: is monitoring on,
/// does anything need attention, how long have I been working, when should
/// I move, and what can I do right now.
struct MenuView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            workCard
            if let g = model.guidedBreak {
                breakCard(g)
            } else if let a = model.attention {
                attentionCard(a)
            }
            if let hold = model.decision.hold {
                Label(hold.label, systemImage: "bell.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            postureRow
            actions
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Sway").font(.system(size: 15, weight: .semibold))
            Spacer()
            if model.isPaused {
                Label("Paused", systemImage: "pause.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    StatusDot(color: model.tracker.isActive ? .green : .secondary)
                    Text(model.tracker.isActive ? "Coaching" : "Away")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if model.cameraState.isRunning {
                Label("Camera on", systemImage: "video.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .help("Camera is on. Frames are analysed in memory and never stored.")
            }
        }
    }

    // MARK: Work

    private var workCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tracker.isActive ? "Working for" : "Away since")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.tracker.isActive ? Format.duration(model.continuousWork) : awaySince)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Today").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Format.duration(model.today.activeSeconds)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    Text("\(model.today.meaningfulBreaks) breaks").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let next = model.nextBreak, model.tracker.isActive, model.attention == nil, model.guidedBreak == nil {
                let left = next.at.timeIntervalSince(model.now)
                ProgressView(value: progress(to: next))
                    .tint(Theme.accent)
                    .padding(.top, 6)
                Text(left > 0 ? "\(next.kind == .longBreak ? "Longer break" : "Movement break") in \(Format.duration(left + 59))" : "Break due")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var awaySince: String {
        let f = DateFormatter()
        f.timeStyle = .short
        switch model.tracker.mode {
        case .away(let since), .asleep(let since): return f.string(from: since)
        case .active: return "—"
        }
    }

    private func progress(to next: UpcomingBreak) -> Double {
        let ref = next.kind == .longBreak ? model.tracker.lastLongBreak(fallback: model.now) : model.tracker.lastMovement(fallback: model.now)
        let total = next.at.timeIntervalSince(ref)
        guard total > 0 else { return 1 }
        return min(1, max(0, model.now.timeIntervalSince(ref) / total))
    }

    // MARK: Attention

    private func attentionCard(_ r: DueReminder) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: r.kind.isBreak ? "figure.walk" : (r.kind == .workstationReview ? "wrench.adjustable" : (r.kind == .eyeRest ? "eye" : "person.fill")))
                        .foregroundStyle(Theme.warm)
                    Text(r.title).font(.system(size: 13, weight: .semibold))
                }
                Text(r.body).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if r.kind.postureIssue != nil {
                    Text("Experimental camera estimate").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                    if r.kind == .workstationReview {
                        Button("Check my setup") { model.respond(r, .accepted); WindowManager.shared.show(.setup) }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    } else if r.kind == .eyeRest {
                        Button("Rest eyes · 20 s") { model.respond(r, .accepted); WindowManager.shared.showRoutine(RoutineLibrary.routine("eyes-30")) }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    } else {
                        Button(r.kind.isBreak ? "1-min routine" : "Move · 1 min") {
                            model.respond(r, .accepted)
                            WindowManager.shared.showRoutine(RoutineLibrary.suggested(for: r.kind == .longBreak || r.kind == .longSession ? .microBreak : r.kind))
                        }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        if r.kind.isBreak {
                            Button("3-min break") { model.respond(r, .accepted); model.startGuidedBreak() }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                    Menu {
                        if model.canSnooze(r) {
                            Button("Snooze \(Int(model.settings.snoozeDuration / 60)) min") { model.respond(r, .snoozed) }
                        }
                        Button("Not helpful") { model.respond(r, .unhelpful) }
                        Button("Dismiss") { model.respond(r, .dismissed) }
                        if r.kind.postureIssue != nil {
                            Divider()
                            Button("Recalibrate posture…") { WindowManager.shared.show(.calibration) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }

    private func breakCard(_ g: GuidedBreak) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("On a break", systemImage: "cup.and.saucer").font(.system(size: 13, weight: .semibold))
                let left = max(0, g.end.timeIntervalSince(model.now))
                Text(left > 0 ? "\(Int(left) / 60):\(String(format: "%02d", Int(left) % 60)) left. Step away from the screen — Sway notices when you're gone." : "Welcome back.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("End break") { model.endGuidedBreak() }.buttonStyle(PillButtonStyle())
            }
        }
    }

    // MARK: Posture

    private var postureRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.metering.center.weighted.average")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Posture monitoring").font(.system(size: 12, weight: .medium))
                Text(postureSubtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.calibration == nil || model.posture.status == .needsRecalibration {
                Button("Calibrate") { WindowManager.shared.show(.calibration) }.buttonStyle(PillButtonStyle())
            } else {
                Toggle("", isOn: Binding(get: { model.settings.cameraMonitoringEnabled }, set: { model.setCameraMonitoring($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
    }

    private var postureSubtitle: String {
        if !model.settings.cameraMonitoringEnabled { return model.calibration == nil ? "Optional · uses the camera locally" : "Off" }
        if model.cameraAuthorization == .denied || model.cameraAuthorization == .restricted { return "Camera access denied in System Settings" }
        if model.isPaused { return "Paused" }
        if !model.tracker.isActive { return "Camera off while you're away" }
        switch model.cameraState {
        case .running:
            if let issue = model.activeIssues.first { return "\(model.posture.status.label) · \(issue.issue.title.lowercased())" }
            return model.posture.status.label
        default:
            return model.cameraState.label
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(RoutineCategory.allCases, id: \.self) { cat in
                    Section(cat.rawValue) {
                        ForEach(RoutineLibrary.all.filter { $0.category == cat }) { r in
                            Button("\(r.title) · \(r.durationLabel)") { WindowManager.shared.showRoutine(r) }
                        }
                    }
                }
            } label: {
                Label("Routines", systemImage: "figure.cooldown")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .buttonStyle(PillButtonStyle())

            if model.guidedBreak == nil {
                Button { model.startGuidedBreak() } label: { Label("Break", systemImage: "cup.and.saucer") }
                    .buttonStyle(PillButtonStyle())
            }
            Spacer()
            if model.isPaused {
                Button("Resume") { model.resume() }.buttonStyle(PillButtonStyle(prominent: true))
            } else {
                Menu {
                    Button("30 minutes") { model.pause(for: 30 * 60) }
                    Button("1 hour") { model.pause(for: 3600) }
                    Button("2 hours") { model.pause(for: 7200) }
                    Button("Until tomorrow") { model.pause(for: nil) }
                } label: {
                    Label("Pause", systemImage: "pause")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .font(.system(size: 12))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Dashboard") { WindowManager.shared.show(.dashboard) }
            Button("Setup") { WindowManager.shared.show(.setup) }
            Button("Settings") { WindowManager.shared.show(.settings) }
            Spacer()
            Button("Quit") {
                model.persist()
                NSApp.terminate(nil)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }
}
