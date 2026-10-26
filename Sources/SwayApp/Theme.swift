import SwayCore
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.24, green: 0.56, blue: 0.52)       // calm teal
    static let warm = Color(red: 0.86, green: 0.55, blue: 0.26)         // attention, not alarm
    static let quiet = Color.secondary
    static let radius: CGFloat = 12
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct EvidenceTag: View {
    var level: EvidenceLevel
    var body: some View {
        Text(level.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch level {
        case .evidenceInformed: return Theme.accent
        case .heuristic: return .blue
        case .preference: return .purple
        case .experimental: return Theme.warm
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension TrackingStatus {
    var color: Color {
        switch self {
        case .tracking: return .green
        case .lookingAway, .searching: return .yellow
        case .lowConfidence, .needsRecalibration, .notCalibrated: return Theme.warm
        case .off: return .secondary
        }
    }
}

extension TimeInterval {
    var minutesText: String { Format.duration(self) }
}
