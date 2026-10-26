import CoreVideo
import Foundation
import SwayCore

/// `Sway --benchmark`: measures the per-frame cost of the analysis pipeline
/// without a camera, so performance claims are measured, not assumed.
/// Vision runs on synthetic 640×480 frames (no face in them, so this is the
/// cost of looking; a frame with a face adds landmark work the live
/// Diagnostics tab reports).
enum Benchmark {
    static func run() {
        print("Sway benchmark")
        print("--------------")
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, nil, &pixels)
        guard let buffer = pixels else { print("could not allocate a frame"); return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = CVPixelBufferGetBytesPerRow(buffer) * 480
            let p = base.assumingMemoryBound(to: UInt8.self)
            for i in 0..<bytes { p[i] = UInt8(truncatingIfNeeded: (i / 7) &* 31) }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for (label, body) in [("face only", false), ("face + upper body", true)] {
            _ = CameraService.analyze(buffer, includeBody: body, at: Date())   // warm-up
            let n = 30
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<n { _ = CameraService.analyze(buffer, includeBody: body, at: Date()) }
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(n)
            print(String(format: "Vision %@: %.1f ms per frame (%d frames)", label, ms, n))
        }

        // Posture engine on a synthetic stream: one hour of 2-second samples.
        var engine = PostureEngine()
        var settings = CoachSettings()
        settings.cameraMonitoringEnabled = true
        let t0 = Date()
        let base = (0..<15).map { i in PostureObservation(timestamp: t0 + Double(i), faceConfidence: 0.95, faceCenter: Point2(0.5, 0.55), faceHeight: 0.25, pitch: 0, yaw: 0, roll: 0) }
        guard case .success(let cal) = CalibrationBuilder.build(samples: base, cameraID: "bench", cameraName: "bench", minConfidence: 0.6, now: t0) else { return }
        engine.configure(calibration: cal, cameraID: "bench", settings: settings)
        let samples = 1800
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<samples {
            let wobble = sin(Double(i) / 40) * 0.05
            _ = engine.process(PostureObservation(timestamp: t0 + 20 + Double(i) * 2, faceConfidence: 0.95, faceCenter: Point2(0.5, 0.55 - wobble), faceHeight: 0.25 * (1 + wobble), pitch: 0, yaw: 0, roll: wobble * 50), settings: settings)
        }
        let us = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(samples)
        print(String(format: "Posture engine: %.1f µs per sample", us))

        // Break scheduling + notification policy: one evaluation per tick.
        var tracker = ActivityTracker()
        var policy = InterventionEngine()
        let ticks = 8640   // 12 hours of 5-second ticks
        let s2 = CFAbsoluteTimeGetCurrent()
        for i in 0..<ticks {
            let now = t0 + Double(i) * 5
            _ = tracker.tick(now: now, idleSeconds: 1, settings: settings)
            let due = BreakScheduler.due(now: now, tracker: tracker, settings: settings)
            let d = policy.decide(candidates: due, now: now, context: InterruptionContext(), settings: settings)
            if let r = d.deliver { policy.recordDelivered(r, at: now) }
        }
        let tickUs = (CFAbsoluteTimeGetCurrent() - s2) * 1_000_000 / Double(ticks)
        print(String(format: "Activity tick + scheduling + policy: %.1f µs per tick", tickUs))
        print(String(format: "Process memory footprint: %.0f MB", ResourceMonitor.footprintMB()))
    }
}
