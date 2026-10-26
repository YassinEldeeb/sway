import AVFoundation
import CoreImage
import SwayCore
import Vision

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isExternal: Bool
}

enum CameraState: Equatable {
    case off
    case starting
    case running(String)
    case unauthorized
    case unavailable(String)

    var isRunning: Bool { if case .running = self { return true } else { return false } }

    var label: String {
        switch self {
        case .off: return "Camera off"
        case .starting: return "Starting camera…"
        case .running(let name): return "Camera on · \(name)"
        case .unauthorized: return "Camera access not allowed"
        case .unavailable(let why): return why
        }
    }
}

struct VisionStats {
    var framesProcessed = 0
    var totalMs: Double = 0
    var lastMs: Double = 0
    var averageMs: Double { framesProcessed == 0 ? 0 : totalMs / Double(framesProcessed) }
}

/// Captures low-resolution frames at a low frame rate and turns a sparse
/// subset of them into `PostureObservation`s with Apple Vision. Frames are
/// processed in memory on a background queue and released immediately;
/// nothing is written to disk.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "sway.camera", qos: .utility)
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var observers: [NSObjectProtocol] = []

    // Accessed on `queue` only.
    private var interval: TimeInterval = 2
    private var lastProcessed: TimeInterval = 0
    private var frameCounter = 0
    private var stats = VisionStats()
    /// Upper-body pose runs on every third processed frame; its result is
    /// carried to the frames in between while fresh.
    private var lastShoulders: (l: Point2, r: Point2, confidence: Double, at: TimeInterval)?

    /// Called on the main queue.
    var onObservation: ((PostureObservation) -> Void)?
    var onState: ((CameraState) -> Void)?
    var onStats: ((VisionStats) -> Void)?

    private(set) var currentDeviceID: String?
    /// When the current start reported running (main thread).
    private(set) var runningSince: Date?
    /// Bumped by every start and stop (main thread). A start that completes
    /// after a newer stop or start is discarded, so a late "running" can't
    /// overwrite "off".
    private var generation = 0
    /// Main-thread copies, so recovery never waits on the capture queue.
    private var mainInterval: TimeInterval = 2
    private var restartAttempts = 0

    static func authorization() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { done(ok) } }
    }

    static func devices() -> [CameraDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
        types.append(.continuityCamera)
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        return found.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName, isExternal: $0.deviceType != .builtInWideAngleCamera) }
    }

    static func defaultDevice() -> CameraDevice? {
        let all = devices()
        return all.first { !$0.isExternal } ?? all.first
    }

    override init() {
        super.init()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] n in
            guard let self, let d = n.object as? AVCaptureDevice, d.uniqueID == self.currentDeviceID else { return }
            self.stop()
            self.onState?(.unavailable("Camera disconnected"))
        })
        observers.append(nc.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
            self?.recoverFromError()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Process at most one frame per `seconds`.
    func setInterval(_ seconds: TimeInterval) {
        mainInterval = max(0.1, seconds)
        let v = mainInterval
        queue.async { self.interval = v }
    }

    func start(deviceID: String?, interval: TimeInterval) {
        guard Self.authorization() == .authorized else {
            onState?(.unauthorized)
            return
        }
        let all = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
        guard let device = (deviceID.flatMap { id in all.first { $0.uniqueID == id } }) ?? (deviceID == nil ? (all.first { $0.deviceType == .builtInWideAngleCamera } ?? all.first) : nil) else {
            onState?(.unavailable(deviceID == nil ? "No camera found" : "Calibrated camera not connected"))
            return
        }
        if currentDeviceID == device.uniqueID, session.isRunning {
            setInterval(interval)
            return
        }
        onState?(.starting)
        currentDeviceID = device.uniqueID
        mainInterval = interval
        generation += 1
        let gen = generation
        let name = device.localizedName
        queue.async {
            self.interval = interval
            self.configure(device: device)
            self.setLowFrameRate(device)
            self.session.startRunning()
            let running = self.session.isRunning
            DispatchQueue.main.async {
                guard gen == self.generation else { return }   // superseded
                if running { self.runningSince = Date() }
                self.onState?(running ? .running(name) : .unavailable("Couldn't start the camera"))
            }
        }
    }

    func stop() {
        currentDeviceID = nil
        runningSince = nil
        generation += 1
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            if let input = self.input {
                self.session.beginConfiguration()
                self.session.removeInput(input)
                self.session.commitConfiguration()
                self.input = nil
            }
        }
        onState?(.off)
    }

    private func recoverFromError() {
        guard let id = currentDeviceID else { return }
        let attempt = restartAttempts
        restartAttempts += 1
        guard attempt < 3 else {
            stop()
            onState?(.unavailable("The camera stopped responding"))
            return
        }
        let delay = Double(1 << attempt) * 2
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Don't restart a camera that was stopped (or restarted) since.
            guard let self, self.generation == gen, self.currentDeviceID == id else { return }
            self.currentDeviceID = nil
            self.start(deviceID: id, interval: self.mainInterval)
        }
    }

    // MARK: Capture (on `queue`)

    private func configure(device: AVCaptureDevice) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input { session.removeInput(input) }
        input = nil
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.low) {
            session.sessionPreset = .low
        }
        guard let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
    }

    /// Ask for the lowest frame rate the camera supports, but not below 5 fps:
    /// fewer frames delivered means less work even before throttling. Runs
    /// after the session configuration is committed (the preset picks the
    /// format), and only uses durations inside a supported range, so a
    /// fractional rate like 7.5 or 29.97 fps can't be rejected.
    private func setLowFrameRate(_ device: AVCaptureDevice) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let range = ranges.max(by: { CMTimeCompare($0.maxFrameDuration, $1.maxFrameDuration) < 0 }) else { return }
        let fiveFps = CMTime(value: 1, timescale: 5)
        // The longest allowed duration, capped at 1/5 s, never shorter than the range's minimum.
        var duration = CMTimeCompare(range.maxFrameDuration, fiveFps) > 0 ? fiveFps : range.maxFrameDuration
        if CMTimeCompare(duration, range.minFrameDuration) < 0 { duration = range.minFrameDuration }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessed >= interval, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessed = now
        frameCounter += 1
        let started = CFAbsoluteTimeGetCurrent()
        let includeBody = frameCounter % 3 == 1
        var observation = Self.analyze(pixels, includeBody: includeBody, at: Date())
        if includeBody {
            if let l = observation.leftShoulder, let r = observation.rightShoulder {
                lastShoulders = (l, r, observation.shoulderConfidence, now)
            } else {
                lastShoulders = nil
            }
        } else if let cached = lastShoulders, now - cached.at <= interval * 3 + 1, observation.faceCenter != nil {
            observation.leftShoulder = cached.l
            observation.rightShoulder = cached.r
            observation.shoulderConfidence = cached.confidence
        }
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        stats.framesProcessed += 1
        stats.totalMs += ms
        stats.lastMs = ms
        let snapshot = stats
        DispatchQueue.main.async {
            self.restartAttempts = 0
            self.onObservation?(observation)
            self.onStats?(snapshot)
        }
    }

    /// Runs face (and every third frame, upper-body) detection on one frame.
    static func analyze(_ pixels: CVPixelBuffer, includeBody: Bool, at date: Date) -> PostureObservation {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest()
        if VNDetectFaceRectanglesRequest.supportedRevisions.contains(VNDetectFaceRectanglesRequestRevision3) {
            faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        }
        var requests: [VNRequest] = [faceRequest]
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        if includeBody { requests.append(bodyRequest) }
        do { try handler.perform(requests) } catch { return .noFace(at: date) }

        let faces = (faceRequest.results ?? []).filter { $0.confidence >= 0.3 }
        guard let face = faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            return .noFace(at: date)
        }
        // Count only faces of comparable size: a small face in the background
        // doesn't make the estimate ambiguous.
        let comparable = faces.filter { $0.boundingBox.height >= face.boundingBox.height * 0.6 }.count
        let deg = { (n: NSNumber?) -> Double? in n.map { $0.doubleValue * 180 / .pi } }
        var o = PostureObservation(
            timestamp: date, faceCount: comparable, faceConfidence: Double(face.confidence),
            faceCenter: Point2(Double(face.boundingBox.midX), Double(face.boundingBox.midY)),
            faceHeight: Double(face.boundingBox.height),
            pitch: deg(face.pitch), yaw: deg(face.yaw), roll: deg(face.roll))
        if includeBody, let body = bodyRequest.results?.first,
           let points = try? body.recognizedPoints(.torso),
           let l = points[.leftShoulder], let r = points[.rightShoulder] {
            o.leftShoulder = Point2(Double(l.location.x), Double(l.location.y))
            o.rightShoulder = Point2(Double(r.location.x), Double(r.location.y))
            o.shoulderConfidence = Double(min(l.confidence, r.confidence))
        }
        return o
    }
}
