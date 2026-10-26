import SwayCore
import SwiftUI

struct SetupAssistantView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected = WorkstationGuide.items.first!.id

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                Section {
                    CalibrationStatusRow()
                }
                ForEach(areas, id: \.self) { area in
                    Section(area) {
                        ForEach(WorkstationGuide.items.filter { $0.area == area }) { item in
                            HStack {
                                Image(systemName: item.symbol).frame(width: 18).foregroundStyle(Theme.accent)
                                Text(item.title)
                                Spacer()
                                statusIcon(model.runtime.setupChecklist[item.id])
                            }
                            .tag(item.id)
                        }
                    }
                }
                Section("Your measurements") {
                    Text("Measurements").tag("measure")
                }
            }
            .listStyle(.sidebar)
            .frame(width: 250)
            Divider()
            ScrollView {
                Group {
                    if selected == "measure" {
                        MeasurementsPane()
                    } else if let item = WorkstationGuide.items.first(where: { $0.id == selected }) {
                        ItemPane(item: item, next: next(after: item))
                    }
                }
                .padding(28)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 600)
    }

    private var areas: [String] {
        var seen: [String] = []
        for i in WorkstationGuide.items where !seen.contains(i.area) { seen.append(i.area) }
        return seen
    }

    private func next(after item: GuideItem) -> (() -> Void)? {
        let all = WorkstationGuide.items
        guard let i = all.firstIndex(where: { $0.id == item.id }) else { return nil }
        if i + 1 < all.count { return { selected = all[i + 1].id } }
        return { selected = "measure" }
    }

    @ViewBuilder private func statusIcon(_ s: String?) -> some View {
        switch s {
        case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case "todo": Image(systemName: "circle.dotted").foregroundStyle(Theme.warm)
        case "na": Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        default: EmptyView()
        }
    }
}

private struct CalibrationStatusRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let done = WorkstationGuide.items.filter { model.runtime.setupChecklist[$0.id] == "done" || model.runtime.setupChecklist[$0.id] == "na" }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Checklist").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(done)/\(WorkstationGuide.items.count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(done), total: Double(WorkstationGuide.items.count)).tint(Theme.accent)
            HStack(spacing: 5) {
                StatusDot(color: model.calibration == nil ? .secondary : (model.posture.status == .needsRecalibration ? Theme.warm : .green))
                Text(model.calibration == nil ? "Posture not calibrated" : (model.posture.status == .needsRecalibration ? "Recalibration needed" : "Posture calibrated \(model.calibration!.createdAt.formatted(.relative(presentation: .named)))"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ItemPane: View {
    @EnvironmentObject var model: AppModel
    var item: GuideItem
    var next: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).font(.system(size: 26)).foregroundStyle(Theme.accent)
                Text(item.title).font(.system(size: 22, weight: .semibold))
                Spacer()
                EvidenceTag(level: item.evidence)
            }
            Text(item.guidance).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            if item.id == "monitor-height" { MonitorDiagram().frame(height: 170) }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Quick check")
                    Text(item.check).font(.system(size: 13, weight: .medium))
                    HStack {
                        choice("Yes, it's set", "done")
                        choice("Not yet", "todo")
                        choice("Doesn't apply", "na")
                    }
                }
            }
            if item.id == "monitor-height" || item.id == "viewing-distance" {
                Text("Sway can't measure your screen height or distance from the camera image. Use the Measurements page to enter what you measure.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let next {
                HStack { Spacer(); Button("Next", action: next).keyboardShortcut(.defaultAction) }
            }
        }
    }

    private func choice(_ label: String, _ value: String) -> some View {
        let on = model.runtime.setupChecklist[item.id] == value
        return Button(label) { model.setChecklist(item.id, on ? nil : value) }
            .buttonStyle(PillButtonStyle(prominent: on))
    }
}

