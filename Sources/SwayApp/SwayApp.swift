import AppKit
import SwayCore
import SwiftUI

@main
struct SwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let toolingFlags = ["--benchmark", "--seed-demo-data", "--snapshots", "--render-icon"]

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set the notification delegate before launch finishes: when a click
        // on a Sway notification launches the app, the click is delivered
        // right after, and would be lost without a delegate.
        guard !CommandLine.arguments.contains(where: Self.toolingFlags.contains) else { return }
        AppModel.shared.notifications.setUp()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--benchmark") {
            Benchmark.run()
            exit(0)
        }
        if args.contains("--seed-demo-data") {
            Snapshots.seed(AppModel.shared.store)
            exit(0)
        }
        if let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count {
            Snapshots.render(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            Snapshots.renderIcon(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            exit(0)
        }
        let model = AppModel.shared
        NSApp.setActivationPolicy(model.settings.showDockIcon ? .regular : .accessory)
        model.start()
        if !model.settings.onboardingComplete {
            WindowManager.shared.show(.onboarding)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.show(.dashboard)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in AppModel.shared.persist() }
    }
}

/// The menu-bar item: a figure that changes with state, a small camera mark
/// whenever the camera is on, and optionally the current work stretch.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let image = MenuBarIcon.image(symbol: symbol, cameraOn: model.cameraState.isRunning)
        if model.settings.showTimerInMenuBar, model.tracker.isActive, !model.isPaused {
            Image(nsImage: image)
            Text(Format.short(model.continuousWork))
        } else {
            Image(nsImage: image)
        }
    }

    private var symbol: String {
        if model.isPaused { return "pause.circle" }
        if model.guidedBreak != nil { return "cup.and.saucer" }
        if let a = model.attention {
            return a.kind.isBreak ? "figure.walk" : "exclamationmark.circle"
        }
        return "figure.stand"
    }
}

enum MenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(symbol: String, cameraOn: Bool) -> NSImage {
        let key = "\(symbol)-\(cameraOn)"
        if let img = cache[key] { return img }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = (NSImage(systemSymbolName: symbol, accessibilityDescription: "Sway") ?? NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Sway")!)
            .withSymbolConfiguration(config)!
        let cameraMark = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Camera on")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold))
        let width = base.size.width + (cameraOn ? 9 : 0)
        let size = NSSize(width: width, height: max(base.size.height, 16))
        let img = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: (size.height - base.size.height) / 2, width: base.size.width, height: base.size.height))
            if cameraOn, let mark = cameraMark {
                mark.draw(in: NSRect(x: base.size.width + 1, y: size.height - mark.size.height - 1, width: mark.size.width, height: mark.size.height))
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = cameraOn ? "Sway, camera on" : "Sway"
        cache[key] = img
        return img
    }
}

/// Plain AppKit windows hosting SwiftUI views: reliable for an app that
/// lives in the menu bar and has no Dock icon.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    enum Kind: String {
        case dashboard, settings, calibration, routine, setup, onboarding
    }

    private var windows: [Kind: NSWindow] = [:]

    func show(_ kind: Kind) {
        if let w = windows[kind] {
            present(w)
            return
        }
        let model = AppModel.shared
        let (title, size, view): (String, NSSize, AnyView) = {
            switch kind {
            case .dashboard: return ("Sway", NSSize(width: 860, height: 640), AnyView(DashboardView()))
            case .settings: return ("Sway Settings", NSSize(width: 620, height: 560), AnyView(SettingsView()))
            case .calibration: return ("Posture Calibration", NSSize(width: 640, height: 600), AnyView(CalibrationView()))
            case .routine: return ("Movement", NSSize(width: 560, height: 620), AnyView(RoutinePlayerView(routine: nil)))
            case .setup: return ("Workstation Setup", NSSize(width: 760, height: 660), AnyView(SetupAssistantView()))
            case .onboarding: return ("Welcome to Sway", NSSize(width: 560, height: 560), AnyView(OnboardingView()))
            }
        }()
        let host = NSHostingController(rootView: view.environmentObject(model))
        let w = NSWindow(contentViewController: host)
        w.title = title
        w.setContentSize(size)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("sway.\(kind.rawValue)")
        windows[kind] = w
        present(w)
    }

    func showRoutine(_ routine: Routine?) {
        close(.routine)
        let model = AppModel.shared
        let host = NSHostingController(rootView: RoutinePlayerView(routine: routine).environmentObject(model))
        let w = NSWindow(contentViewController: host)
        w.title = routine?.title ?? "Movement"
        w.setContentSize(NSSize(width: 560, height: 620))
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        w.center()
        windows[.routine] = w
        present(w)
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
        windows[kind] = nil
    }

    private func present(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let kind = windows.first(where: { $0.value === w })?.key else { return }
        if kind == .calibration, AppModel.shared.calibrationSession != nil {
            AppModel.shared.cancelCalibration()
        }
        // Drop the window so its SwiftUI state (and any preview layer) is freed.
        windows[kind] = nil
    }
}
