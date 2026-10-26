import Foundation

/// Which animation the routine player draws for a step.
public enum Motion: String, Codable, Sendable {
    case chinTuck, neckTilt, neckTurn
    case shoulderRoll, shoulderShrug, bladeSqueeze
    case overheadReach, chestOpener, backExtension, seatedTwist
    case wristCircles, wristFlex, fingerSpread
    case lookFar, blink, palming
    case standUp, calfRaise, march, walk
    case breathe
}

public struct RoutineStep: Equatable, Sendable, Identifiable {
    public var id: String { title + String(seconds) }
    public var title: String
    public var instruction: String
    public var seconds: Int
    public var reps: String?
    public var motion: Motion
    public var caution: String?
}

public enum RoutineCategory: String, CaseIterable, Sendable {
    case neck = "Neck"
    case shoulders = "Shoulders"
    case upperBack = "Upper back"
    case wrists = "Wrists & forearms"
    case eyes = "Eyes"
    case standing = "Stand & walk"
    case mixed = "Full reset"
}

public struct Routine: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var category: RoutineCategory
    public var steps: [RoutineStep]
    /// Counts as a "long" break when completed away from the keyboard.
    public var isAwayBreak: Bool = false

    public var seconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    public var durationLabel: String {
        seconds < 60 ? "\(seconds) sec" : (seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s")
    }
}

public enum RoutineLibrary {
    public static let generalSafety = "Move slowly and only within a comfortable range. Never bounce or force a stretch. Stop if anything causes pain, numbness, tingling or dizziness. Sway can't assess pain: for persistent, severe or worsening pain, see a qualified clinician."

    static let neckCaution = "Keep it small and slow. Skip this if you've been told to avoid neck movements."

    // Steps, reused across routines.
    static let chinTuck = RoutineStep(title: "Chin tucks", instruction: "Sit tall. Gently draw your chin straight back, as if making a double chin, hold a moment, then release. Keep your eyes level.", seconds: 15, reps: "5 slow reps", motion: .chinTuck, caution: neckCaution)
    static let neckTilt = RoutineStep(title: "Side tilts", instruction: "Let one ear drift toward the shoulder on the same side, without lifting the shoulder. Pause, return to centre, then switch sides.", seconds: 20, reps: "2–3 per side", motion: .neckTilt, caution: neckCaution)
    static let neckTurn = RoutineStep(title: "Look over your shoulder", instruction: "Slowly turn your head to look over one shoulder, as far as is comfortable. Return to centre, then turn the other way.", seconds: 20, reps: "3 per side", motion: .neckTurn, caution: neckCaution)
    static let shoulderRoll = RoutineStep(title: "Shoulder rolls", instruction: "Roll your shoulders up, back and down in slow circles. Let your arms hang loose.", seconds: 15, reps: "5 backwards, 5 forwards", motion: .shoulderRoll, caution: nil)
    static let shrug = RoutineStep(title: "Shrug and drop", instruction: "Lift both shoulders toward your ears, hold for two seconds, then let them drop and relax completely.", seconds: 15, reps: "5 reps", motion: .shoulderShrug, caution: nil)
    static let bladeSqueeze = RoutineStep(title: "Shoulder-blade squeeze", instruction: "Gently draw your shoulder blades back and down, as if tucking them into your back pockets. Hold three seconds, release.", seconds: 20, reps: "5 reps", motion: .bladeSqueeze, caution: nil)
    static let overheadReach = RoutineStep(title: "Overhead reach", instruction: "Interlace your fingers and reach up toward the ceiling. Breathe out and grow tall, then lower your arms.", seconds: 15, reps: "3 reps", motion: .overheadReach, caution: "Skip if lifting your arms is painful.")
    static let chestOpener = RoutineStep(title: "Chest opener", instruction: "Clasp your hands behind your back (or hold the chair back), gently open your chest and look ahead. Breathe slowly.", seconds: 20, reps: "Hold, breathing slowly", motion: .chestOpener, caution: nil)
    static let backExtension = RoutineStep(title: "Seated back extension", instruction: "Hands on your lower back or the chair, gently lift your chest and lean back a little over the backrest. Return to upright.", seconds: 20, reps: "3–5 reps", motion: .backExtension, caution: "Keep it gentle; skip if it pinches.")
    static let seatedTwist = RoutineStep(title: "Seated twist", instruction: "Sit tall, feet flat. Turn your chest toward one side using the chair for light support, then the other side.", seconds: 20, reps: "2 per side", motion: .seatedTwist, caution: "Rotate from the middle of your back, not by pulling.")
    static let wristCircles = RoutineStep(title: "Wrist circles", instruction: "Make loose fists and draw slow circles with your wrists, both directions.", seconds: 15, reps: "5 each way", motion: .wristCircles, caution: nil)
    static let wristFlex = RoutineStep(title: "Wrist bends", instruction: "Arm forward, palm down. Let the hand drop gently, then lift it back up. Use the other hand only to support, not to pull.", seconds: 20, reps: "5 per hand", motion: .wristFlex, caution: "Stop if you feel tingling in your fingers.")
    static let fingerSpread = RoutineStep(title: "Spread and relax", instruction: "Spread your fingers wide for two seconds, then relax them into a soft, loose hand.", seconds: 15, reps: "5 reps", motion: .fingerSpread, caution: nil)
    static let lookFar = RoutineStep(title: "Look far away", instruction: "Look out of a window or at the farthest point in the room — about 6 metres (20 feet) or more — and let your eyes relax.", seconds: 20, reps: nil, motion: .lookFar, caution: nil)
    static let blink = RoutineStep(title: "Slow blinks", instruction: "Close your eyes fully, pause, and open them. Screens make us blink less.", seconds: 10, reps: "5 slow blinks", motion: .blink, caution: nil)
    static let palming = RoutineStep(title: "Palming", instruction: "Rub your palms together and rest them gently over closed eyes without pressing. Breathe slowly.", seconds: 20, reps: nil, motion: .palming, caution: nil)
    static let standUp = RoutineStep(title: "Stand up", instruction: "Stand up, feet hip-width apart. Let your arms hang and take a full breath.", seconds: 10, reps: nil, motion: .standUp, caution: nil)
    static let calfRaise = RoutineStep(title: "Calf raises", instruction: "Holding the desk for balance, rise onto your toes and lower slowly.", seconds: 20, reps: "10 reps", motion: .calfRaise, caution: nil)
    static let march = RoutineStep(title: "March in place", instruction: "March gently on the spot, swinging your arms.", seconds: 20, reps: nil, motion: .march, caution: nil)
    static let breathe = RoutineStep(title: "Three slow breaths", instruction: "Breathe in through your nose, let your belly expand, and breathe out slowly. Let your shoulders drop.", seconds: 15, reps: "3 breaths", motion: .breathe, caution: nil)

