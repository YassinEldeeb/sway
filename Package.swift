// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sway",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sway", targets: ["SwayApp"]),
        .executable(name: "sway-tests", targets: ["SwayTests"]),
        .library(name: "SwayCore", targets: ["SwayCore"]),
    ],
    targets: [
        // Pure, deterministic logic: activity, breaks, notification policy,
        // posture signal processing, calibration, persistence. No AppKit.
        .target(name: "SwayCore"),
        // The menu-bar app: SwiftUI + AppKit + AVFoundation + Vision.
        .executableTarget(name: "SwayApp", dependencies: ["SwayCore"]),
        // Self-contained test runner (the Command Line Tools ship no XCTest).
        .executableTarget(name: "SwayTests", dependencies: ["SwayCore"]),
    ]
)
