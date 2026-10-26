import SwayCore
import SwiftUI

struct SetupAssistantView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: String

    /// `initialItem` opens a specific item, e.g. the one a workstation
    /// suggestion ("Head down keeps coming back") points to.
    init(initialItem: String? = nil) {
        _selected = State(initialValue: WorkstationGuide.item(initialItem)?.id ?? WorkstationGuide.items.first!.id)
    }

    var body: some View {
        content
            // A workstation suggestion opens its item even when the
            // window is already open on another one.
            .onReceive(model.$setupFocus.compactMap { $0 }) { focus in
                if let item = WorkstationGuide.item(focus) { selected = item.id }
            }
    }

    private var content: some View {
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
                                statusIcon(WorkstationGuide.answer(for: item.id, in: model.runtime.setupChecklist))
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
                            .id(item.id)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: selected)
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
        let done = WorkstationGuide.items.filter {
            let a = WorkstationGuide.answer(for: $0.id, in: model.runtime.setupChecklist)
            return a == "done" || a == "na"
        }.count
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
            SetupIllustration(itemID: item.id)
            Text(item.guidance).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
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
        let on = WorkstationGuide.answer(for: item.id, in: model.runtime.setupChecklist) == value
        return Button(label) {
            // Copy an answer saved under a replaced item onto the new items
            // first, so clearing this one doesn't fall back to it.
            let current = model.runtime.setupChecklist
            let migrated = WorkstationGuide.migrated(current)
            for id in Set(current.keys).union(migrated.keys) where current[id] != migrated[id] {
                model.setChecklist(id, migrated[id])
            }
            model.setChecklist(item.id, on ? nil : value)
        }
        .buttonStyle(PillButtonStyle(prominent: on))
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
