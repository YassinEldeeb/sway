import AppKit
import SwayCore
import SwiftUI

/// Development tooling: seed demo data into a separate folder
/// (`SWAY_DATA_DIR`) and render each screen offscreen to PNG in light and
/// dark appearance, so the UI can be reviewed without touching real data or
/// the screen. Never used in normal runs.
@MainActor
enum Snapshots {
    static func seed(_ store: SwayStore) {
        guard ProcessInfo.processInfo.environment["SWAY_DATA_DIR"] != nil else {
            print("Refusing: set SWAY_DATA_DIR=<demo folder> so real data is never overwritten.")
            return
        }
        let cal = Calendar.current
        let now = Date()
        var rng = SystemRandomNumberGenerator()
        for offset in (0..<14).reversed() {
            let day = cal.date(byAdding: .day, value: -offset, to: now)!
            var r = DailyRecord(day: DayKey.key(day))
            let weekend = cal.isDateInWeekend(day)
            r.activeSeconds = weekend ? Double.random(in: 1...2.5, using: &rng) * 3600 : Double.random(in: 6.5...10.5, using: &rng) * 3600
            r.stretches = (0..<(weekend ? 3 : 9)).map { _ in Double.random(in: 18...95, using: &rng) * 60 }
            let breakCount = weekend ? 3 : Int.random(in: 6...11, using: &rng)
            r.breaks = (0..<breakCount).map { i in
                let start = day.addingTimeInterval(Double(i) * 3600)
                return BreakRecord(start: start, end: start.addingTimeInterval(Double.random(in: 150...900, using: &rng)), kind: i % 3 == 0 ? .long : .micro, source: .away)
            }
            r.cameraSeconds = weekend ? 0 : r.activeSeconds * 0.8
            r.cameraReliableSeconds = r.cameraSeconds * 0.9
            if !weekend {
                let trend = Double(14 - offset) / 14
                r.postureSeconds = [
                    .headDown: Double.random(in: 20...55, using: &rng) * 60 * (1.2 - trend * 0.6),
                    .forwardLean: Double.random(in: 5...25, using: &rng) * 60,
                    .lateralTilt: Double.random(in: 0...8, using: &rng) * 60,
                    .staticPosture: Double.random(in: 30...90, using: &rng) * 60 * (1.1 - trend * 0.5),
                ]
                r.postureEpisodes = [.headDown: Int.random(in: 1...4, using: &rng), .forwardLean: Int.random(in: 0...2, using: &rng), .staticPosture: 1]
                var micro = ResponseCounts(); micro.prompts = 5; micro.accepted = 3; micro.snoozed = 1; micro.dismissed = 1
                var long = ResponseCounts(); long.prompts = 3; long.accepted = 2; long.dismissed = 1
                var head = ResponseCounts(); head.prompts = 2; head.accepted = 1; head.helpful = 1
                r.prompts = [.microBreak: micro, .longBreak: long, .headDown: head]
                r.routinesCompleted = Int.random(in: 1...5, using: &rng)
                if offset % 2 == 0 {
                    r.comfort = ComfortCheckIn(neck: max(1, 6 - (14 - offset) / 3), upperBack: max(1, 4 - (14 - offset) / 5), lowerBack: offset % 4 == 0 ? 2 : nil, eyes: Int.random(in: 2...5, using: &rng), at: day)
                }
            }
            if offset == 0 {
                r.comfort = nil
                r.log = [LogEntry(at: now.addingTimeInterval(-7200), text: "Break (6 min, away)"), LogEntry(at: now.addingTimeInterval(-3000), text: "Head tilted down for 9 min"), LogEntry(at: now.addingTimeInterval(-1200), text: "Reminder: Movement break")]
            }
            try? store.save(r)
        }
        // A calibration and a 47-minute work stretch in progress.
        let base = (0..<15).map { i in PostureObservation(timestamp: now + Double(i), faceConfidence: 0.95, faceCenter: Point2(0.5, 0.55), faceHeight: 0.25, pitch: 0, yaw: 0, roll: 0, leftShoulder: Point2(0.7, 0.2), rightShoulder: Point2(0.3, 0.2), shoulderConfidence: 0.8) }
        if case .success(let c) = CalibrationBuilder.build(samples: base, cameraID: CameraService.defaultDevice()?.id ?? "demo", cameraName: CameraService.defaultDevice()?.name ?? "FaceTime HD Camera", minConfidence: 0.6, now: now.addingTimeInterval(-86_400 * 3)) {
            try? store.save(c)
        }
        var state = RuntimeState()
        var settings = CoachSettings()
        settings.onboardingComplete = true
        settings.cameraMonitoringEnabled = true
        for i in stride(from: 47 * 60, through: 0, by: -60) {
            _ = state.tracker.tick(now: now.addingTimeInterval(-Double(i)), idleSeconds: 2, settings: settings)
        }
        state.setupChecklist = ["monitor-height": "done", "viewing-distance": "done", "screen-angle": "todo", "chair-height": "done"]
        state.setupMeasurements = ["viewingDistanceCm": 58, "screenTop": 3, "laptopOnly": 0]
        try? store.save(state)
        try? store.save(settings)
        print("Seeded demo data in \(store.directory.path)")
    }

