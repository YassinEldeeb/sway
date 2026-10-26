import Foundation

/// The user's own comfortable working position, as seen by one camera.
public struct PostureBaseline: Codable, Equatable, Sendable {
    public var faceCenter: Point2
    public var faceHeight: Double
    public var pitch: Double?
    public var yaw: Double?
    public var roll: Double?
    public var shoulderSlope: Double?
    /// Sample-to-sample noise while sitting still (std dev of the face's
    /// vertical position in face heights).
    public var noise: Double
}

public struct CalibrationReport: Codable, Equatable, Sendable {
    public enum Quality: String, Codable, Sendable { case good, usable }
    public var quality: Quality
    public var validSamples: Int
    public var totalSamples: Int
    public var measurable: [PostureIssue: Bool]
    public var warnings: [String]
    public var notes: [String]
}

public struct Calibration: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var cameraID: String
    public var cameraName: String
    public var baseline: PostureBaseline
    /// Features of the "look at your keyboard" reference, when captured:
    /// (face drop in face heights, pitch change in degrees).
    public var lookDown: Point2?
    public var report: CalibrationReport
}

public enum CalibrationError: Error, Equatable, Sendable {
    case notEnoughFace(valid: Int, total: Int)
    case tooFar
    case tooMuchMovement
    case multipleFaces

    public var message: String {
        switch self {
        case .notEnoughFace(let v, let t):
            return "Your face was clearly visible in only \(v) of \(t) frames. Check the lighting and that the camera faces you, then try again."
        case .tooFar:
            return "You appear very small in the camera image. Move the camera closer or use the camera on the screen you look at most."
        case .tooMuchMovement:
            return "There was a lot of movement during capture. Sit comfortably, look at the screen, and hold still for a few seconds."
        case .multipleFaces:
            return "More than one face was visible. Calibrate when only you are in view."
        }
    }
}

public enum CalibrationBuilder {
    public static let minValidSamples = 8

    static func isValid(_ o: PostureObservation, minConfidence: Double) -> Bool {
        o.faceCount == 1 && o.faceConfidence >= minConfidence && o.faceCenter != nil && (o.faceHeight ?? 0) > 0
    }

    public static func build(samples: [PostureObservation], lookDown: [PostureObservation] = [], cameraID: String, cameraName: String, minConfidence: Double, now: Date) -> Result<Calibration, CalibrationError> {
        let multi = samples.filter { $0.faceCount > 1 }.count
        if !samples.isEmpty, Double(multi) / Double(samples.count) > 0.3 { return .failure(.multipleFaces) }
        let valid = samples.filter { isValid($0, minConfidence: minConfidence) }
        guard valid.count >= minValidSamples, Double(valid.count) >= Double(samples.count) * 0.6 else {
            return .failure(.notEnoughFace(valid: valid.count, total: samples.count))
        }
        let heights = valid.compactMap(\.faceHeight)
        let h = median(heights)
        if h < 0.07 { return .failure(.tooFar) }
        let cx = median(valid.compactMap { $0.faceCenter?.x })
        let cy = median(valid.compactMap { $0.faceCenter?.y })
        let ys = valid.compactMap { $0.faceCenter.map { $0.y / h } }
        let noise = stdDev(ys)
        if noise > 0.15 { return .failure(.tooMuchMovement) }

        let pitches = valid.compactMap(\.pitch)
        let yaws = valid.compactMap(\.yaw)
        let rolls = valid.compactMap(\.roll)
        let slopes = valid.compactMap(\.shoulderSlope)
        let shouldersSeen = Double(slopes.count) / Double(valid.count)

        let baseline = PostureBaseline(
            faceCenter: Point2(cx, cy), faceHeight: h,
            pitch: pitches.count >= valid.count / 2 ? median(pitches) : nil,
            yaw: yaws.count >= valid.count / 2 ? median(yaws) : nil,
            roll: rolls.count >= valid.count / 2 ? median(rolls) : nil,
            shoulderSlope: shouldersSeen >= 0.7 ? median(slopes) : nil,
            noise: noise)

        var warnings: [String] = []
        var notes: [String] = []
        if h < 0.12 {
            warnings.append("You're fairly far from the camera, so leaning-in estimates are less precise.")
        }
        if cy < 0.3 {
            warnings.append("Your face sits low in the camera image: the camera points above you. Tilting it down slightly makes head-position estimates more reliable.")
        } else if cy > 0.85 {
            warnings.append("Your face sits near the top of the camera image. Tilting the camera up slightly gives more margin.")
        }
        if cx < 0.2 || cx > 0.8 || abs(baseline.yaw ?? 0) > 25 {
            warnings.append("The camera views you from the side. Use the camera on the screen you look at most; side-on views make tilt estimates less reliable.")
        }

        var lookDownRef: Point2?
        let ldValid = lookDown.filter { isValid($0, minConfidence: minConfidence) }
        if ldValid.count >= 3 {
            let ldY = median(ldValid.compactMap { $0.faceCenter?.y })
            let drop = (cy - ldY) / h
            let ldPitches = ldValid.compactMap(\.pitch)
            let dPitch = (baseline.pitch != nil && ldPitches.count >= 2) ? median(ldPitches) - baseline.pitch! : 0
            // The face must clearly move down (in the image) and by well more
            // than sitting-still noise; a tiny or upward reference would make
            // head-down detection hypersensitive or inverted.
            if drop >= max(0.15, 4 * noise) {
                lookDownRef = Point2(drop, dPitch)
                notes.append("Head-down detection is tuned to how your head moved when you looked at your keyboard.")
            } else {
                warnings.append("We saw little difference when you looked at your keyboard, so head-down detection uses a cautious default.")
            }
        } else if !lookDown.isEmpty {
            warnings.append("Your face wasn't visible while looking at the keyboard, so head-down detection uses a cautious default.")
        }

        let measurable: [PostureIssue: Bool] = [
            .headDown: true,
            .forwardLean: true,
            .lateralTilt: baseline.roll != nil,
            .shoulderAsymmetry: baseline.shoulderSlope != nil,
            .staticPosture: true,
        ]
        if baseline.shoulderSlope == nil {
            notes.append("Shoulders weren't clearly visible, so uneven-shoulder detection is off. That's fine: head position is the main signal.")
        }
        notes.append("All estimates are relative to this position and this camera. They are not measurements of your spine.")

        let quality: CalibrationReport.Quality = (warnings.isEmpty && valid.count >= 12) ? .good : .usable
        let report = CalibrationReport(quality: quality, validSamples: valid.count, totalSamples: samples.count, measurable: measurable, warnings: warnings, notes: notes)
        return .success(Calibration(createdAt: now, cameraID: cameraID, cameraName: cameraName, baseline: baseline, lookDown: lookDownRef, report: report))
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func stdDev(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        return sqrt(xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count))
    }
}
