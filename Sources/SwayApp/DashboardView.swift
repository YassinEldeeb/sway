import Charts
import SwayCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab

    init(tab: Tab = .today) {
        _tab = State(initialValue: tab)
    }

    enum Tab: String, CaseIterable { case today = "Today", trends = "Trends", insights = "Insights" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sway").font(.system(size: 20, weight: .semibold))
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .labelsHidden()
                Spacer()
                Button { WindowManager.shared.show(.settings) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 12)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .today: TodayView()
                    case .trends: TrendsView()
                    case .insights: InsightsView()
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

// MARK: Today

private struct TodayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let r = model.today
        VStack(alignment: .leading, spacing: 18) {
            StatusStrip()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                Metric(title: "Active time", value: Format.duration(r.activeSeconds), detail: "Time with keyboard/mouse activity, counting pauses under \(Int(model.settings.awayThreshold / 60)) min.")
                Metric(title: "Longest stretch", value: Format.duration(model.longestStretchToday), detail: "Longest time between breaks of \(Int(model.settings.microBreakMinAway / 60)) min or more (includes the stretch in progress).")
                Metric(title: "Breaks", value: "\(r.meaningfulBreaks)", detail: "Times you stepped away \(Int(model.settings.microBreakMinAway / 60))+ min, plus completed routines and guided breaks.")
                Metric(title: "Typical stretch", value: r.medianStretch.map { Format.duration($0) } ?? "—", detail: "Median time between breaks today.")
                Metric(title: "Camera monitoring", value: Format.duration(r.cameraSeconds), detail: "Time the camera was on. \(Format.duration(r.cameraReliableSeconds)) of it had reliable tracking.")
                Metric(title: "Sustained deviations", value: Format.duration(r.totalPostureSeconds), detail: "Total time in a detected sustained posture deviation. Experimental camera estimate.")
                Metric(title: "Routines", value: "\(r.routinesCompleted)", detail: "Guided movement routines completed.")
                Metric(title: "Reminders", value: "\(r.prompts.values.reduce(0) { $0 + $1.prompts })", detail: "Notifications sent today (menu-bar-only hints are not counted).")
            }
            HStack(alignment: .top, spacing: 12) {
                PostureBreakdown(record: r)
                if model.settings.comfortCheckInEnabled { ComfortCheckInView() }
            }
            if !r.prompts.isEmpty {
                PromptsBreakdown(record: r)
            }
            if !r.log.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Timeline")
                        ForEach(Array(r.log.suffix(12).reversed().enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .firstTextBaseline) {
                                Text(e.at, style: .time).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                                Text(e.text).font(.system(size: 12))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct StatusStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            HStack(spacing: 22) {
                item("Coaching", model.isPaused ? "Paused" : (model.tracker.isActive ? "Active" : "Away"), model.isPaused ? .secondary : (model.tracker.isActive ? .green : .secondary))
                item("Working for", Format.duration(model.continuousWork), .primary)
                if let n = model.nextBreak, model.attention == nil {
                    item("Next break", Format.duration(max(0, n.at.timeIntervalSince(model.now)) + 59), .primary)
                } else if let a = model.attention {
                    item("Needs attention", a.kind.title, Theme.warm)
                }
                item("Posture", model.settings.cameraMonitoringEnabled ? model.posture.status.label : "Off", model.settings.cameraMonitoringEnabled ? model.posture.status.color : .secondary)
                Spacer()
                Button("Start a routine") { WindowManager.shared.showRoutine(nil) }.buttonStyle(PillButtonStyle(prominent: true))
            }
        }
    }

    private func item(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(color).monospacedDigit()
        }
    }
}

struct Metric: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                    Image(systemName: "info.circle").font(.system(size: 9)).foregroundStyle(.tertiary).help(detail)
                }
                Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .help(detail)
    }
}

