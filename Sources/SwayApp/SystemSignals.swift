import AppKit
import CoreAudio
import CoreMediaIO
import IOKit
import IOKit.ps

/// Signals the OS exposes without extra permissions. None of them reveal
/// content: only "how long since any input", "is a mic/camera running",
/// "does the front app cover the screen", "are we on battery".
enum SystemSignals {
    /// Seconds since the last keyboard, mouse or trackpad event, from the HID
    /// system's idle counter.
    static func idleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            let entry = IOIteratorNext(iterator)
            if entry != 0 {
                defer { IOObjectRelease(entry) }
                if let prop = IORegistryEntryCreateCFProperty(entry, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                   let ns = (prop as? NSNumber)?.uint64Value {
                    return TimeInterval(ns) / 1_000_000_000
                }
            }
        }
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .flagsChanged, .leftMouseDragged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    /// True when the default input device is running in any process.
    static func microphoneInUse() -> Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr, device != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// UIDs of video devices currently running in any process.
    static func runningCameraUIDs() -> Set<String> {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        var out = Set<String>()
        for id in ids {
            var runAddr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var got: UInt32 = 0
            guard CMIOObjectGetPropertyData(id, &runAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == noErr, running != 0 else { continue }
            var uidAddr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var uid: Unmanaged<CFString>?
            var uidSize: UInt32 = 0
            let status = withUnsafeMutablePointer(to: &uid) { ptr in
                CMIOObjectGetPropertyData(id, &uidAddr, 0, nil, UInt32(MemoryLayout<CFString?>.size), &uidSize, ptr)
            }
            if status == noErr, let s = uid?.takeRetainedValue() {
                out.insert(s as String)
            } else {
                out.insert("unknown-\(id)")
            }
        }
        return out
    }

    /// The frontmost app has a window covering an entire display.
    static func fullScreenAppInFront() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        let pid = front.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens.map { $0.frame.size }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"] else { continue }
            if screens.contains(where: { abs($0.width - width) < 1 && abs($0.height - height) < 1 }) {
                return true
            }
        }
        return false
    }

    static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

/// Sleep, wake, lock and fast-user-switch transitions.
final class PowerObserver {
    var onSuspend: (() -> Void)?
    var onResume: (() -> Void)?
    private var tokens: [NSObjectProtocol] = []

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        let suspend: [(NotificationCenter, Notification.Name)] = [
            (ws, NSWorkspace.willSleepNotification),
            (ws, NSWorkspace.screensDidSleepNotification),
            (ws, NSWorkspace.sessionDidResignActiveNotification),
            (dnc, Notification.Name("com.apple.screenIsLocked")),
        ]
        let resume: [(NotificationCenter, Notification.Name)] = [
            (ws, NSWorkspace.didWakeNotification),
            (ws, NSWorkspace.screensDidWakeNotification),
            (ws, NSWorkspace.sessionDidBecomeActiveNotification),
            (dnc, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in suspend {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.onSuspend?() })
        }
        for (center, name) in resume {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.onResume?() })
        }
    }

    deinit {
        let ws = NSWorkspace.shared.notificationCenter
        for t in tokens {
            ws.removeObserver(t)
            DistributedNotificationCenter.default().removeObserver(t)
        }
    }
}

/// This process's own CPU and memory, so Sway can show what it costs.
struct ResourceSample {
    var cpuPercent: Double
    var footprintMB: Double
}

final class ResourceMonitor {
    private var lastCPU: TimeInterval?
    private var lastWall: Date?

    static func cpuSeconds() -> TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let u = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1e6
        let s = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1e6
        return u + s
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// CPU percent since the previous call (100 = one core fully busy).
    func sample() -> ResourceSample? {
        let cpu = Self.cpuSeconds()
        let now = Date()
        defer { lastCPU = cpu; lastWall = now }
        guard let c0 = lastCPU, let w0 = lastWall else { return nil }
        let wall = now.timeIntervalSince(w0)
        guard wall > 0 else { return nil }
        return ResourceSample(cpuPercent: (cpu - c0) / wall * 100, footprintMB: Self.footprintMB())
    }
}