    public static let all: [Routine] = [
        Routine(id: "neck-30", title: "Neck reset", summary: "Undo a long stretch of looking at the screen.", category: .neck,
                steps: [chinTuck, RoutineStep(title: "Side tilts", instruction: neckTilt.instruction, seconds: 15, reps: "2 per side", motion: .neckTilt, caution: neckCaution)]),
        Routine(id: "shoulders-30", title: "Shoulder release", summary: "Let go of tension you didn't notice building.", category: .shoulders,
                steps: [shoulderRoll, shrug]),
        Routine(id: "eyes-30", title: "20-20-20 eye rest", summary: "Twenty seconds of distance focus, then a few blinks.", category: .eyes,
                steps: [lookFar, blink]),
        Routine(id: "desk-60", title: "Desk mobility minute", summary: "Neck, shoulders and back in one minute, without standing.", category: .mixed,
                steps: [chinTuck, shoulderRoll, seatedTwist, RoutineStep(title: "Overhead reach", instruction: overheadReach.instruction, seconds: 10, reps: "2 reps", motion: .overheadReach, caution: overheadReach.caution)]),
        Routine(id: "upperback-60", title: "Upper back opener", summary: "Counter the rounded-forward coding posture.", category: .upperBack,
                steps: [bladeSqueeze, chestOpener, backExtension]),
        Routine(id: "wrists-60", title: "Wrists and forearms", summary: "For long typing and mouse stretches.", category: .wrists,
                steps: [wristCircles, wristFlex, fingerSpread, RoutineStep(title: "Shake out", instruction: "Let your arms hang and gently shake out your hands.", seconds: 10, reps: nil, motion: .fingerSpread, caution: nil)]),
        Routine(id: "neck-60", title: "Gentle neck mobility", summary: "Slow, small movements in every direction.", category: .neck,
                steps: [chinTuck, neckTilt, neckTurn, RoutineStep(title: "Relax", instruction: "Let your shoulders drop and breathe slowly.", seconds: 5, reps: nil, motion: .breathe, caution: nil)]),
        Routine(id: "eyes-60", title: "Eye relax", summary: "A minute away from near focus.", category: .eyes,
                steps: [lookFar, palming, blink, RoutineStep(title: "Near and far", instruction: "Look at your thumb at arm's length, then at something far away. Shift slowly between them.", seconds: 10, reps: "3 shifts", motion: .lookFar, caution: nil)]),
        Routine(id: "stand-60", title: "Stand and reset", summary: "Get out of the chair for a minute.", category: .standing,
                steps: [standUp, calfRaise, march, RoutineStep(title: "Overhead reach", instruction: overheadReach.instruction, seconds: 10, reps: "2 reps", motion: .overheadReach, caution: overheadReach.caution)]),
        Routine(id: "full-180", title: "Full reset", summary: "Three minutes for neck, shoulders, back and wrists.", category: .mixed,
                steps: [standUp, chinTuck, neckTilt, shoulderRoll, bladeSqueeze, chestOpener, seatedTwist, wristCircles, wristFlex, breathe, RoutineStep(title: "Look far away", instruction: lookFar.instruction, seconds: 10, reps: nil, motion: .lookFar, caution: nil)]),
        Routine(id: "walk-180", title: "Walk break", summary: "Leave the desk: water, a window, a lap of the room.", category: .standing,
                steps: [RoutineStep(title: "Walk", instruction: "Step away from the desk. Refill water, walk to a window, or take the stairs. Sway will notice you're away.", seconds: 180, reps: nil, motion: .walk, caution: nil)],
                isAwayBreak: true),
        Routine(id: "snack-300", title: "Movement snack", summary: "Five minutes: walk, then a mobility round.", category: .mixed,
                steps: [RoutineStep(title: "Walk", instruction: "Walk around for a couple of minutes — anywhere away from the screen.", seconds: 120, reps: nil, motion: .walk, caution: nil),
                        chinTuck, neckTurn, shoulderRoll, bladeSqueeze, chestOpener, backExtension, wristCircles, lookFar, breathe]),
    ]

