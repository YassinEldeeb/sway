import SwayCore
import SwiftUI

@MainActor
final class RoutineRunner: ObservableObject {
    let routine: Routine
    @Published private(set) var index = 0
    @Published private(set) var remaining: Double
    @Published var paused = false
    @Published private(set) var finished = false
    private(set) var completedSeconds = 0
    /// Called once, when the last step ends or the player closes.
    var onFinish: ((RoutineRunner) -> Void)?
    private var reported = false
    let started = Date()
    private var timer: Timer?
    private var lastTick = Date()

    init(routine: Routine) {
        self.routine = routine
        remaining = Double(routine.steps.first?.seconds ?? 0)
    }

    var step: RoutineStep { routine.steps[min(index, routine.steps.count - 1)] }

    var completedFraction: Double {
        Double(completedSeconds) / Double(max(1, routine.seconds))
    }

    func start() {
        lastTick = Date()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        let now = Date()
        defer { lastTick = now }
        guard !paused, !finished else { return }
        remaining -= now.timeIntervalSince(lastTick)
        if remaining <= 0 {
            completedSeconds += step.seconds
            next()
        }
    }

    func skip() { next() }

    private func next() {
        if index + 1 < routine.steps.count {
            index += 1
            remaining = Double(step.seconds)
        } else {
            finished = true
            remaining = 0
            stop()
            report()
        }
    }

    func report() {
        guard !reported else { return }
        reported = true
        onFinish?(self)
    }
}

struct RoutinePlayerView: View {
    @EnvironmentObject var model: AppModel
    @State private var chosen: Routine?
    @State private var runner: RoutineRunner?
    @State private var feedbackGiven = false

    init(routine: Routine?) {
        _chosen = State(initialValue: routine)
    }

    var body: some View {
        Group {
            if let runner {
                if runner.finished {
                    FinishedView(runner: runner, feedbackGiven: $feedbackGiven) { helpful in
                        model.routineFeedback(helpful: helpful)
                    }
                } else {
                    PlayerBody(runner: runner)
                }
            } else {
                picker
            }
        }
        .frame(minWidth: 520, minHeight: 580)
        .onAppear { if let chosen { begin(chosen) } }
        .onDisappear { finish() }
    }

    private func begin(_ r: Routine) {
        if r.isAwayBreak {
            model.startGuidedBreak(minutes: Double(r.seconds) / 60)
        }
        let run = RoutineRunner(routine: r)
        let model = self.model
        run.onFinish = { r in
            if !r.routine.isAwayBreak {
                model.routineFinished(r.routine, start: r.started, completedFraction: r.completedFraction)
            }
        }
        runner = run
        run.start()
    }

    private func finish() {
        guard let runner else { return }
        runner.stop()
        runner.report()
        self.runner = nil
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a routine").font(.system(size: 22, weight: .semibold))
                Text("Short, gentle movements. Skip anything that doesn't feel right.")
                    .foregroundStyle(.secondary)
                ForEach(RoutineCategory.allCases, id: \.self) { cat in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(cat.rawValue)
                        ForEach(RoutineLibrary.all.filter { $0.category == cat }) { r in
                            Button { chosen = r; begin(r) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title).font(.system(size: 13, weight: .medium))
                                        Text(r.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(r.durationLabel).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .padding(10)
                                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                SafetyNote()
            }
            .padding(24)
            .padding(.top, 12)
        }
    }
}

private struct PlayerBody: View {
    @ObservedObject var runner: RoutineRunner

    var body: some View {
        let step = runner.step
        VStack(spacing: 16) {
            HStack {
                Text(runner.routine.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(runner.routine.steps.indices, id: \.self) { i in
                        Capsule()
                            .fill(i < runner.index ? Theme.accent : (i == runner.index ? Theme.accent.opacity(0.6) : Color.secondary.opacity(0.25)))
                            .frame(width: i == runner.index ? 16 : 6, height: 6)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: runner.index)
            }
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0, runner.remaining) / Double(step.seconds))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: runner.remaining)
                FigureView(motion: step.motion, paused: runner.paused)
                    .padding(34)
            }
            .frame(width: 260, height: 260)
            VStack(spacing: 6) {
                Text(step.title).font(.system(size: 22, weight: .semibold))
                    .id(step.id)
                    .transition(.opacity)
                HStack(spacing: 8) {
                    Text("\(Int(max(0, runner.remaining.rounded(.up)))) s").monospacedDigit()
                    if let reps = step.reps {
                        Text("·")
                        Text(reps)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                Text(step.instruction)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                if let caution = step.caution {
                    Label(caution, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warm)
                        .frame(maxWidth: 420)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step.id)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(runner.paused ? "Resume" : "Pause") { runner.paused.toggle() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.space, modifiers: [])
                Button("Skip step") { runner.skip() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            SafetyNote()
        }
        .padding(24)
        .padding(.top, 8)
    }
}

private struct FinishedView: View {
    @ObservedObject var runner: RoutineRunner
    @Binding var feedbackGiven: Bool
    var onFeedback: (Bool) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Nice.").font(.system(size: 24, weight: .semibold))
            Text(runner.routine.isAwayBreak ? "Enjoy the break — Sway resets your timers when it sees you were away." : "That counts as a movement break.")
                .foregroundStyle(.secondary)
            if feedbackGiven {
                Text("Thanks — Sway uses this to tune what it suggests.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    Text("Did that help?").font(.system(size: 13, weight: .medium))
                    HStack {
                        Button("Yes, felt better") { onFeedback(true); feedbackGiven = true }.buttonStyle(PillButtonStyle(prominent: true))
                        Button("Not really") { onFeedback(false); feedbackGiven = true }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            Spacer()
            Button("Close") { NSApp.keyWindow?.close() }
                .keyboardShortcut(.defaultAction)
            SafetyNote()
        }
        .padding(24)
    }
}

struct SafetyNote: View {
    var body: some View {
        Text(RoutineLibrary.generalSafety)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
            .fixedSize(horizontal: false, vertical: true)
    }
}