    static func render(to dir: URL) {
        guard AppModel.cameraBlocked, ProcessInfo.processInfo.environment["SWAY_DATA_DIR"] != nil else {
            print("Refusing: set SWAY_NO_CAMERA=1 and SWAY_DATA_DIR=<demo folder> for snapshots.")
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        model.start()
        let shots: [(String, CGSize, AnyView)] = [
            ("menu", CGSize(width: 340, height: 470), AnyView(MenuView())),
            ("dashboard-today", CGSize(width: 900, height: 900), AnyView(DashboardView(tab: .today))),
            ("dashboard-trends", CGSize(width: 900, height: 980), AnyView(DashboardView(tab: .trends))),
            ("dashboard-insights", CGSize(width: 900, height: 640), AnyView(DashboardView(tab: .insights))),
            ("routine-picker", CGSize(width: 560, height: 700), AnyView(RoutinePlayerView(routine: nil))),
            ("routine-step", CGSize(width: 560, height: 640), AnyView(RoutinePreview(routine: RoutineLibrary.routine("desk-60")!, step: 0))),
            ("routine-wrists", CGSize(width: 560, height: 640), AnyView(RoutinePreview(routine: RoutineLibrary.routine("wrists-60")!, step: 1))),
            ("calibration", CGSize(width: 640, height: 640), AnyView(CalibrationView())),
            ("setup", CGSize(width: 780, height: 680), AnyView(SetupAssistantView())),
            ("settings", CGSize(width: 640, height: 600), AnyView(SettingsView())),
            ("onboarding", CGSize(width: 560, height: 560), AnyView(OnboardingView())),
        ]
        for (name, size, view) in shots {
            for dark in [false, true] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                let root = view
                    .environmentObject(model)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: root)
                host.appearance = appearance
                host.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = appearance
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                window.contentView = nil
            }
        }
        print("Rendered \(shots.count * 2) snapshots to \(dir.path)")
    }

    static func renderIcon(to dir: URL) {
        let iconset = dir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let img = NSImage(size: NSSize(width: px, height: px), flipped: false) { rect in
                    let inset = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
                    let path = NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.225, yRadius: inset.width * 0.225)
                    NSGradient(colors: [NSColor(red: 0.30, green: 0.66, blue: 0.60, alpha: 1), NSColor(red: 0.16, green: 0.43, blue: 0.42, alpha: 1)])!.draw(in: path, angle: -90)
                    let config = NSImage.SymbolConfiguration(pointSize: inset.height * 0.52, weight: .medium).applying(.init(paletteColors: [.white]))
                    if let sym = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                        let s = sym.size
                        sym.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
                    }
                    return true
                }
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: iconset.appendingPathComponent(name))
            }
        }
        print("Wrote \(iconset.path)")
    }
}

/// A routine step frozen for snapshots.
private struct RoutinePreview: View {
    let routine: Routine
    let step: Int

    var body: some View {
        let s = routine.steps[step]
        VStack(spacing: 16) {
            HStack {
                Text(routine.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle().trim(from: 0, to: 0.62).stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                FigureView(motion: s.motion, paused: true).padding(34)
            }
            .frame(width: 260, height: 260)
            Text(s.title).font(.system(size: 22, weight: .semibold))
            Text("\(Int(Double(s.seconds) * 0.62)) s · \(s.reps ?? "")").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            Text(s.instruction).font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            if let c = s.caution { Label(c, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.warm) }
            Spacer()
            HStack { Button("Pause") {}.buttonStyle(PillButtonStyle()); Button("Skip step") {}.buttonStyle(PillButtonStyle()) }
            SafetyNote()
        }
        .padding(24)
    }
}