private struct PostureBreakdown: View {
    @EnvironmentObject var model: AppModel
    var record: DailyRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Sustained posture deviations")
                    Spacer()
                    EvidenceTag(level: .experimental)
                }
                if !model.settings.cameraMonitoringEnabled && record.cameraSeconds == 0 {
                    Text("Camera monitoring is off. Breaks and activity work without it.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Set up posture monitoring") { WindowManager.shared.show(.calibration) }.buttonStyle(PillButtonStyle())
                } else {
                    let rows = PostureIssue.allCases.map { issue -> (PostureIssue, Double, Int) in
                        // Finished episodes are saved when they end; add the
                        // one happening now so it shows while it lasts.
                        var secs = record.postureSeconds[issue] ?? 0
                        var count = record.postureEpisodes[issue] ?? 0
                        if let a = live.active.first(where: { $0.issue == issue }) {
                            secs += max(0, Date().timeIntervalSince(a.since))
                            count += 1
                        }
                        return (issue, secs, count)
                    }
                    let maxV = max(rows.map(\.1).max() ?? 0, 60)
                    ForEach(rows, id: \.0) { issue, secs, count in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(issue.title).font(.system(size: 12))
                                    .help(issue.definition)
                                Spacer()
                                Text(value(issue, secs, count)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            GeometryReader { g in
                                Capsule().fill(Color.secondary.opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Theme.warm.opacity(0.75)).frame(width: g.size.width * secs / maxV)
                                    }
                            }
                            .frame(height: 5)
                        }
                    }
                    Text("Camera-relative estimates against your calibration — not spinal measurements. A position counts once it has lasted the time set in Settings → Posture.")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Live state applies only to today's record.
    private var live: (active: [ActiveIssue], building: [BuildingIssue]) {
        guard record.day == DayKey.key(Date()) else { return ([], []) }
        return (model.activeIssues, model.buildingIssues)
    }

    private func value(_ issue: PostureIssue, _ secs: Double, _ count: Int) -> String {
        let now = live.active.contains { $0.issue == issue } ? " · now" : ""
        if secs > 0 { return "\(Format.duration(secs)) · \(count)×\(now)" }
        if let b = live.building.first(where: { $0.issue == issue }) {
            let n = Int(b.remaining(at: Date()).rounded(.up))
            return "now · counts in \(n / 60):\(String(format: "%02d", n % 60))"
        }
        return "—"
    }
}

private struct PromptsBreakdown: View {
    var record: DailyRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Most frequent prompts")
                ForEach(record.prompts.sorted { $0.value.prompts > $1.value.prompts }.prefix(5), id: \.key) { kind, c in
                    HStack {
                        Text(kind.title).font(.system(size: 12))
                        Spacer()
                        Text("\(c.prompts) sent · \(c.accepted) acted on · \(c.snoozed) snoozed · \(c.dismissed + c.unhelpful) dismissed")
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

struct ComfortCheckInView: View {
    @EnvironmentObject var model: AppModel
    /// nil = not answered (the area doesn't apply or the user skipped it).
    @State private var values: [ComfortCheckIn.Area: Double] = [:]
    @State private var note = ""
    @State private var editing = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Comfort check-in")
                    Spacer()
                    Text("Optional").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                if let c = model.today.comfort, !editing {
                    HStack(spacing: 16) {
                        ForEach(ComfortCheckIn.Area.allCases, id: \.self) { area in
                            score(area.title, c[area])
                        }
                        if c.back != nil, c.upperBack == nil, c.lowerBack == nil { score("Back", c.back) }
                    }
                    if let n = c.note { Text(n).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Button("Update") {
                        values = Dictionary(uniqueKeysWithValues: ComfortCheckIn.Area.allCases.compactMap { a in c[a].map { (a, Double($0)) } })
                        note = c.note ?? ""
                        editing = true
                    }
                    .buttonStyle(PillButtonStyle())
                } else {
                    Text("How uncomfortable is each area right now? 0 = none, 10 = worst imaginable. Answer only what applies.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(ComfortCheckIn.Area.allCases, id: \.self) { area in row(area) }
                    TextField("Note (optional)", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    HStack {
                        Button("Save") {
                            let v = { (a: ComfortCheckIn.Area) in values[a].map { Int($0) } }
                            model.saveComfort(ComfortCheckIn(neck: v(.neck), upperBack: v(.upperBack), lowerBack: v(.lowerBack), eyes: v(.eyes),
                                                             note: note.isEmpty ? nil : note, at: Date()))
                            editing = false
                        }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(values.isEmpty && note.isEmpty)
                        if editing { Button("Cancel") { editing = false }.buttonStyle(PillButtonStyle()) }
                    }
                    if values.values.contains(where: { $0 >= 7 }) {
                        Text("For persistent, severe or worsening pain, please see a qualified clinician — Sway can't assess it.")
                            .font(.system(size: 11)).foregroundStyle(Theme.warm)
                    }
                }
            }
        }
    }

    private func score(_ label: String, _ v: Int?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v.map { "\($0)/10" } ?? "—").font(.system(size: 18, weight: .semibold, design: .rounded))
        }
    }

    private func row(_ area: ComfortCheckIn.Area) -> some View {
        let answered = values[area] != nil
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(area.title).font(.system(size: 12))
                Spacer()
                if answered {
                    Text("\(Int(values[area] ?? 0))").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Button("Clear") { values[area] = nil }.buttonStyle(.link).font(.system(size: 11))
                } else {
                    Text("Not answered").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Slider(value: Binding(get: { values[area] ?? 0 }, set: { values[area] = $0 }), in: 0...10, step: 1)
                .tint(answered ? Theme.accent : Color.secondary.opacity(0.4))
        }
    }
}

// MARK: Trends

private struct TrendsView: View {
    @EnvironmentObject var model: AppModel
    @State private var days = 14