    public static func routine(_ id: String) -> Routine? { all.first { $0.id == id } }

    /// The routine to offer for a prompt.
    public static func suggested(for kind: ReminderKind) -> Routine {
        switch kind {
        case .headDown, .forwardLean, .lateralTilt: return routine("neck-60")!
        case .shoulderAsymmetry: return routine("shoulders-30")!
        case .staticPosture: return routine("desk-60")!
        case .eyeRest: return routine("eyes-30")!
        case .longBreak, .longSession: return routine("walk-180")!
        case .microBreak, .workstationReview: return routine("desk-60")!
        }
    }
}

public struct GuideItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var area: String
    public var symbol: String
    public var title: String
    public var guidance: String
    public var check: String
    public var evidence: EvidenceLevel
}

/// Workstation guidance drawn from occupational-health sources (OSHA's
/// Computer Workstations eTool, CCOHS office ergonomics, ISO 9241-5 /
/// ANSI/HFES 100). Practical adjustments, not a diagnosis.
public enum WorkstationGuide {
    public static let sources = [
        "OSHA — Computer Workstations eTool (Workstation components: monitors, chairs, keyboards, pointers)",
        "CCOHS — Office Ergonomics: positioning the monitor; sitting and standing",
        "ANSI/HFES 100-2007 Human Factors Engineering of Computer Workstations",
        "ISO 9241-5 Workstation layout and postural requirements",
    ]

