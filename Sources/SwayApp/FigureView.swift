import SwayCore
import SwiftUI

/// A simple line figure that demonstrates each movement. Drawn, not video:
/// small, crisp in both appearances, and gentle in tempo (one cycle ~4 s).
struct FigureView: View {
    var motion: Motion
    var paused = false
    var period: Double = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            switch motion {
            case .standUp, .calfRaise, .march, .walk:
                symbolFigure(t)
            default:
                Canvas { ctx, size in
                    let scale = min(size.width, size.height) / 200
                    ctx.translateBy(x: (size.width - 200 * scale) / 2, y: (size.height - 200 * scale) / 2)
                    ctx.scaleBy(x: scale, y: scale)
                    draw(&ctx, t: t)
                }
            }
        }
        .accessibilityLabel(Text("Illustration: \(motion.rawValue)"))
    }

    // MARK: Drawing

    private let ink = Theme.accent
    private func s(_ t: Double) -> Double { sin(t * 2 * .pi) }
    /// 0 → 1 → 0 with a hold at the top: smooth and unhurried.
    private func pulse(_ t: Double) -> Double { (1 - cos(t * 2 * .pi)) / 2 }

    private func draw(_ ctx: inout GraphicsContext, t: Double) {
        switch motion {
        case .chinTuck: side(&ctx, headShift: -7 * pulse(t))
        case .shoulderRoll: side(&ctx, shoulder: CGPoint(x: 5 * cos(t * 2 * .pi), y: 5 * sin(t * 2 * .pi)))
        case .bladeSqueeze: side(&ctx, shoulder: CGPoint(x: -6 * pulse(t), y: 2 * pulse(t)), chest: 4 * pulse(t))
        case .backExtension: side(&ctx, lean: -12 * pulse(t))
        case .neckTilt: front(&ctx, headRoll: 18 * s(t))
        case .neckTurn: front(&ctx, headTurn: s(t))
        case .shoulderShrug: front(&ctx, shrug: 11 * pulse(t))
        case .overheadReach: front(&ctx, armsUp: pulse(t))
        case .chestOpener: front(&ctx, armsOut: pulse(t))
        case .seatedTwist: front(&ctx, headTurn: 0.6 * s(t), twist: s(t))
        case .wristCircles: hand(&ctx, angle: 22 * s(t), lift: 10 * cos(t * 2 * .pi), spread: 0.2)
        case .wristFlex: hand(&ctx, angle: 40 * s(t), lift: 0, spread: 0.2)
        case .fingerSpread: hand(&ctx, angle: 0, lift: 0, spread: pulse(t))
        case .lookFar: eye(&ctx, t: t, far: true)
        case .blink: eye(&ctx, t: t, far: false)
        case .palming: palming(&ctx, t: t)
        case .breathe: breathe(&ctx, t: t)
        case .standUp, .calfRaise, .march, .walk: break
        }
    }

    private func line(_ ctx: inout GraphicsContext, _ pts: [CGPoint], width: CGFloat = 7) {
        var p = Path()
        p.addLines(pts)
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func head(_ ctx: inout GraphicsContext, at c: CGPoint, r: CGFloat = 19, roll: Double = 0, turn: Double = 0) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.14)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(ink), lineWidth: 4)
        // Eyes and nose show where the head points.
        let a = roll * .pi / 180
        func rot(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a))
        }
        let shift = CGFloat(turn) * 8
        for dx in [-7.0, 7.0] {
            let e = rot(CGFloat(dx) + shift, -3)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 2.2, y: e.y - 2.2, width: 4.4, height: 4.4)), with: .color(ink))
        }
        let n = rot(shift * 1.3, 6)
        ctx.fill(Path(ellipseIn: CGRect(x: n.x - 1.6, y: n.y - 1.6, width: 3.2, height: 3.2)), with: .color(ink.opacity(0.7)))
    }

    private func chair(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 55, y: 158, width: 90, height: 8), cornerSize: CGSize(width: 4, height: 4))
        ctx.fill(p, with: .color(.secondary.opacity(0.25)))
    }

    private func front(_ ctx: inout GraphicsContext, headRoll: Double = 0, headTurn: Double = 0, shrug: Double = 0, armsUp: Double = 0, armsOut: Double = 0, twist: Double = 0) {
        chair(&ctx)
        let half = 30 * CGFloat(1 - 0.25 * abs(twist))
        let sy = 98 - CGFloat(shrug)
        let cx = 100 + CGFloat(twist) * 4
        let ls = CGPoint(x: cx - half, y: sy), rs = CGPoint(x: cx + half, y: sy)
        // Torso
        line(&ctx, [CGPoint(x: 100, y: 156), CGPoint(x: cx, y: 100)], width: 9)
        line(&ctx, [ls, rs], width: 8)
        // Arms: resting → overhead (armsUp) or opened out and back (armsOut).
        for (sh, dir) in [(ls, -1.0), (rs, 1.0)] {
            let restElbow = CGPoint(x: sh.x + CGFloat(dir) * 6, y: sh.y + 34)
            let restHand = CGPoint(x: sh.x + CGFloat(dir) * -6, y: sh.y + 58)
            let upElbow = CGPoint(x: sh.x + CGFloat(dir) * 4, y: sh.y - 34)
            let upHand = CGPoint(x: 100 + CGFloat(dir) * 4, y: sh.y - 66)
            let outElbow = CGPoint(x: sh.x + CGFloat(dir) * 26, y: sh.y + 22)
            let outHand = CGPoint(x: sh.x + CGFloat(dir) * 18, y: sh.y + 50)
            func mix(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGPoint {
                let u = CGFloat(armsUp), o = CGFloat(armsOut)
                return CGPoint(x: a.x + (b.x - a.x) * u + (c.x - a.x) * o, y: a.y + (b.y - a.y) * u + (c.y - a.y) * o)
            }
            line(&ctx, [sh, mix(restElbow, upElbow, outElbow), mix(restHand, upHand, outHand)], width: 6)
        }
        // Neck and head pivot at the base of the neck.
        let base = CGPoint(x: cx, y: sy - 4)
        let a = CGFloat(headRoll * .pi / 180)
        let hc = CGPoint(x: base.x + 28 * sin(a), y: base.y - 28 * cos(a))
        line(&ctx, [base, CGPoint(x: base.x + 9 * sin(a), y: base.y - 9 * cos(a))], width: 7)
        head(&ctx, at: hc, roll: headRoll, turn: headTurn)
    }

    private func side(_ ctx: inout GraphicsContext, headShift: Double = 0, shoulder: CGPoint = .zero, chest: Double = 0, lean: Double = 0) {
        // Chair back and seat.
        line(&ctx, [CGPoint(x: 70, y: 166), CGPoint(x: 130, y: 166)], width: 6)
        line(&ctx, [CGPoint(x: 68, y: 166), CGPoint(x: 62, y: 96)], width: 5)
        let hip = CGPoint(x: 82, y: 158)
        let a = lean * .pi / 180
        let top = CGPoint(x: hip.x + 58 * sin(-a) + 6, y: hip.y - 58 * cos(a))
        let sh = CGPoint(x: top.x + shoulder.x + CGFloat(chest) * 0.3, y: top.y + shoulder.y)
        var torso = Path()
        torso.move(to: hip)
        torso.addQuadCurve(to: sh, control: CGPoint(x: (hip.x + sh.x) / 2 + 8 + CGFloat(chest), y: (hip.y + sh.y) / 2))
        ctx.stroke(torso, with: .color(ink), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        // Thigh and shin.
        line(&ctx, [hip, CGPoint(x: 132, y: 158), CGPoint(x: 134, y: 196)], width: 7)
        // Arm resting forward.
        line(&ctx, [sh, CGPoint(x: sh.x + 10, y: sh.y + 34), CGPoint(x: sh.x + 40, y: sh.y + 40)], width: 6)
        let neckTop = CGPoint(x: sh.x + 6 + CGFloat(headShift) * 0.4, y: sh.y - 14)
        line(&ctx, [CGPoint(x: sh.x + 2, y: sh.y - 2), neckTop], width: 7)
        let hc = CGPoint(x: neckTop.x + 6 + CGFloat(headShift), y: neckTop.y - 18)
        let rect = CGRect(x: hc.x - 19, y: hc.y - 19, width: 38, height: 38)
        ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.14)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(ink), lineWidth: 4)
        ctx.fill(Path(ellipseIn: CGRect(x: hc.x + 9, y: hc.y - 5, width: 4.4, height: 4.4)), with: .color(ink))
    }

    private func hand(_ ctx: inout GraphicsContext, angle: Double, lift: Double, spread: Double) {
        let wrist = CGPoint(x: 96, y: 104 + lift)
        line(&ctx, [CGPoint(x: 20, y: 110), wrist], width: 14)
        let a = angle * .pi / 180
        var palm = ctx
        palm.translateBy(x: wrist.x, y: wrist.y)
        palm.rotate(by: .radians(a))
        let pr = CGRect(x: 0, y: -14, width: 40, height: 28)
        palm.fill(Path(roundedRect: pr, cornerRadius: 10), with: .color(ink.opacity(0.14)))
        palm.stroke(Path(roundedRect: pr, cornerRadius: 10), with: .color(ink), lineWidth: 4)
        for i in 0..<4 {
            let base = CGPoint(x: 38, y: -10 + CGFloat(i) * 6.7)
            let fan = (Double(i) - 1.5) * 0.22 * spread
            let tip = CGPoint(x: base.x + 28 * cos(fan), y: base.y + 28 * sin(fan))
            var p = Path()
            p.move(to: base)
            p.addLine(to: tip)
            palm.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        var thumb = Path()
        thumb.move(to: CGPoint(x: 18, y: -12))
        thumb.addLine(to: CGPoint(x: 30, y: -30 - 6 * spread))
        palm.stroke(thumb, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func eye(_ ctx: inout GraphicsContext, t: Double, far: Bool) {
        let c = CGPoint(x: 100, y: 112)
        if far {
            // Distant hills: where to look.
            var hills = Path()
            hills.move(to: CGPoint(x: 10, y: 60))
            hills.addCurve(to: CGPoint(x: 190, y: 56), control1: CGPoint(x: 60, y: 24), control2: CGPoint(x: 130, y: 70))
            ctx.stroke(hills, with: .color(.secondary.opacity(0.5)), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: 150, y: 18, width: 16, height: 16)), with: .color(Theme.warm.opacity(0.6)))
        }
        // Blink twice per cycle when blinking, once otherwise.
        let blinkPhase = far ? (t > 0.9 ? (t - 0.9) / 0.1 : 0) : (t.truncatingRemainder(dividingBy: 0.5) > 0.38 ? (t.truncatingRemainder(dividingBy: 0.5) - 0.38) / 0.12 : 0)
        let open = 1 - sin(blinkPhase * .pi)
        let h = 34 * open + 1
        var lid = Path()
        lid.move(to: CGPoint(x: c.x - 56, y: c.y))
        lid.addQuadCurve(to: CGPoint(x: c.x + 56, y: c.y), control: CGPoint(x: c.x, y: c.y - h * 1.6))
        lid.addQuadCurve(to: CGPoint(x: c.x - 56, y: c.y), control: CGPoint(x: c.x, y: c.y + h * 1.6))
        ctx.fill(lid, with: .color(ink.opacity(0.1)))
        ctx.stroke(lid, with: .color(ink), lineWidth: 4)
        if open > 0.3 {
            let look = far ? CGPoint(x: 10 * sin(t * 2 * .pi), y: -8) : .zero
            let r = 15 * open
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + look.x - r, y: c.y + look.y - r, width: 2 * r, height: 2 * r)), with: .color(ink))
        }
    }

    private func palming(_ ctx: inout GraphicsContext, t: Double) {
        head(&ctx, at: CGPoint(x: 100, y: 100), r: 52)
        let cover = pulse(min(1, t * 1.6))
        for dx in [-24.0, 24.0] {
            let rect = CGRect(x: 100 + dx - 28, y: 90 - 22 + (1 - cover) * 60, width: 56, height: 44)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 18), with: .color(ink.opacity(0.35)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 18), with: .color(ink), lineWidth: 3)
        }
    }

    private func breathe(_ ctx: inout GraphicsContext, t: Double) {
        let r = 30 + 40 * pulse(t)
        let c = CGPoint(x: 100, y: 100)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.14)))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink), lineWidth: 4)
        ctx.draw(Text(t < 0.5 ? "in" : "out").font(.system(size: 16, weight: .medium)).foregroundColor(ink), at: c)
    }

    @ViewBuilder private func symbolFigure(_ t: Double) -> some View {
        let name: String = {
            switch motion {
            case .walk, .march: return "figure.walk"
            case .standUp: return "figure.stand"
            default: return "figure.stand"
            }
        }()
        let bounce: Double = {
            switch motion {
            case .calfRaise: return -12 * pulse(t)
            case .march, .walk: return -5 * abs(s(t * 2))
            case .standUp: return -8 * pulse(t)
            default: return 0
            }
        }()
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.accent)
            .padding(40)
            .offset(y: bounce)
            .scaleEffect(x: motion == .march && t > 0.5 ? -1 : 1, y: 1)
    }
}