    var body: some View {
        let history = model.history(days: days)
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $days) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()

            chartCard("Active time (bars) and longest stretch (dots), hours") {
                Chart(history, id: \.day) { d in
                    BarMark(x: .value("Day", date(d.day), unit: .day), y: .value("Active", d.activeSeconds / 3600))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                    PointMark(x: .value("Day", date(d.day), unit: .day), y: .value("Longest", d.longestStretch / 3600))
                        .foregroundStyle(Theme.warm)
                }
                .chartXAxis { dayAxis }
            }
            HStack(spacing: 12) {
                chartCard("Breaks per day") {
                    Chart(history, id: \.day) { d in
                        BarMark(x: .value("Day", date(d.day), unit: .day), y: .value("Breaks", d.meaningfulBreaks))
                            .foregroundStyle(Theme.accent.opacity(0.7))
                    }
                    .chartXAxis { dayAxis }
                }
                chartCard("Sustained posture deviation (min)") {
                    Chart(history, id: \.day) { d in
                        ForEach(PostureIssue.allCases, id: \.self) { issue in
                            BarMark(x: .value("Day", date(d.day), unit: .day), y: .value("Minutes", (d.postureSeconds[issue] ?? 0) / 60))
                                .foregroundStyle(by: .value("Issue", issue.title))
                        }
                    }
                    .chartForegroundStyleScale(domain: PostureIssue.allCases.map(\.title), range: [Theme.warm, Theme.accent, Color.blue.opacity(0.7), Color.purple.opacity(0.6), Color.gray.opacity(0.55)])
                    .chartXAxis { dayAxis }
                    .chartLegend(position: .bottom)
                }
            }
            chartCard("Comfort check-ins (0–10, lower is better) · dashed lines mark workstation changes") {
                let points = history.compactMap { d in d.comfort.map { (d.day, $0) } }
                let changes = history.filter { d in d.log.contains { Self.isWorkstationChange($0.text) } }.map(\.day)
                if points.isEmpty {
                    Text("No check-ins yet. Add one from the Today tab — a few a week is enough to see whether things change.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart {
                        ForEach(changes, id: \.self) { day in
                            RuleMark(x: .value("Day", date(day), unit: .day))
                                .foregroundStyle(Color.secondary.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        ForEach(Self.comfortSeries, id: \.0) { name, value in
                            ForEach(points.filter { value($0.1) != nil }, id: \.0) { day, c in
                                LineMark(x: .value("Day", date(day), unit: .day), y: .value("Score", value(c) ?? 0), series: .value("Area", name))
                                    .foregroundStyle(by: .value("Area", name)).symbol(.circle)
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: Self.comfortSeries.map(\.0), range: [Theme.warm, Theme.accent, Color.purple.opacity(0.65), Color.blue.opacity(0.7), Color.gray.opacity(0.6)])
                    .chartXScale(domain: date(history.first?.day ?? "")...date(history.last?.day ?? ""))
                    .chartXAxis { dayAxis }
                    .chartYScale(domain: 0...10)
                    .chartLegend(position: .bottom)
                }
            }
            Text("Trends show what Sway observed and what you reported. They can suggest whether changes help you, but they can't show cause and effect.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    /// Areas over time; "Back" holds check-ins from before the split.
    static let comfortSeries: [(String, (ComfortCheckIn) -> Int?)] = [
        ("Neck", { $0.neck }), ("Upper back", { $0.upperBack }), ("Lower back", { $0.lowerBack }), ("Eye fatigue", { $0.eyes }), ("Back", { $0.back }),
    ]

    static func isWorkstationChange(_ text: String) -> Bool {
        text.hasPrefix("Workstation:") || text.hasPrefix("Calibrated")
    }

    private func date(_ day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }

    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: days > 14 ? 7 : (days > 7 ? 3 : 1))) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
        }
    }

    private func chartCard<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title)
                content().frame(height: 170)
            }
        }
    }
}

