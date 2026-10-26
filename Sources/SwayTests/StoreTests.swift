import Foundation
import SwayCore

func tempStore() -> SwayStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sway-tests-\(UUID().uuidString)", isDirectory: true)
    return SwayStore(directory: dir)
}

let storeTests: [TestCase] = [
    TestCase(name: "settings round trip, with sanitizing") {
        let store = tempStore()
        defer { try? store.deleteAll() }
        var s = CoachSettings()
        s.microBreakInterval = 30 * 60
        s.eyeRestEnabled = true
        s.headDown.enter = 0.7
        try store.save(s)
        expectEqual(store.loadSettings(), s.sanitized())
        expectEqual(store.loadSettings().microBreakInterval, 30 * 60)
        var bad = CoachSettings()
        bad.microBreakInterval = 5
        bad.maxNotificationsPerHour = 999
        bad.lateralTilt.exit = 50
        let clean = bad.sanitized()
        expectEqual(clean.microBreakInterval, 5 * 60)
        expectEqual(clean.maxNotificationsPerHour, 12)
        expect(clean.lateralTilt.exit <= clean.lateralTilt.enter, "exit stays inside the hysteresis band")
    },
    TestCase(name: "an older settings file keeps defaults for missing keys") {
        let json = #"{"microBreakInterval": 1800, "cameraMonitoringEnabled": true}"#
        let s = try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))
        expectEqual(s.microBreakInterval, 1800)
        expectEqual(s.cameraMonitoringEnabled, true)
        expectEqual(s.longBreakInterval, CoachSettings().longBreakInterval)
        let garbage = try? JSONDecoder().decode(CoachSettings.self, from: Data(#"{"microBreakInterval": "soon"}"#.utf8))
        expectEqual(garbage?.microBreakInterval, CoachSettings().microBreakInterval)
    },
    TestCase(name: "calibration persists and can be removed") {
        let store = tempStore()
        defer { try? store.deleteAll() }
        var s = Synth()
        let c = calibrated(&s, lookDown: true)
        try store.save(c)
        expectEqual(store.loadCalibration(), c)
        try store.save(nil as Calibration?)
        expect(store.loadCalibration() == nil)
    },
    TestCase(name: "runtime state survives a restart") {
        let store = tempStore()
        defer { try? store.deleteAll() }
        var sim = Sim()
        sim.work(30 * 60)
        var state = RuntimeState()
        state.tracker = sim.tracker
        state.engine.recordDelivered(reminder(.microBreak, "x", at: sim.now), at: sim.now)
        state.pausedUntil = sim.now + 600
        try store.save(state)
        let back = store.loadRuntime()
        expectEqual(back, state)
    },
    TestCase(name: "ledger accounting: retraction never goes negative, logs are bounded") {
        var ledger = Ledger()
        ledger.apply([.retractActive(from: t0, to: t0 + 100)], calendar: utc)
        expectEqual(ledger.records["2026-03-02"]?.activeSeconds, 0)
        for i in 0..<(DailyRecord.maxLog + 50) {
            ledger.prompted(.microBreak, at: t0 + Double(i), calendar: utc)
        }
        let r = ledger.records["2026-03-02"]!
        expectEqual(r.log.count, DailyRecord.maxLog)
        expectEqual(r.prompts[.microBreak]?.prompts, DailyRecord.maxLog + 50)
        ledger.apply(PostureEpisode(issue: .headDown, start: t0, end: t0 + 400, peak: 1), calendar: utc)
        expectEqual(ledger.records["2026-03-02"]?.postureSeconds[.headDown], 400)
        expectEqual(ledger.records["2026-03-02"]?.postureEpisodes[.headDown], 1)
    },
    TestCase(name: "daily records persist, prune by retention, and delete completely") {
        let store = tempStore()
        for offset in [0, 10, 100, 200] {
            var r = DailyRecord(day: DayKey.key(t0 - Double(offset) * 86_400))
            r.activeSeconds = Double(offset)
            r.comfort = ComfortCheckIn(neck: 12, back: -1, eyes: 4, at: t0)
            try store.save(r)
        }
        let today = store.loadDay(DayKey.key(t0))
        expectEqual(today?.comfort?.neck, 10, "clamped to 0-10")
        expectEqual(today?.comfort?.back, 0)
        expectEqual(store.storedDayCount(), 4)
        let removed = store.prune(retentionDays: 90, now: t0)
        expectEqual(removed, 2)
        expectEqual(store.storedDayCount(), 2)
        let recent = store.recent(days: 14, now: t0)
        expectEqual(recent.count, 14)
        expectEqual(recent.last?.day, DayKey.key(t0))
        try store.save(CoachSettings())
        try store.deleteAll()
        expect(!FileManager.default.fileExists(atPath: store.directory.path), "everything removed")
        expectEqual(store.storedDayCount(), 0)
    },
    TestCase(name: "stored files hold derived numbers only") {
        let store = tempStore()
        defer { try? store.deleteAll() }
        var sim = Sim()
        sim.work(20 * 60)
        sim.idle(4 * 60)
        sim.work(5 * 60)
        for (_, r) in sim.ledger.records { try store.save(r) }
        let data = try Data(contentsOf: store.directory.appendingPathComponent("days/\(DayKey.key(t0)).json"))
        let text = String(decoding: data, as: UTF8.self)
        expect(text.contains("activeSeconds"))
        expect(data.count < 10_000, "small: \(data.count) bytes")
    },
    TestCase(name: "workstation advice uses only what the user entered") {
        expect(WorkstationGuide.advice(viewingDistanceCm: nil, screenTop: nil, usesLaptopScreenOnly: nil).isEmpty)
        let a = WorkstationGuide.advice(viewingDistanceCm: 35, screenTop: .wellBelow, usesLaptopScreenOnly: true)
        expectEqual(a.count, 3)
        expect(a[0].contains("35 cm"))
    },
    TestCase(name: "routine library is complete and safe to present") {
        let all = RoutineLibrary.all
        expect(all.contains { $0.seconds <= 30 }, "30-second routines")
        expect(all.contains { $0.seconds == 60 }, "1-minute routines")
        expect(all.contains { $0.seconds == 180 }, "3-minute routines")
        expect(all.contains { $0.seconds > 180 }, "longer routine")
        for c in RoutineCategory.allCases { expect(all.contains { $0.category == c }, "category \(c)") }
        for r in all { for s in r.steps { expect(!s.instruction.isEmpty && s.seconds > 0) } }
        expectEqual(Set(all.map(\.id)).count, all.count)
        for k in ReminderKind.allCases { _ = RoutineLibrary.suggested(for: k) }
    },
    TestCase(name: "an answer saved for the old keyboard-and-mouse item carries over to both new items") {
        let old = ["keyboard-mouse": "done", "monitor-height": "todo"]
        expectEqual(WorkstationGuide.answer(for: "keyboard", in: old), "done")
        expectEqual(WorkstationGuide.answer(for: "mouse", in: old), "done")
        expectEqual(WorkstationGuide.answer(for: "monitor-height", in: old), "todo")
        // A new answer wins over the old one.
        expectEqual(WorkstationGuide.answer(for: "mouse", in: old.merging(["mouse": "na"]) { $1 }), "na")
        // Migration copies the old answer and drops the old id, so clearing
        // a new item afterwards doesn't fall back to it.
        var m = WorkstationGuide.migrated(old)
        expectEqual(m, ["keyboard": "done", "mouse": "done", "monitor-height": "todo"])
        m["keyboard"] = nil
        expectEqual(WorkstationGuide.answer(for: "keyboard", in: m), nil)
        expectEqual(WorkstationGuide.migrated(["mouse": "na", "keyboard-mouse": "done"]), ["mouse": "na", "keyboard": "done"])
        expectEqual(WorkstationGuide.migrated(["chair-height": "done"]), ["chair-height": "done"])
    },
    TestCase(name: "every setup item has a diagram-ready id, and outside ids resolve") {
        let ids = WorkstationGuide.items.map(\.id)
        expectEqual(Set(ids).count, ids.count)
        expectEqual(ids, ["monitor-height", "viewing-distance", "screen-angle", "external-monitor", "chair-height", "foot-support",
                          "desk-height", "keyboard", "mouse", "forearm-support", "neck-shoulders", "variation"])
        // Ids that posture reminders point to stay valid.
        for id in ["monitor-height", "viewing-distance", "external-monitor", "forearm-support", "variation"] {
            expectEqual(WorkstationGuide.item(id)?.id, id)
        }
        expectEqual(WorkstationGuide.item("keyboard-mouse")?.id, "keyboard")
        expect(WorkstationGuide.item("nonsense") == nil && WorkstationGuide.item(nil) == nil)
        // Approximate guidance reads as approximate.
        for item in WorkstationGuide.items where item.guidance.contains("°") || item.guidance.contains("cm") {
            let g = item.guidance.lowercased()
            expect(g.contains("about") || g.contains("roughly") || g.contains("around") || g.contains("often"), "\(item.id) hedges its numbers")
        }
    },
]
