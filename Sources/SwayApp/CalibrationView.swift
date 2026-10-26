import AVFoundation
import SwayCore
import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var model: AppModel
    @State private var devices = CameraService.devices()
    @State private var deviceID: String?
    @State private var step = Step.intro

    enum Step { case intro, capture }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .intro: intro
            case .capture:
                if let session = model.calibrationSession {
                    CaptureView(session: session, onDone: finish, onRetry: retry)
                } else {
                    ProgressView()
                }
            }
        }
        .padding(28)
        .padding(.top, 6)
        .frame(minWidth: 600, minHeight: 560)
        .onAppear {
            devices = CameraService.devices()
            deviceID = model.calibration?.cameraID ?? model.settings.preferredCameraID ?? CameraService.defaultDevice()?.id
            if let id = deviceID, !devices.contains(where: { $0.id == id }) { deviceID = devices.first?.id }
        }
        .onDisappear {
            if model.calibrationSession != nil { model.cancelCalibration() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calibrate your working position").font(.system(size: 22, weight: .semibold))
            Text("Sway compares how you sit later with how you sit now. There's no single correct posture — calibrate in a position that feels comfortable and that you'd happily return to.")
                .foregroundStyle(.secondary)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Before you start")
                    tip("display", "Use the camera on the screen you look at most. With an external monitor, a camera on top of it beats the laptop's.")
                    tip("arrow.up.and.down", "Point the camera at your face and upper body, roughly at eye level, with your face near the middle of the image.")
                    tip("sun.max", "Make sure your face is lit from the front, not only from a window behind you.")
                    tip("chair", "Sit back in your normal working position, looking at the screen.")
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("What it can and can't measure")
                    tip("checkmark.circle", "Relative changes from this baseline: head lower or pitched down, closer to the screen, tilted to a side, shoulders uneven (when both are visible), and long periods without movement.")
                    tip("xmark.circle", "It can't measure your spine, your actual screen height or viewing distance, or pain. Estimates are experimental and only reliable while the camera, chair and screen stay where they were.")
                }
            }
            if devices.isEmpty {
                Label("No camera found. Connect one, then reopen this window.", systemImage: "video.slash").foregroundStyle(Theme.warm)
            } else {
                Picker("Camera", selection: $deviceID) {
                    ForEach(devices) { d in Text(d.name + (d.isExternal ? " (external)" : "")).tag(Optional(d.id)) }
                }
                .frame(maxWidth: 380)
            }
            Spacer()
            HStack {
                Text("Takes about 15 seconds. Frames are analysed in memory and never saved.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Start") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(devices.isEmpty || deviceID == nil)
            }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon).foregroundStyle(Theme.accent) }
    }

    private func start() {
        let go = {
            guard let id = deviceID, let d = devices.first(where: { $0.id == id }) else { return }
            model.beginCalibration(device: d)
            step = .capture
        }
        switch CameraService.authorization() {
        case .authorized: go()
        case .notDetermined: model.requestCameraAccess { ok in if ok { go() } }
        default:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        }
    }

    private func retry() {
        model.cancelCalibration()
        step = .intro
    }

    private func finish(_ c: Calibration) {
        model.saveCalibration(c)
        NSApp.keyWindow?.close()
    }
}

private struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: CalibrationSession
    var onDone: (Calibration) -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                CameraPreview(session: model.camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(session.faceVisible ? Theme.accent : Theme.warm, lineWidth: 2))
                HStack(spacing: 6) {
                    StatusDot(color: session.faceVisible ? .green : Theme.warm)
                    Text(session.faceVisible ? "Face found" : "Looking for your face…")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
            .frame(height: 260)

            switch session.phase {
            case .positioning:
                Text("Sit comfortably in your normal working position and look at the screen.").font(.system(size: 15, weight: .medium))
                Text("Adjust the camera until your face is near the middle of the image.").foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Capture my position") { session.begin(.baseline) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!session.faceVisible)
                }
            case .baseline:
                Text("Hold still, breathing normally…").font(.system(size: 15, weight: .medium))
                ProgressView(value: session.progress).tint(Theme.accent)
            case .lookDownPrompt:
                Text("Optional: look down at your keyboard").font(.system(size: 15, weight: .medium))
                Text("Look at your keyboard the way you do while typing. This teaches Sway what 'head down' looks like for you and your camera.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Skip") { session.finish(minConfidence: model.settings.minFaceConfidence, includeLookDown: false) }
                    Spacer()
                    Button("I'm looking at my keyboard") { session.begin(.lookDown) }
                        .keyboardShortcut(.defaultAction)
                }
            case .lookDown:
                Text("Keep looking at the keyboard…").font(.system(size: 15, weight: .medium))
                ProgressView(value: session.progress).tint(Theme.accent)
            case .review:
                review
            }
        }
    }

    @ViewBuilder private var review: some View {
        switch session.result {
        case .success(let c):
            VStack(alignment: .leading, spacing: 8) {
                Label(c.report.quality == .good ? "Calibrated" : "Calibrated, with caveats", systemImage: "checkmark.seal")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                HStack(spacing: 10) {
                    ForEach(PostureIssue.allCases, id: \.self) { i in
                        Label(i.title, systemImage: (c.report.measurable[i] ?? false) ? "checkmark" : "minus")
                            .font(.system(size: 10.5))
                            .foregroundStyle((c.report.measurable[i] ?? false) ? .primary : .secondary)
                    }
                }
                ForEach(c.report.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Theme.warm) }
                ForEach(c.report.notes, id: \.self) { Label($0, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary) }
                HStack {
                    Button("Redo") { session.begin(.positioning) }
                    Spacer()
                    Button("Save and start monitoring") { onDone(c) }.keyboardShortcut(.defaultAction)
                }
            }
        case .failure(let e):
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't calibrate", systemImage: "xmark.octagon").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.warm)
                Text(e.message)
                HStack {
                    Button("Change camera") { onRetry() }
                    Spacer()
                    Button("Try again") { session.begin(.positioning) }.keyboardShortcut(.defaultAction)
                }
            }
        case nil:
            ProgressView()
        }
    }
}

/// The system draws the preview straight from the capture session; Sway
/// never receives or stores these frames.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        v.layer = layer
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
