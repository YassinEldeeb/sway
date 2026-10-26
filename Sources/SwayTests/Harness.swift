import Foundation

// A small test harness: the Command Line Tools on this machine ship no
// XCTest or swift-testing, so tests run as a plain executable
// (`swift run sway-tests`). Exit code is non-zero on any failure.

final class TestRun {
    static var current = TestRun()
    var failures: [String] = []
    var checks = 0
}

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    TestRun.current.checks += 1
    if !condition() {
        TestRun.current.failures.append("\(file):\(line) \(message())")
    }
}

func expectEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    let x = a(), y = b()
    TestRun.current.checks += 1
    if x != y {
        TestRun.current.failures.append("\(file):\(line) expected \(y), got \(x) \(message())")
    }
}

func expectClose(_ a: Double, _ b: Double, tolerance: Double, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    TestRun.current.checks += 1
    if abs(a - b) > tolerance {
        TestRun.current.failures.append("\(file):\(line) expected \(b) ± \(tolerance), got \(a) \(message())")
    }
}

struct TestCase {
    let name: String
    let body: () throws -> Void
}

func runAll(_ suites: [(String, [TestCase])]) -> Int32 {
    // Optional: only tests whose "suite / name" contains this text.
    let filter = CommandLine.arguments.dropFirst().first
    var passed = 0, failed = 0, checks = 0
    let started = Date()
    for (suite, cases) in suites {
        for c in cases {
            let full = "\(suite) / \(c.name)"
            if let filter, !full.localizedCaseInsensitiveContains(filter) { continue }
            TestRun.current = TestRun()
            do {
                try c.body()
            } catch {
                TestRun.current.failures.append("threw \(error)")
            }
            checks += TestRun.current.checks
            if TestRun.current.failures.isEmpty {
                passed += 1
                print("  ✓ \(full)")
            } else {
                failed += 1
                print("  ✗ \(full)")
                for f in TestRun.current.failures { print("      \(f)") }
            }
        }
    }
    let ms = Int(Date().timeIntervalSince(started) * 1000)
    if let filter, passed + failed == 0 {
        // A filter that matches nothing is a mistake (e.g. a "# comment" an
        // interactive zsh passed as arguments), never a green run.
        print("No test name contains \"\(filter)\". Run with no arguments for all tests, or pass part of a test name.")
        return 2
    }
    print("\n\(passed) passed, \(failed) failed, \(checks) checks, \(ms) ms")
    return failed == 0 ? 0 : 1
}
