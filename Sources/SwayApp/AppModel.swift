import AppKit
import AVFoundation
import Combine
import SwayCore

/// Collects frames during calibration. Observations go here instead of the
/// posture engine while it exists.
@MainActor
final class CalibrationSession: ObservableObject {
    enum Phase: Equatable { case positioning, baseline, lookDownPrompt, lookDown, review }

    let deviceID: String
    let deviceName: String
    @Published var phase: Phase = .positioning
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastObservation: PostureObservation?
    @Published var result: Result<Calibration, CalibrationError>?
    private(set) var baseline: [PostureObservation] = []
    private(set) var lookDown: [PostureObservation] = []
    private var phaseStart = Date()

    static let baselineSeconds: TimeInterval = 8
    static let lookDownSeconds: TimeInterval = 4

    init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    var faceVisible: Bool {
        guard let o = lastObservation, Date().timeIntervalSince(o.timestamp) < 2 else { return false }
        return o.faceCount == 1 && o.faceConfidence >= 0.6
    }

    func begin(_ p: Phase) {
        phase = p
        phaseStart = Date()
        progress = 0
        if p == .baseline { baseline = [] }
        if p == .lookDown { lookDown = [] }
    }

    func add(_ o: PostureObservation, minConfidence: Double) {
        lastObservation = o
        let elapsed = Date().timeIntervalSince(phaseStart)
        switch phase {
        case .baseline:
            baseline.append(o)
            progress = min(1, elapsed / Self.baselineSeconds)
            if elapsed >= Self.baselineSeconds { phase = .lookDownPrompt }
        case .lookDown:
            lookDown.append(o)
            progress = min(1, elapsed / Self.lookDownSeconds)
            if elapsed >= Self.lookDownSeconds { finish(minConfidence: minConfidence, includeLookDown: true) }
        default:
            break
        }
    }

    func finish(minConfidence: Double, includeLookDown: Bool) {
        result = CalibrationBuilder.build(samples: baseline, lookDown: includeLookDown ? lookDown : [], cameraID: deviceID, cameraName: deviceName, minConfidence: minConfidence, now: Date())
        phase = .review
    }
}

struct GuidedBreak: Equatable {
    var start: Date
    var end: Date
    var idleTicks = 0
    var totalTicks = 0
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store: SwayStore
    let notifications = NotificationService()
    let camera = CameraService()
    private let power = PowerObserver()
    private let resources = ResourceMonitor()

    @Published var settings: CoachSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published private(set) var runtime: RuntimeState
    @Published private(set) var calibration: Calibration?
    @Published private(set) var posture = PostureEngine()
    @Published private(set) var decision = InterventionDecision.empty
    @Published private(set) var cameraState: CameraState = .off
    @Published private(set) var visionStats = VisionStats()
    @Published private(set) var resourceSample: ResourceSample?
    @Published private(set) var adjustments = Adjustments.neutral
    @Published private(set) var patternIssues: Set<PostureIssue> = []
    @Published private(set) var now = Date()
    @Published private(set) var context = InterruptionContext()
    @Published private(set) var guidedBreak: GuidedBreak?
    @Published private(set) var suspendReasons: Set<SuspendReason> = []
    var suspended: Bool { !suspendReasons.isEmpty }
    @Published private(set) var cameraAuthorization = CameraService.authorization()
    @Published var calibrationSession: CalibrationSession?
    @Published var launchAtLoginMessage: String?