    public static let items: [GuideItem] = [
        GuideItem(id: "monitor-height", area: "Screen", symbol: "arrow.up.and.down.square",
                  title: "Monitor height",
                  guidance: "Set the top of the screen at or slightly below eye level, so you look slightly down at the middle of the screen (roughly 15–20° below straight ahead). If you wear bifocals or progressive lenses, go lower so you don't tilt your head back. A laptop screen on its own is almost always too low: raise it on a stand and use an external keyboard and mouse.",
                  check: "Sitting back comfortably, can you read the middle of the screen without bending your neck forward or tipping your chin up?",
                  evidence: .evidenceInformed),
        GuideItem(id: "viewing-distance", area: "Screen", symbol: "ruler",
                  title: "Viewing distance",
                  guidance: "Place the screen about an arm's length away (roughly 50–100 cm / 20–40 in). If you lean in to read, enlarge the text rather than moving your head toward the screen.",
                  check: "Can you read comfortably while leaning back against your chair?",
                  evidence: .evidenceInformed),
        GuideItem(id: "screen-angle", area: "Screen", symbol: "rectangle.portrait.rotate",
                  title: "Screen angle and glare",
                  guidance: "Tilt the screen back slightly (about 10–20°) so it faces your eyes. Place it at a right angle to windows and adjust brightness to the room to avoid glare and squinting.",
                  check: "Is the screen free of reflections from windows or lamps?",
                  evidence: .evidenceInformed),
        GuideItem(id: "external-monitor", area: "Screen", symbol: "rectangle.on.rectangle",
                  title: "External and multiple monitors",
                  guidance: "Put the screen you use most directly in front of you, in line with the keyboard. With two screens used equally, butt them together and centre the seam on you; a secondary screen goes to the side, angled in, at the same height.",
                  check: "Is the screen you use most straight ahead, so you're not turned to one side for hours?",
                  evidence: .evidenceInformed),
        GuideItem(id: "chair-height", area: "Chair", symbol: "chair",
                  title: "Chair height and back support",
                  guidance: "Adjust the seat so your feet rest flat and your thighs are roughly level, knees about hip height. Sit back so the backrest supports your lower back; a slightly reclined backrest (100–110°) is fine.",
                  check: "Is your back supported without perching on the front of the seat?",
                  evidence: .evidenceInformed),
        GuideItem(id: "foot-support", area: "Chair", symbol: "shoeprints.fill",
                  title: "Foot support",
                  guidance: "If raising the chair to desk height leaves your feet dangling, use a footrest (a box or a stack of books works).",
                  check: "Do both feet rest flat on the floor or a footrest?",
                  evidence: .evidenceInformed),
        GuideItem(id: "desk-height", area: "Desk", symbol: "table.furniture",
                  title: "Desk and keyboard height",
                  guidance: "The keyboard should sit at about elbow height with your shoulders relaxed, elbows bent around 90–110°. If the desk is too high and can't change, raise the chair and add a footrest.",
                  check: "With your shoulders relaxed, are your forearms roughly level when typing?",
                  evidence: .evidenceInformed),
        GuideItem(id: "keyboard-mouse", area: "Desk", symbol: "keyboard",
                  title: "Keyboard and mouse placement",
                  guidance: "Keep the keyboard and mouse close and at the same height, the mouse right beside the keyboard. Keep wrists roughly straight; a flat keyboard (feet folded) usually helps.",
                  check: "Can you reach the mouse without stretching your arm out to the side or forward?",
                  evidence: .evidenceInformed),
        GuideItem(id: "forearm-support", area: "Desk", symbol: "hand.raised",
                  title: "Forearm support",
                  guidance: "Let your forearms rest on armrests or the desk so your shoulders don't hold your arms up. Armrests should be low enough that your shoulders stay down.",
                  check: "Are your shoulders relaxed (not lifted) while you type?",
                  evidence: .evidenceInformed),
        GuideItem(id: "neck-shoulders", area: "You", symbol: "person.fill",
                  title: "Neck and shoulder comfort",
                  guidance: "Use a headset for calls instead of cradling a phone. Place documents you read often next to the screen at the same height.",
                  check: "Do you avoid holding your head turned or tilted for long periods?",
                  evidence: .evidenceInformed),
        GuideItem(id: "variation", area: "You", symbol: "figure.walk",
                  title: "Vary your position",
                  guidance: "No single posture is right for hours. Changing position often, standing for parts of the day if you can, and short movement breaks matter more than sitting perfectly still and upright.",
                  check: "Do you change position at least every half hour or so?",
                  evidence: .heuristic),
    ]

    /// Advice from manual measurements. Never claims a measurement the user
    /// didn't give.
    public static func advice(viewingDistanceCm: Double?, screenTop: ScreenTopPosition?, usesLaptopScreenOnly: Bool?) -> [String] {
        var out: [String] = []
        if let d = viewingDistanceCm {
            if d < 45 { out.append("At \(Int(d)) cm the screen is closer than the usual 50–100 cm. Move it back a little and enlarge text if needed.") }
            else if d > 110 { out.append("At \(Int(d)) cm the screen is farther than usual; if you find yourself leaning in, move it closer or enlarge text.") }
            else { out.append("Viewing distance of \(Int(d)) cm is within the commonly recommended range.") }
        }
        switch screenTop {
        case .aboveEyes: out.append("The top of the screen is above eye level, which can tip your chin up. Lower it so the top is at or slightly below eye level.")
        case .wellBelow: out.append("The screen is well below eye level, a common cause of looking down for long periods. Raise it (a stand or a stack of books works).")
        case .atEyes, .slightlyBelow: out.append("Screen height looks right: top at or slightly below eye level.")
        case nil: break
        }
        if usesLaptopScreenOnly == true {
            out.append("Working on a laptop's own screen and keyboard forces a choice between a low screen and raised arms. A laptop stand plus an external keyboard and mouse fixes both.")
        }
        return out
    }
}

public enum ScreenTopPosition: String, CaseIterable, Codable, Sendable {
    case aboveEyes = "Above my eyes"
    case atEyes = "At eye level"
    case slightlyBelow = "Slightly below eye level"
    case wellBelow = "Well below eye level"
}
