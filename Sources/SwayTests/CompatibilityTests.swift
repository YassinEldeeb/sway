import Foundation
import SwayCore

// Saved files from the previous version must load without losing data:
// before tolerant decoding, one new field made a whole day unreadable, and
// the next save replaced it with an empty record.

private let oldState = """
{
  "engine" : {
    "answeredInstances" : { "micro@1" : "2026-10-26T09:00:00.000Z" },
    "deliveredInstances" : { "micro@1" : "2026-10-26T09:00:00.000Z" },
    "deliveries" : [ "2026-10-26T09:00:00.000Z" ],
    "lastDeliveredByKind" : { "microBreak" : "2026-10-26T09:00:00.000Z" },
    "negativeStreak" : { "microBreak" : 1 },
    "silencedUntil" : { },
    "snoozes" : { }
  },
  "setupChecklist" : { "chair-height" : "done" },
  "setupMeasurements" : { "viewingDistanceCm" : 80 },
  "tracker" : {
    "lastInputAt" : "2026-10-26T18:21:35.071Z",
    "lastTick" : "2026-10-26T18:21:35.158Z",
    "mode" : { "active" : { } },
    "sessionStart" : "2026-10-26T18:12:24.875Z"
  }
}
"""

private let oldDay = """
{
  "activeSeconds" : 550.5,
  "breaks" : [ ],
  "cameraReliableSeconds" : 60,
  "cameraSeconds" : 60,
  "comfort" : { "neck" : 3, "back" : 5, "eyes" : 2, "at" : "2026-10-25T17:00:00.000Z" },
  "day" : "2026-10-25",
  "log" : [ { "at" : "2026-10-25T18:20:29.123Z", "text" : "Calibrated with FaceTime HD Camera" } ],
  "postureEpisodes" : { "headDown" : 2 },
  "postureSeconds" : { "headDown" : 700 },
  "prompts" : { },
  "routinesCompleted" : 1,
  "stretches" : [ 1200 ]
}
"""

private func storeWith(_ files: [String: String]) throws -> SwayStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sway-compat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("days"), withIntermediateDirectories: true)
    for (name, text) in files { try Data(text.utf8).write(to: dir.appendingPathComponent(name)) }
    return SwayStore(directory: dir)
}

let compatibilityTests: [TestCase] = [
    TestCase(name: "state saved by the previous version keeps its timers and history") {
        let store = try storeWith(["state.json": oldState])
        let r = store.loadRuntime()
        expect(r.tracker.sessionStart != nil, "work timer survives the upgrade")
        expectEqual(r.setupChecklist["chair-height"], "done")
        expectEqual(r.setupMeasurements["viewingDistanceCm"], 80)
        let again = r.engine.decide(candidates: [reminder(.microBreak, "micro@1", at: t0)], now: t0, context: .init(), settings: CoachSettings())
        expect(again.statuses.isEmpty, "an answered reminder stays answered")
        expect(r.decisionLog.entries.isEmpty)
    },
    TestCase(name: "a day saved by the previous version loads in full, including its old comfort score") {
        let store = try storeWith(["days/2026-10-25.json": oldDay])
        let d = store.loadDay("2026-10-25")
        expectEqual(d?.activeSeconds, 550.5)
        expectEqual(d?.postureSeconds[.headDown], 700)
        expectEqual(d?.log.count, 1)
        expectEqual(d?.comfort?.neck, 3)
        expectEqual(d?.comfort?.back, 5, "kept as recorded")
        expectEqual(d?.comfort?.upperBack, nil, "never invented")
        expect(d?.frequentPatterns.isEmpty == true)
    },
    TestCase(name: "one damaged field doesn't lose the rest of the day") {
        let damaged = oldDay.replacingOccurrences(of: "\"routinesCompleted\" : 1", with: "\"routinesCompleted\" : \"one\"")
        let store = try storeWith(["days/2026-10-25.json": damaged])
        let d = store.loadDay("2026-10-25")
        expectEqual(d?.activeSeconds, 550.5)
        expectEqual(d?.routinesCompleted, 0)
    },
    TestCase(name: "an unreadable day is set aside, never overwritten") {
        let store = try storeWith(["days/2026-10-25.json": "{ not json"])
        expect(store.loadDay("2026-10-25") == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.appendingPathComponent("days").path)
        expect(names.contains { $0.hasPrefix("2026-10-25.unreadable-") }, "\(names)")
        expectEqual(store.storedDayCount(), 0)
    },
    TestCase(name: "new fields round-trip") {
        var d = DailyRecord(day: "2026-03-02")
        d.frequentPatterns[.forwardLean] = FrequentFlag(at: t0, share: 0.4, bouts: 6, observedMinutes: 55)
        d.comfort = ComfortCheckIn(neck: 2, lowerBack: 4, at: t0)
        let back = try JSONDecoder().decode(DailyRecord.self, from: JSONEncoder().encode(d))
        expectEqual(back, d)
        var r = RuntimeState()
        r.decisionLog.note("x", kind: .microBreak, at: t0)
        let rBack = try JSONDecoder().decode(RuntimeState.self, from: JSONEncoder().encode(r))
        expectEqual(rBack, r)
    },
]