    private var ledger = Ledger()
    private var sleepClock = SleepClock()
    private var appNapToken: NSObjectProtocol?
    private var latestVisionStats = VisionStats()
    private var lastObservationAt: Date?
    /// Past days for trends and personalization, refreshed on persist.
    private var pastDays: [DailyRecord] = []
    private var timer: Timer?
    private var lastSave = Date.distantPast
    private var lastContextCheck = Date.distantPast
    private var lastPersonalization = Date.distantPast
    private var lastResourceSample = Date.distantPast
    private var lastCameraAttempt = Date.distantPast
    private var askedCameraThisLaunch = false
    private var lastCameraAccounting: Date?
    private var lastPrune = Date.distantPast
    private var lastFrequentCheck = Date.distantPast
    private var currentDay = DayKey.key(Date())
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // SWAY_DATA_DIR points the app at another folder (demo data, snapshots).
        let dir = ProcessInfo.processInfo.environment["SWAY_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        store = SwayStore(directory: dir ?? SwayStore.defaultDirectory())
        settings = store.loadSettings()
        runtime = store.loadRuntime()
        calibration = store.loadCalibration()
        let store = self.store
        ledger.loader = { store.loadDay($0) }
        let today = DayKey.key(Date())
        if let r = store.loadDay(today) { ledger.records[today] = r }
        // A guided break can't survive a relaunch (its timer is gone).
        if runtime.tracker.guidedBreakStart != nil { runtime.tracker.cancelGuidedBreak() }
        suspendReasons = PowerObserver.currentReasons()
        context.pausedUntil = runtime.pausedUntil
        posture.configure(calibration: calibration, cameraID: calibration?.cameraID, settings: settings)

        camera.onState = { [weak self] s in self?.cameraStateChanged(s) }
        camera.onObservation = { [weak self] o in self?.observe(o) }
        camera.onStats = { [weak self] s in self?.latestVisionStats = s }
        power.onChange = { [weak self] reason, active in self?.powerChanged(reason, active: active) }
        notifications.onPostFailed = { [weak self] kind, why in
            guard let self else { return }
            self.runtime.decisionLog.note("\(kind.title): macOS didn't show the notification (\(why))", kind: kind, at: self.now)
        }
        notifications.onTap = { [weak self] tap, instance, kind in
            self?.handleNotification(tap, instance: instance, kind: kind)
        }
        NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)
            .sink { [weak self] _ in self?.lastCameraAttempt = .distantPast }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &cancellables)
    }

    func start() {
        // A menu-bar app has no visible windows, so App Nap would delay the
        // timer by minutes; the tick is tiny, so opt out (system sleep is
        // still allowed).
        appNapToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Tracking activity for break reminders")
        reloadPastDays()
        notifications.setUp()   // idempotent; normally already done before launch finished
        if settings.onboardingComplete, settings.notificationsEnabled { notifications.askIfUndetermined() }
        recomputePersonalization()
        recomputePatterns()
        tick()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 1.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Derived state

    var today: DailyRecord {
        ledger.records[DayKey.key(now)] ?? DailyRecord(day: DayKey.key(now))
    }

    var tracker: ActivityTracker { runtime.tracker }

    var isPaused: Bool { (runtime.pausedUntil ?? .distantPast) > now }

    var continuousWork: TimeInterval { runtime.tracker.continuousWork(at: now) }

    var nextBreak: UpcomingBreak? { BreakScheduler.next(now: now, tracker: runtime.tracker, settings: settings, adjustments: adjustments) }

    /// The reminder to show in the menu (delivered or passive).
    var attention: DueReminder? { decision.deliver ?? decision.passive.first }

    var notificationsLastHour: Int { runtime.engine.deliveryTimes.filter { now.timeIntervalSince($0) < 3600 }.count }
    var notificationsToday: Int { runtime.engine.deliveryTimes.filter { Calendar.current.isDate($0, inSameDayAs: now) }.count }

    var activeIssues: [ActiveIssue] { cameraState.isRunning ? posture.activeIssues() : [] }
    var buildingIssues: [BuildingIssue] { cameraState.isRunning ? posture.buildingIssues() : [] }

    /// Today's active time including the stretch in progress.
    var longestStretchToday: TimeInterval {
        max(today.longestStretch, runtime.tracker.sessionStart.map { Calendar.current.isDate($0, inSameDayAs: now) ? continuousWork : 0 } ?? 0)
    }

    /// The last `days` days, oldest first, ending with today (from memory).
    func history(days: Int) -> [DailyRecord] {
        // Days changed in memory (e.g. yesterday, when an overnight absence
        // closes in the morning) win over the cached copy.
        Array(pastDays.suffix(max(0, days - 1))).map { ledger.records[$0.day] ?? $0 } + [today]
    }

    private func reloadPastDays() {
        pastDays = Array(store.recent(days: 31, now: now).dropLast())
    }

    func canSnooze(_ r: DueReminder) -> Bool { runtime.engine.canSnooze(r.instanceID, settings: settings) }

    // MARK: Tick

    func tick() {
        now = Date()
        let day = DayKey.key(now)
        if day != currentDay {
            persist()
            currentDay = day
            ledger.records = ledger.records.filter { $0.key >= day }
            reloadPastDays()
            recomputePatterns()
            recomputePersonalization()
        }
        reconcileSuspension()
        let slept = sleepClock.sleptSinceLastCall()
        if !suspended {
            apply(runtime.tracker.tick(now: now, idleSeconds: SystemSignals.idleSeconds(), settings: settings, sleptDuringGap: slept))
        }
        visionStats = latestVisionStats
        watchCameraHealth()
        if now.timeIntervalSince(lastContextCheck) >= 10 { refreshContext() }
        updateCamera()
        accountCamera()
        updateGuidedBreak()
        if now.timeIntervalSince(lastFrequentCheck) >= 60 { checkFrequentPatterns() }
        evaluate()
        if now.timeIntervalSince(lastResourceSample) >= 30 {
            lastResourceSample = now
            if let s = resources.sample() { resourceSample = s }
        }
        if now.timeIntervalSince(lastSave) >= 60 { persist() }
        if now.timeIntervalSince(lastPersonalization) >= 3600 { recomputePersonalization() }
        if now.timeIntervalSince(lastPrune) >= 86_400 {
            lastPrune = now
            store.prune(retentionDays: settings.retentionDays, now: now)
        }
    }

    private func apply(_ events: [ActivityEvent]) {
        guard !events.isEmpty else { return }
        ledger.apply(events)
    }

    private func refreshContext() {
        lastContextCheck = now
        // While Sway's own camera is on (or starting), "a camera is running"
        // can't be attributed to another app, so only the microphone counts.
        let ownCameraActive = cameraState.isRunning || cameraState == .starting || calibrationSession != nil
        let otherCamera = ownCameraActive ? false : !SystemSignals.runningCameraUIDs().isEmpty
        context.micOrCameraInUseByOthers = SystemSignals.microphoneInUse() || otherCamera
        context.fullScreenAppInFront = SystemSignals.fullScreenAppInFront()
        context.pausedUntil = runtime.pausedUntil
        cameraAuthorization = CameraService.authorization()
        notifications.refresh()
    }

    private func evaluate() {
        guard notifications.answered else { return }
        var candidates = BreakScheduler.due(now: now, tracker: runtime.tracker, settings: settings, adjustments: adjustments)
        let breakDueAt = candidates.filter(\.kind.isBreak).map(\.dueAt).max()
        if guidedBreak == nil {
            candidates += PostureReminders.candidates(active: activeIssues, setupIssues: patternIssues, breakDueAt: breakDueAt,
                                                      nextBreakAt: nextBreak?.at, now: now, settings: settings)
        }
        context.pausedUntil = runtime.pausedUntil
        context.systemNotificationsAllowed = notifications.canShow
        decision = runtime.engine.evaluate(candidates: candidates, now: now, context: context, settings: settings, adjustments: adjustments)
        // Never leave an obsolete notification on screen.
        for k in decision.expired { notifications.clear(k) }
        if let r = decision.deliver {
            runtime.engine.recordDelivered(r, at: now)
            ledger.prompted(r.kind, at: now)
            notifications.post(r, canSnooze: canSnooze(r))
        }
        runtime.decisionLog.record(decision, now: now)
    }

    /// Issues that keep coming back in short bouts: recorded once a day,
    /// and they lead to the workstation suggestion, not posture reminders.
    private func checkFrequentPatterns() {
        lastFrequentCheck = now
        guard cameraState.isRunning else { return }
        var changed = false
        for (issue, flag) in posture.frequentFlags(now: now, settings: settings) {
            if ledger.flagFrequent(issue, flag) {
                changed = true
                runtime.decisionLog.note("\(issue.title) came up often in short bouts (\(Int((flag.share * 100).rounded()))% of \(Int(flag.observedMinutes.rounded())) min observed)", kind: ReminderKind(issue), at: now)
            }
        }
        if changed { recomputePatterns() }
    }

    // MARK: Camera

    private var effectiveCameraID: String? {
        settings.preferredCameraID ?? calibration?.cameraID ?? CameraService.defaultDevice()?.id
    }

    /// SWAY_NO_CAMERA=1 keeps the camera off whatever the settings say
    /// (snapshots and other tooling).
    static let cameraBlocked = ProcessInfo.processInfo.environment["SWAY_NO_CAMERA"] != nil

    var wantsCamera: Bool {
        if Self.cameraBlocked { return false }
        if calibrationSession != nil { return !suspended }
        guard settings.cameraMonitoringEnabled, cameraAuthorization == .authorized, !suspended, !isPaused,
              let cal = calibration, cal.cameraID == effectiveCameraID else { return false }
        // Only while the user is at the computer: the camera turns off when
        // they step away and back on when they return.
        return runtime.tracker.isActive
    }

    private var cameraInterval: TimeInterval {
        if calibrationSession != nil { return 0.25 }
        var i = settings.sampleInterval
        if SystemSignals.onBattery() { i *= 2 }
        if posture.status == .searching { i *= 2.5 }
        return i
    }

    private func updateCamera() {
        askForCameraIfNeeded()
        let running = cameraState.isRunning || cameraState == .starting
        if wantsCamera {
            if running {
                camera.setInterval(cameraInterval)
            } else if now.timeIntervalSince(lastCameraAttempt) >= 30 {
                lastCameraAttempt = now
                let id = calibrationSession?.deviceID ?? calibration?.cameraID
                camera.start(deviceID: id, interval: cameraInterval)
            }
        } else if running {
            camera.stop()
        }
        if !wantsCamera, posture.status != .off || !posture.activeIssues().isEmpty {
            stopPosture(status: postureIdleStatus)
        }
    }

    /// Monitoring is on but macOS has no answer for this build (a reinstall
    /// with a new signature resets it): ask once per launch instead of
    /// staying silently off.
    private func askForCameraIfNeeded() {
        guard !Self.cameraBlocked, !askedCameraThisLaunch, settings.cameraMonitoringEnabled, calibration != nil else { return }
        cameraAuthorization = CameraService.authorization()
        guard cameraAuthorization == .notDetermined else { return }
        askedCameraThisLaunch = true
        requestCameraAccess { _ in self.lastCameraAttempt = .distantPast }
    }

    private var postureIdleStatus: TrackingStatus {
        if calibration == nil { return .notCalibrated }
        if let id = effectiveCameraID, calibration?.cameraID != id { return .needsRecalibration }
        return .off
    }

    private func stopPosture(status: TrackingStatus) {
        for e in posture.stop(status: status) {
            if case .ended(let ep) = e { recordEpisode(ep) }
        }
    }

    private func cameraStateChanged(_ s: CameraState) {
        cameraState = s
        if s.isRunning { lastObservationAt = nil }
        if !s.isRunning { lastCameraAccounting = nil }
        if case .unavailable = s { stopPosture(status: .off) }
        if s == .unauthorized { cameraAuthorization = CameraService.authorization() }
    }

    private func accountCamera() {
        guard cameraState.isRunning, calibrationSession == nil else { lastCameraAccounting = nil; return }
        if let last = lastCameraAccounting {
            let dt = min(now.timeIntervalSince(last), 10)
            if dt > 0 { ledger.addCamera(seconds: dt, reliable: posture.status == .tracking, at: now) }
        }
        lastCameraAccounting = now
    }

    /// Frames stopped arriving while the camera claims to run (a stalled
    /// device, a lost start/stop race): don't keep showing a frozen posture
    /// state; stop and restart the camera.
    private func watchCameraHealth() {
        guard cameraState.isRunning, calibrationSession == nil else { return }
        let limit = max(30, cameraInterval * 5)
        let last = lastObservationAt ?? camera.runningSince ?? now
        if now.timeIntervalSince(last) > limit {
            stopPosture(status: .searching)
            camera.stop()
            lastObservationAt = nil
            lastCameraAttempt = .distantPast
        }
    }

    private func observe(_ o: PostureObservation) {
        lastObservationAt = o.timestamp
        if let session = calibrationSession {
            session.add(o, minConfidence: settings.minFaceConfidence)
            return
        }
        guard wantsCamera else { return }
        for e in posture.process(o, settings: settings) {
            if case .ended(let ep) = e { recordEpisode(ep) }
        }
    }

    private func recordEpisode(_ ep: PostureEpisode) {
        guard ep.duration >= 30 else { return }
        ledger.apply(ep)
        recomputePatterns()
    }

    func requestCameraAccess(_ done: @escaping (Bool) -> Void) {
        CameraService.requestAccess { ok in
            self.cameraAuthorization = CameraService.authorization()
            done(ok)
        }
    }

    func beginCalibration(device: CameraDevice) {
        guard !Self.cameraBlocked else { return }
        if cameraState.isRunning { camera.stop() }
        stopPosture(status: .off)
        calibrationSession = CalibrationSession(deviceID: device.id, deviceName: device.name)
        lastCameraAttempt = .distantPast
        camera.start(deviceID: device.id, interval: 0.25)
        lastCameraAttempt = now
    }

    func saveCalibration(_ c: Calibration) {
        calibration = c
        try? store.save(c)
        calibrationSession = nil
        camera.stop()
        var s = settings
        s.preferredCameraID = c.cameraID
        s.cameraMonitoringEnabled = true
        settings = s
        posture.configure(calibration: c, cameraID: c.cameraID, settings: settings, adjustments: adjustments)
        lastCameraAttempt = .distantPast
        ledger.note("Calibrated with \(c.cameraName)", at: Date())
    }

    func cancelCalibration() {
        calibrationSession = nil
        camera.stop()
        lastCameraAttempt = .distantPast
    }

    func setCameraMonitoring(_ on: Bool) {
        var s = settings
        s.cameraMonitoringEnabled = on
        settings = s
        if !on {
            camera.stop()
            stopPosture(status: .off)
        }
        lastCameraAttempt = .distantPast
        tick()
    }

    // MARK: Sleep / wake / lock

    private func powerChanged(_ reason: SuspendReason, active: Bool) {
        var reasons = suspendReasons
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
        setSuspendReasons(reasons)
    }

    /// Notifications can be missed; the lock, session and display state can
    /// be read directly. "Asleep" is cleared by the timer running at all.
    private func reconcileSuspension() {
        var reasons = PowerObserver.currentReasons()
        if suspendReasons.contains(.sleep), Date().timeIntervalSince(sleepSince ?? .distantPast) < 15 {
            reasons.insert(.sleep)
        }
        setSuspendReasons(reasons)
    }

    private var sleepSince: Date?

    private func setSuspendReasons(_ reasons: Set<SuspendReason>) {
        let was = suspended
        if reasons.contains(.sleep), !suspendReasons.contains(.sleep) { sleepSince = Date() }
        suspendReasons = reasons
        if !was, suspended {
            apply(runtime.tracker.suspend(now: Date(), idleSeconds: SystemSignals.idleSeconds(), settings: settings))
            camera.stop()
            stopPosture(status: .off)
            persist()
        } else if was, !suspended {
            runtime.tracker.resume(now: Date())
            lastCameraAttempt = .distantPast
            cameraAuthorization = CameraService.authorization()
            _ = sleepClock.sleptSinceLastCall()
        }
    }

    // MARK: Responses

    /// A click on a notification (body, button or close).
    func handleNotification(_ tap: NotificationTap, instance: String, kind: ReminderKind) {
        let routed = NotificationRouting.route(tap, kind: kind)
        handle(action: routed.action, response: routed.response, instance: instance, kind: kind)
    }

    /// An action from the menu-bar card.
    func perform(_ action: CoachAction, _ r: DueReminder) {
        handleNotification(.button(action), instance: r.instanceID, kind: r.kind)
    }

    func dismiss(_ r: DueReminder) {
        handleNotification(.dismissed, instance: r.instanceID, kind: r.kind)
    }

    func handle(action: CoachAction?, response: PromptResponse?, instance: String, kind: ReminderKind) {
        if let response { record(response, kind: kind, instance: instance) }
        switch action {
        case .startRoutine: WindowManager.shared.showRoutine(RoutineLibrary.suggested(for: kind))
        case .takeBreak: startGuidedBreak()
        case .recalibrate: WindowManager.shared.show(.calibration)
        case .eyeDone: runtime.tracker.acknowledgeEyeRest(at: Date())
        case .openSetup:
            setupFocus = PostureReminders.setupIssue(of: instance).map(ReminderKind.setupItem(for:))
            WindowManager.shared.show(.setup)
        case .snooze, .notHelpful, nil: break
        }
        evaluate()
    }

    /// The setup item a workstation suggestion points to, for the setup
    /// assistant to open at.
    @Published var setupFocus: String?

    func record(_ response: PromptResponse, kind: ReminderKind, instance: String) {
        let t = Date()
        if response == .snoozed {
            runtime.engine.snooze(instance, kind: kind, now: t, settings: settings)
        }
        runtime.engine.record(response, kind: kind, instanceID: instance.isEmpty ? nil : instance, now: t)
        ledger.responded(kind, response, at: t)
        if response != .helpful { notifications.clear(kind) }
        let what: String
        switch response {
        case .accepted: what = "you acted on it"
        case .snoozed: what = "snoozed for \(Int(settings.snoozeDuration / 60)) min"
        case .dismissed: what = "dismissed"
        case .unhelpful: what = "marked not helpful"
        case .helpful: what = "marked helpful"
        }
        if response != .snoozed { runtime.decisionLog.answered(instance) }
        runtime.decisionLog.note("\(kind.title): \(what)", kind: kind, at: t)
        if runtime.engine.isSilenced(kind, now: t), response == .dismissed || response == .unhelpful {
            runtime.decisionLog.note("\(kind.title): menu bar only for the rest of today after repeated dismissals", kind: kind, at: t)
        }
        if response == .unhelpful || response == .dismissed { recomputePersonalization() }
    }

    /// From the menu-bar card (snooze, not helpful, dismiss).
    func respond(_ r: DueReminder, _ response: PromptResponse) {
        switch response {
        case .snoozed: perform(.snooze, r)
        case .unhelpful: perform(.notHelpful, r)
        case .dismissed: dismiss(r)
        default: handle(action: nil, response: response, instance: r.instanceID, kind: r.kind)
        }
    }

    // MARK: Breaks & routines

    func startGuidedBreak(minutes: Double = 3) {
        let t = Date()
        let end = t.addingTimeInterval(minutes * 60)
        runtime.tracker.beginGuidedBreak(at: t, until: end)
        guidedBreak = GuidedBreak(start: t, end: end)
        notifications.clearAll()
        runtime.engine.forgetPosted()
    }

    func endGuidedBreak() {
        guard let g = guidedBreak else { return }
        let fraction = g.totalTicks == 0 ? 0 : Double(g.idleTicks) / Double(g.totalTicks)
        apply(runtime.tracker.finishGuidedBreak(at: Date(), idleFraction: fraction))
        guidedBreak = nil
        evaluate()
    }

    private func updateGuidedBreak() {
        guard var g = guidedBreak else { return }
        g.totalTicks += 1
        if SystemSignals.idleSeconds() >= 8 || !runtime.tracker.isActive { g.idleTicks += 1 }
        guidedBreak = g
        if now >= g.end { endGuidedBreak() }
    }

    func routineFinished(_ routine: Routine, start: Date, completedFraction: Double) {
        let end = Date()
        if completedFraction >= 0.6 {
            apply(runtime.tracker.completeRoutine(start: start, end: end))
            ledger.routineCompleted(at: end)
            if routine.category == .eyes { runtime.tracker.acknowledgeEyeRest(at: end) }
        }
        evaluate()
        persist()
    }

    func routineFeedback(helpful: Bool) {
        ledger.responded(.microBreak, helpful ? .helpful : .unhelpful, at: Date())
        persist()
    }

    // MARK: Pause

    func pause(for seconds: TimeInterval?) {
        if let seconds {
            runtime.pausedUntil = Date().addingTimeInterval(seconds)
        } else {
            // Until tomorrow morning.
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
            runtime.pausedUntil = cal.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow)
        }
        notifications.clearAll()
        runtime.engine.forgetPosted()
        camera.stop()
        stopPosture(status: .off)
        persist()
        tick()
    }

    func resume() {
        runtime.pausedUntil = nil
        lastCameraAttempt = .distantPast
        persist()
        tick()
    }

    // MARK: Comfort, personalization, patterns

    func saveComfort(_ c: ComfortCheckIn) {
        ledger.setComfort(c)
        persist()
    }

    func recomputePersonalization() {
        lastPersonalization = Date()
        let days = history(days: 14)
        var counts: [ReminderKind: ResponseCounts] = [:]
        for d in days { for (k, c) in d.prompts { counts[k, default: ResponseCounts()] = counts[k, default: ResponseCounts()] + c } }
        adjustments = Personalization.compute(counts: counts, naturalStretches: days.flatMap(\.stretches))
        posture.rebuildDetectors(settings: settings, adjustments: adjustments)
    }

    private func recomputePatterns() {
        let earlier = history(days: 7).dropLast().map { Set($0.postureEpisodes.filter { $0.value > 0 }.keys) }
        patternIssues = PatternDetector.persistent(todayEpisodes: today.postureEpisodes, recentDays: Array(earlier))
            .union(today.frequentPatterns.keys)
    }

    func setChecklist(_ id: String, _ status: String?) {
        let old = runtime.setupChecklist[id]
        runtime.setupChecklist[id] = status
        // Workstation changes appear next to comfort and posture trends.
        if status == "done", old != "done", let item = WorkstationGuide.items.first(where: { $0.id == id }) {
            ledger.note("Workstation: \(item.title.lowercased()) set", at: Date())
        }
        persist()
    }

    func setMeasurement(_ id: String, _ value: Double?) {
        runtime.setupMeasurements[id] = value
        persist()
    }

    // MARK: Settings & data

    private func settingsChanged(from old: CoachSettings) {
        let clean = settings.sanitized()
        if clean != settings {
            settings = clean
            return
        }
        try? store.save(settings)
        posture.rebuildDetectors(settings: settings, adjustments: adjustments)
        if old.showDockIcon != settings.showDockIcon {
            NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        }
        if old.preferredCameraID != settings.preferredCameraID || old.cameraMonitoringEnabled != settings.cameraMonitoringEnabled {
            if cameraState.isRunning { camera.stop() }
            lastCameraAttempt = .distantPast
        }
    }

    func persist() {
        lastSave = Date()
        try? store.save(runtime)
        for (_, r) in ledger.records { try? store.save(r) }
    }

    func deleteAllData() {
        camera.stop()
        stopPosture(status: .notCalibrated)
        notifications.clearAll()
        runtime.engine.forgetPosted()
        try? store.deleteAll()
        let store = self.store
        ledger = Ledger(loader: { store.loadDay($0) })
        pastDays = []
        runtime = RuntimeState()
        calibration = nil
        adjustments = .neutral
        patternIssues = []
        var fresh = CoachSettings()
        fresh.onboardingComplete = true
        settings = fresh
        posture.configure(calibration: nil, cameraID: nil, settings: settings)
        try? store.save(settings)
        tick()
    }

    func resetPersonalization() {
        runtime.engine = InterventionEngine()
        for key in ledger.records.keys { ledger.update(key) { $0.prompts = [:] } }
        for d in store.recent(days: 30, now: now) where !d.prompts.isEmpty {
            var copy = d
            copy.prompts = [:]
            try? store.save(copy)
        }
        recomputePersonalization()
        persist()
    }
}