// MARK: Insights

private struct InsightsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let history = model.history(days: 14)
        var totals: [ReminderKind: ResponseCounts] = [:]
        for d in history { for (k, c) in d.prompts { totals[k, default: ResponseCounts()] = totals[k, default: ResponseCounts()] + c } }
        return VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("What Sway has adapted")
                    if model.adjustments.explanations.isEmpty {
                        Text("Nothing yet. Sway starts with your settings and only adapts after several reminders of the same kind, based on whether you act on them, snooze them, or mark them not helpful.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        ForEach(model.adjustments.explanations, id: \.self) { e in
                            Label(e, systemImage: "slider.horizontal.3").font(.system(size: 12))
                        }
                    }
                    Text("Adaptation can only make Sway quieter or less sensitive — never more insistent than your settings.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            if !model.patternIssues.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Recurring patterns")
                        ForEach(Array(model.patternIssues).sorted { $0.rawValue < $1.rawValue }, id: \.self) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title).font(.system(size: 13, weight: .medium))
                                if let f = model.today.frequentPatterns[issue] {
                                    Text("Came up often in short bouts today: about \(Int((f.share * 100).rounded()))% of \(Int(f.observedMinutes.rounded())) min the camera could see you, in \(f.bouts) separate bouts.")
                                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                                } else {
                                    Text("Counted as a sustained position several times recently.")
                                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                                Text(PatternDetector.advice(for: issue)).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        Button("Open workstation setup") { WindowManager.shared.show(.setup) }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Last 14 days: how reminders landed")
                    if totals.isEmpty {
                        Text("No reminders yet.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(totals.sorted { $0.value.prompts > $1.value.prompts }, id: \.key) { k, c in
                        HStack {
                            Text(k.title).font(.system(size: 12))
                            Spacer()
                            Text("\(c.prompts) sent · \(c.accepted) acted on · \(c.helpful) helped · \(c.unhelpful) not helpful · \(c.snoozed) snoozed")
                                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Comfort over time")
                    let checks = history.compactMap(\.comfort)
                    if checks.count < 3 {
                        Text("Record a comfort check-in on a few days to compare. Sway treats comfort as the outcome that matters; camera estimates can't measure it.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        let half = checks.count / 2
                        let early = Array(checks.prefix(half)), late = Array(checks.suffix(checks.count - half))
                        ForEach(ComfortCheckIn.Area.allCases, id: \.self) { area in
                            let e = early.compactMap { $0[area] }, l = late.compactMap { $0[area] }
                            if !e.isEmpty, !l.isEmpty {
                                Text(String(format: "%@: %.1f → %.1f", area.title, Double(e.reduce(0, +)) / Double(e.count), Double(l.reduce(0, +)) / Double(l.count)))
                                    .font(.system(size: 12)).monospacedDigit()
                            }
                        }
                        Text("Earlier vs. recent check-ins in this period, next to the active time, breaks and workstation changes in Trends.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("Many things affect comfort; use this as a prompt for reflection, not proof.").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