/// Side view: eye line, the top of the screen at or slightly below it, and
/// the comfortable downward gaze to the screen's centre.
private struct MonitorDiagram: View {
    var body: some View {
        Canvas { ctx, size in
            let ink = Theme.accent
            let eye = CGPoint(x: 70, y: 60)
            let headRect = CGRect(x: 40, y: 34, width: 52, height: 56)
            ctx.stroke(Path(ellipseIn: headRect), with: .color(ink), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: eye.x + 10, y: eye.y - 3, width: 6, height: 6)), with: .color(ink))
            // Eye line
            var eyeLine = Path()
            eyeLine.move(to: CGPoint(x: eye.x + 16, y: eye.y))
            eyeLine.addLine(to: CGPoint(x: size.width - 40, y: eye.y))
            ctx.stroke(eyeLine, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ctx.draw(Text("eye level").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: size.width - 70, y: eye.y - 10))
            // Monitor, tilted slightly back, top at eye level.
            let mx = size.width - 120
            var screen = Path()
            screen.move(to: CGPoint(x: mx, y: eye.y + 2))
            screen.addLine(to: CGPoint(x: mx + 14, y: eye.y + 82))
            ctx.stroke(screen, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            var stand = Path()
            stand.move(to: CGPoint(x: mx + 10, y: eye.y + 62))
            stand.addLine(to: CGPoint(x: mx + 30, y: eye.y + 100))
            stand.move(to: CGPoint(x: mx + 10, y: eye.y + 100))
            stand.addLine(to: CGPoint(x: mx + 50, y: eye.y + 100))
            ctx.stroke(stand, with: .color(.secondary), lineWidth: 3)
            // Gaze to the centre, ~15–20° down.
            var gaze = Path()
            gaze.move(to: CGPoint(x: eye.x + 16, y: eye.y))
            gaze.addLine(to: CGPoint(x: mx + 7, y: eye.y + 42))
            ctx.stroke(gaze, with: .color(Theme.warm), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            ctx.draw(Text("≈15–20° down to the centre").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.warm), at: CGPoint(x: (eye.x + mx) / 2 + 10, y: eye.y + 36))
            ctx.draw(Text("about an arm's length").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: (eye.x + mx) / 2 + 10, y: eye.y + 96))
        }
    }
}

private struct MeasurementsPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let m = model.runtime.setupMeasurements
        let distance = Binding<String>(
            get: { m["viewingDistanceCm"].map { String(Int($0)) } ?? "" },
            set: { model.setMeasurement("viewingDistanceCm", Double($0.filter(\.isNumber)).map { min(max($0, 10), 300) }) })
        let top = Binding<ScreenTopPosition?>(
            get: { m["screenTop"].flatMap { ScreenTopPosition.allCases.indices.contains(Int($0)) ? ScreenTopPosition.allCases[Int($0)] : nil } },
            set: { model.setMeasurement("screenTop", $0.flatMap { ScreenTopPosition.allCases.firstIndex(of: $0) }.map(Double.init)) })
        let laptop = Binding<Bool>(
            get: { (m["laptopOnly"] ?? 0) == 1 },
            set: { model.setMeasurement("laptopOnly", $0 ? 1 : 0) })
        let advice = WorkstationGuide.advice(viewingDistanceCm: m["viewingDistanceCm"], screenTop: top.wrappedValue, usesLaptopScreenOnly: m["laptopOnly"].map { $0 == 1 })

        return VStack(alignment: .leading, spacing: 16) {
            Text("Your measurements").font(.system(size: 22, weight: .semibold))
            Text("Measure from your eyes to the screen with a tape measure, sitting as you work. Sway only uses what you enter here — it doesn't estimate these from the camera.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Eyes to screen (cm)", text: distance)
                Picker("Top of the screen is", selection: top) {
                    Text("Not measured").tag(Optional<ScreenTopPosition>.none)
                    ForEach(ScreenTopPosition.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Toggle("I mostly use a laptop's own screen and keyboard", isOn: laptop)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 480)
            if !advice.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Suggestions")
                        ForEach(advice, id: \.self) { Label($0, systemImage: "lightbulb").font(.system(size: 12)) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Sources")
                ForEach(WorkstationGuide.sources, id: \.self) { Text("• " + $0).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }
}
