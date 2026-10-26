import SwayCore
import SwiftUI

// Diagrams for the workstation setup assistant. Every drawing uses the same
// language: neutral ink for people and furniture, teal for what the guidance
// recommends, warm orange for the common mistake. Ranges are labelled as
// approximate ("about", "roughly"), matching the written guidance.

/// One drawing with its verdict and a one-line caption.
struct IllustrationPanel: Identifiable {
    enum Kind { case mistake, recommended }

    var kind: Kind
    var title: String
    var caption: String
    /// The part of the drawing space to show, scaled to fit the panel.
    var viewport = SetupIllustrations.side
    var draw: (Sketch) -> Void

    var id: String { title }
}

/// All panels for a setup item, laid out as a grid.
struct SetupIllustration: View {
    var itemID: String

    var body: some View {
        let panels = SetupIllustrations.panels(for: itemID)
        if panels.count == 1, let p = panels.first {
            PanelView(panel: p)
        } else if !panels.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(panels) { PanelView(panel: $0) }
            }
        }
    }
}

private struct PanelView: View {
    var panel: IllustrationPanel

    var body: some View {
        let color = panel.kind == .mistake ? Theme.warm : Theme.accent
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(panel.title).font(.system(size: 11, weight: .semibold))
            } icon: {
                Image(systemName: panel.kind == .mistake ? "xmark.circle.fill" : "checkmark.circle.fill")
            }
            .foregroundStyle(color)
            Canvas { ctx, size in
                panel.draw(Sketch(ctx, size, viewport: panel.viewport))
            }
            .aspectRatio(panel.viewport.width / panel.viewport.height, contentMode: .fit)
            .clipped()
            .accessibilityLabel(Text("\(panel.title). \(panel.caption)"))
            Text(panel.caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.28), lineWidth: 1))
    }
}

// MARK: Drawing kit

/// Degrees to radians, as CGFloat so trigonometry stays unambiguous.
func rad(_ degrees: Double) -> CGFloat { CGFloat(degrees * .pi / 180) }

/// Draws in a design space (y down) whose viewport is scaled to the canvas. Line widths
/// scale with the drawing; text stays at its point size.
struct Sketch {
    let ctx: GraphicsContext
    let scale: CGFloat
    let origin: CGPoint

    init(_ ctx: GraphicsContext, _ size: CGSize, viewport v: CGRect) {
        self.ctx = ctx
        scale = min(size.width / v.width, size.height / v.height)
        origin = CGPoint(x: (size.width - v.width * scale) / 2 - v.minX * scale, y: (size.height - v.height * scale) / 2 - v.minY * scale)
    }

    static let ink = Color.primary.opacity(0.8)
    static let furniture = Color.secondary.opacity(0.75)
    static let faint = Color.secondary.opacity(0.35)
    static let good = Theme.accent
    static let bad = Theme.warm

    func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: origin.x + pt.x * scale, y: origin.y + pt.y * scale) }

    func line(_ pts: [CGPoint], _ color: Color = ink, width: CGFloat = 2.4, dash: [CGFloat] = []) {
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: p(first))
        for pt in pts.dropFirst() { path.addLine(to: p(pt)) }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round, dash: dash.map { $0 * scale }))
    }

    func circle(_ c: CGPoint, _ r: CGFloat, _ color: Color = ink, width: CGFloat = 2.4, fill: Color? = nil) {
        let rect = CGRect(x: p(c).x - r * scale, y: p(c).y - r * scale, width: 2 * r * scale, height: 2 * r * scale)
        if let fill { ctx.fill(Path(ellipseIn: rect), with: .color(fill)) }
        if width > 0 { ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width * scale) }
    }

    func rect(_ r: CGRect, _ color: Color = furniture, width: CGFloat = 1.6, fill: Color? = nil, corner: CGFloat = 1.5) {
        let rr = CGRect(origin: p(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
        let path = Path(roundedRect: rr, cornerRadius: corner * scale)
        if let fill { ctx.fill(path, with: .color(fill)) }
        if width > 0 { ctx.stroke(path, with: .color(color), lineWidth: width * scale) }
    }

    /// A polygon (used for rotated top-view objects).
    func shape(_ pts: [CGPoint], _ color: Color = furniture, width: CGFloat = 1.6, fill: Color? = nil) {
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: p(first))
        for pt in pts.dropFirst() { path.addLine(to: p(pt)) }
        path.closeSubpath()
        if let fill { ctx.fill(path, with: .color(fill)) }
        if width > 0 { ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineJoin: .round)) }
    }

    /// An arc from `from` to `to` degrees, measured like `atan2` in y-down
    /// space: 0 points right, positive angles turn downward.
    func arc(_ c: CGPoint, _ r: CGFloat, from: Double, to: Double, _ color: Color = good, width: CGFloat = 1.6) {
        let n = 24
        let pts = (0...n).map { i -> CGPoint in
            let a = rad(from + (to - from) * Double(i) / Double(n))
            return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        line(pts, color, width: width)
    }

    func arrow(_ a: CGPoint, _ b: CGPoint, _ color: Color = good, width: CGFloat = 1.6, dash: [CGFloat] = [], heads: (start: Bool, end: Bool) = (false, true)) {
        line([a, b], color, width: width, dash: dash)
        func head(at tip: CGPoint, from tail: CGPoint) {
            let ang: CGFloat = atan2(tip.y - tail.y, tip.x - tail.x)
            let l: CGFloat = 5
            let left = CGPoint(x: tip.x - l * cos(ang - 0.45), y: tip.y - l * sin(ang - 0.45))
            let right = CGPoint(x: tip.x - l * cos(ang + 0.45), y: tip.y - l * sin(ang + 0.45))
            line([left, tip, right], color, width: width)
        }
        if heads.end { head(at: b, from: a) }
        if heads.start { head(at: a, from: b) }
    }

    func label(_ text: String, _ at: CGPoint, _ color: Color = .secondary, size: CGFloat = 10, weight: Font.Weight = .medium, anchor: UnitPoint = .center) {
        ctx.draw(Text(text).font(.system(size: size, weight: weight)).foregroundColor(color), at: p(at), anchor: anchor)
    }
}

/// A seated or standing person seen from the side, facing right.
struct SidePerson {
    var head: CGPoint
    var shoulder: CGPoint
    var hip: CGPoint
    var elbow: CGPoint
    var hand: CGPoint
    var knee: CGPoint
    var ankle: CGPoint
    var toe: CGPoint
    var headR: CGFloat = 8.5
    /// Gaze direction in degrees (0 = straight ahead, positive = down).
    var gaze: Double = 0

    var eye: CGPoint {
        let a = rad(gaze)
        return CGPoint(x: head.x + headR * 0.55 * cos(a), y: head.y - 1.5 + headR * 0.45 * sin(a))
    }

    /// Where the neck meets the head.
    var neckTop: CGPoint {
        let dx = shoulder.x - head.x, dy = shoulder.y - head.y
        let d = max(sqrt(dx * dx + dy * dy), 0.001)
        return CGPoint(x: head.x + dx / d * headR, y: head.y + dy / d * headR)
    }

    /// Draws the figure; `highlight` recolours the named parts.
    func draw(_ s: Sketch, highlight: Set<Part> = [], color: Color = Sketch.bad) {
        func c(_ part: Part) -> Color { highlight.contains(part) ? color : Sketch.ink }
        s.line([hip, knee, ankle, toe], c(.legs), width: 2.6)
        s.line([hip, shoulder], c(.torso), width: 2.8)
        s.line([shoulder, neckTop], c(.neck), width: 2.6)
        s.line([shoulder, elbow, hand], c(.arms), width: 2.4)
        s.circle(head, headR, c(.head), width: 2.4)
        s.circle(eye, 1.2, c(.head), width: 0, fill: c(.head))
    }

    enum Part { case head, neck, torso, arms, legs }
}

/// Side-view furniture.
enum Furniture {
    static func floor(_ s: Sketch, y: CGFloat = 124, x0: CGFloat = 8, x1: CGFloat = 192) {
        s.line([CGPoint(x: x0, y: y), CGPoint(x: x1, y: y)], Sketch.faint, width: 1.2)
    }

    /// Office chair: seat from `seatX0` to `seatX1` at `seatY`, backrest
    /// reclined to `backTop`.
    static func chair(_ s: Sketch, seatY: CGFloat, seatX0: CGFloat = 42, seatX1: CGFloat = 88, backTop: CGPoint, floorY: CGFloat = 124, color: Color = Sketch.furniture) {
        s.line([CGPoint(x: seatX0, y: seatY), CGPoint(x: seatX1, y: seatY)], color, width: 3.2)
        s.line([CGPoint(x: seatX0 + 1, y: seatY), backTop], color, width: 3.2)
        let post = (seatX0 + seatX1) / 2
        s.line([CGPoint(x: post, y: seatY + 2), CGPoint(x: post, y: floorY - 6)], color, width: 2.2)
        s.line([CGPoint(x: post - 15, y: floorY - 5), CGPoint(x: post + 15, y: floorY - 5)], color, width: 2.2)
        s.circle(CGPoint(x: post - 15, y: floorY - 2.5), 2.2, color, width: 1.4)
        s.circle(CGPoint(x: post + 15, y: floorY - 2.5), 2.2, color, width: 1.4)
    }

    static func desk(_ s: Sketch, topY: CGFloat, x0: CGFloat = 76, x1: CGFloat = 194, floorY: CGFloat = 124) {
        s.rect(CGRect(x: x0, y: topY, width: x1 - x0, height: 3.5), Sketch.furniture, width: 1.4, fill: Sketch.faint.opacity(0.5))
        s.line([CGPoint(x: x1 - 6, y: topY + 3.5), CGPoint(x: x1 - 6, y: floorY)], Sketch.furniture, width: 2)
    }

    static func keyboard(_ s: Sketch, x: CGFloat, deskY: CGFloat, width: CGFloat = 18, color: Color = Sketch.furniture) {
        s.rect(CGRect(x: x, y: deskY - 2.6, width: width, height: 2.6), color, width: 1.2, fill: color.opacity(0.35))
    }

    /// A monitor seen from the side: the screen tilted back by `tilt`
    /// degrees from its top edge, on a stand down to the desk.
    @discardableResult
    static func monitor(_ s: Sketch, top: CGPoint, height: CGFloat = 34, tilt: Double = 10, deskY: CGFloat, color: Color = Sketch.ink) -> (top: CGPoint, bottom: CGPoint, centre: CGPoint) {
        let a = rad(tilt)
        let bottom = CGPoint(x: top.x - sin(a) * height, y: top.y + cos(a) * height)
        let centre = CGPoint(x: (top.x + bottom.x) / 2, y: (top.y + bottom.y) / 2)
        s.line([top, bottom], color, width: 4.2)
        let foot = CGPoint(x: centre.x + 7, y: deskY - 0.5)
        s.line([CGPoint(x: centre.x + 1.5, y: centre.y + 2), CGPoint(x: centre.x + 7, y: centre.y + 9), foot], Sketch.furniture, width: 2)
        s.line([CGPoint(x: foot.x - 8, y: deskY - 0.5), CGPoint(x: foot.x + 8, y: deskY - 0.5)], Sketch.furniture, width: 2.2)
        return (top, bottom, centre)
    }
}

/// Top-view pieces: the person sits at the bottom, facing up.
enum TopView {
    static func person(_ s: Sketch, at c: CGPoint, facing: Double = -90, color: Color = Sketch.ink) {
        s.shape(ellipse(CGPoint(x: c.x, y: c.y + 6), rx: 17, ry: 6.5), color, width: 2.2)
        s.circle(c, 7, color, width: 2.2)
        let a = rad(facing)
        s.line([CGPoint(x: c.x + 7 * cos(a), y: c.y + 7 * sin(a)), CGPoint(x: c.x + 10.5 * cos(a), y: c.y + 10.5 * sin(a))], color, width: 2.2)
    }

    static func ellipse(_ c: CGPoint, rx: CGFloat, ry: CGFloat) -> [CGPoint] {
        (0..<32).map { i in
            let a = CGFloat(i) / 32 * 2 * .pi
            return CGPoint(x: c.x + rx * cos(a), y: c.y + ry * sin(a))
        }
    }

    /// A rectangle of `w`×`h` centred on `c`, rotated by `angle` degrees.
    static func box(_ c: CGPoint, w: CGFloat, h: CGFloat, angle: Double = 0) -> [CGPoint] {
        let a = rad(angle)
        let corners: [(CGFloat, CGFloat)] = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
        return corners.map { x, y in
            let rx: CGFloat = x * cos(a) - y * sin(a)
            let ry: CGFloat = x * sin(a) + y * cos(a)
            return CGPoint(x: c.x + rx, y: c.y + ry)
        }
    }

    static func desk(_ s: Sketch, _ r: CGRect = CGRect(x: 18, y: 14, width: 164, height: 74)) {
        s.rect(r, Sketch.furniture, width: 1.4, fill: Sketch.faint.opacity(0.25), corner: 3)
    }

    /// A monitor seen from above: a thick bar, its screen facing `angle + 90`.
    static func monitor(_ s: Sketch, at c: CGPoint, width: CGFloat = 52, angle: Double = 0, color: Color = Sketch.ink) {
        s.shape(box(c, w: width, h: 4.5, angle: angle), color, width: 1.4, fill: color)
        let a = rad(angle)
        s.shape(box(CGPoint(x: c.x + 5 * sin(a), y: c.y - 5 * cos(a)), w: 12, h: 5, angle: angle), Sketch.furniture, width: 1.2)
    }

    static func keyboard(_ s: Sketch, at c: CGPoint, width: CGFloat = 40, numpad: Bool = false, color: Color = Sketch.furniture) {
        s.shape(box(c, w: width, h: 11), color, width: 1.3, fill: color.opacity(0.25))
        for row in 0..<3 {
            let y = c.y - 3.2 + CGFloat(row) * 3.2
            s.line([CGPoint(x: c.x - width / 2 + 3, y: y), CGPoint(x: c.x + width / 2 - (numpad ? 12 : 3), y: y)], color.opacity(0.7), width: 0.8)
        }
        if numpad { s.line([CGPoint(x: c.x + width / 2 - 9, y: c.y - 4), CGPoint(x: c.x + width / 2 - 9, y: c.y + 4)], color.opacity(0.7), width: 0.8) }
    }

    static func mouse(_ s: Sketch, at c: CGPoint, color: Color = Sketch.ink) {
        s.shape(box(c, w: 7, h: 10), color, width: 1.4, fill: color.opacity(0.25))
    }

    /// Arms from the shoulders to two hand points.
    static func arms(_ s: Sketch, person c: CGPoint, left: CGPoint, right: CGPoint, color: Color = Sketch.ink) {
        s.line([CGPoint(x: c.x - 15, y: c.y + 6), left], color, width: 2.2)
        s.line([CGPoint(x: c.x + 15, y: c.y + 6), right], color, width: 2.2)
    }
}

/// A person seen from the front, sitting. Shoulders lift toward a fixed
/// head; a tilted head pivots on the base of the neck.
struct FrontPerson {
    var headY: CGFloat = 30
    var headTilt: Double = 0          // degrees, positive toward the viewer's right
    var shoulderY: CGFloat = 58
    var lift: CGFloat = 0             // both shoulders
    var rightLift: CGFloat = 0        // the viewer's right shoulder, extra
    var elbowOut: CGFloat = 0
    var elbowY: CGFloat = 88

    var leftShoulder: CGPoint { CGPoint(x: 78, y: shoulderY - lift) }
    var rightShoulder: CGPoint { CGPoint(x: 122, y: shoulderY - lift - rightLift) }
    var neckBase: CGPoint { CGPoint(x: 100, y: (leftShoulder.y + rightShoulder.y) / 2 - 3) }

    var headCentre: CGPoint {
        let d = neckBase.y - headY
        let a = rad(headTilt)
        return CGPoint(x: neckBase.x + d * sin(a), y: neckBase.y - d * cos(a))
    }

    func draw(_ s: Sketch, highlight: Set<SidePerson.Part> = [], color: Color = Sketch.bad) {
        func c(_ part: SidePerson.Part) -> Color { highlight.contains(part) ? color : Sketch.ink }
        let ls = leftShoulder, rs = rightShoulder, h = headCentre
        let dx = neckBase.x - h.x, dy = neckBase.y - h.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let neckTop = CGPoint(x: h.x + dx / len * 10, y: h.y + dy / len * 10)
        s.line([ls, CGPoint(x: 89, y: 110), CGPoint(x: 111, y: 110), rs], c(.torso), width: 2.4)
        s.line([ls, neckBase, rs], c(.torso), width: 2.8)
        s.line([neckBase, neckTop], c(.neck), width: 2.6)
        s.circle(h, 10, c(.head), width: 2.4)
        let le = CGPoint(x: ls.x - 9 - elbowOut, y: elbowY), re = CGPoint(x: rs.x + 9 + elbowOut, y: elbowY)
        s.line([ls, le, CGPoint(x: le.x + 9, y: elbowY + 5)], c(.arms), width: 2.4)
        s.line([rs, re, CGPoint(x: re.x - 9, y: elbowY + 5)], c(.arms), width: 2.4)
        s.circle(CGPoint(x: le.x + 10, y: elbowY + 5.5), 1.8, c(.arms), width: 0, fill: c(.arms))
        s.circle(CGPoint(x: re.x - 10, y: elbowY + 5.5), 1.8, c(.arms), width: 0, fill: c(.arms))
    }
}

// MARK: Scenes

enum SetupIllustrations {
    // Viewports for the kinds of scene.
    static let side = CGRect(x: 24, y: 4, width: 156, height: 122)
    static let top = CGRect(x: 12, y: 2, width: 176, height: 122)
    static let front = CGRect(x: 36, y: 6, width: 128, height: 118)
    // The recommended seated position, reused across the side-view scenes.
    static let upright = SidePerson(
        head: CGPoint(x: 57, y: 32), shoulder: CGPoint(x: 54, y: 50), hip: CGPoint(x: 58, y: 88),
        elbow: CGPoint(x: 55, y: 70), hand: CGPoint(x: 80, y: 66),
        knee: CGPoint(x: 94, y: 88), ankle: CGPoint(x: 96, y: 120), toe: CGPoint(x: 106, y: 121), gaze: 16)

    static let deskY: CGFloat = 72

    static func panels(for id: String) -> [IllustrationPanel] {
        switch id {
        case "monitor-height": return monitorHeight
        case "viewing-distance": return viewingDistance
        case "screen-angle": return screenAngle
        case "external-monitor": return externalMonitor
        case "chair-height": return chairHeight
        case "foot-support": return footSupport
        case "desk-height": return deskHeight
        case "keyboard": return keyboard
        case "mouse": return mouse
        case "forearm-support": return forearmSupport
        case "neck-shoulders": return neckShoulders
        case "variation": return variation
        default: return []
        }
    }

    /// Chair, desk and floor for the recommended side view.
    static func room(_ s: Sketch, deskY: CGFloat = deskY, seatY: CGFloat = 91) {
        Furniture.floor(s)
        Furniture.chair(s, seatY: seatY, backTop: CGPoint(x: 37, y: seatY - 45))
        Furniture.desk(s, topY: deskY)
    }

    // MARK: Monitor height

    static let monitorHeight: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Screen too low", caption: "A laptop flat on the desk: the neck bends forward to look down at it.") { s in
            Furniture.floor(s)
            Furniture.chair(s, seatY: 91, backTop: CGPoint(x: 37, y: 46))
            Furniture.desk(s, topY: deskY)
            // Laptop: base on the desk, screen hinged at the back.
            s.line([CGPoint(x: 92, y: deskY - 1.5), CGPoint(x: 120, y: deskY - 1.5)], Sketch.ink, width: 3)
            s.line([CGPoint(x: 120, y: deskY - 2), CGPoint(x: 125, y: deskY - 26)], Sketch.ink, width: 3.6)
            let p = SidePerson(head: CGPoint(x: 76, y: 39), shoulder: CGPoint(x: 64, y: 52), hip: CGPoint(x: 58, y: 88),
                               elbow: CGPoint(x: 64, y: 72), hand: CGPoint(x: 96, y: 68),
                               knee: CGPoint(x: 94, y: 88), ankle: CGPoint(x: 96, y: 120), toe: CGPoint(x: 106, y: 121), gaze: 40)
            s.arrow(p.eye, CGPoint(x: 120, y: deskY - 14), Sketch.bad, dash: [3, 2])
            p.draw(s, highlight: [.neck, .head])
            s.label("neck bent", CGPoint(x: 90, y: 22), Sketch.bad, anchor: .leading)
        },
        IllustrationPanel(kind: .recommended, title: "Top near eye level", caption: "Top of the screen at or slightly below eye level; you look about 15–20° down to its middle.") { s in
            room(s)
            Furniture.keyboard(s, x: 77, deskY: deskY)
            let p = upright
            let m = Furniture.monitor(s, top: CGPoint(x: 132, y: 33), deskY: deskY)
            s.line([CGPoint(x: p.eye.x + 3, y: p.eye.y), CGPoint(x: 176, y: p.eye.y)], Sketch.faint, width: 1, dash: [3, 3])
            s.label("eye level", CGPoint(x: 176, y: p.eye.y - 7), .secondary, anchor: .trailing)
            s.arrow(p.eye, CGPoint(x: m.centre.x - 3, y: m.centre.y), Sketch.good, dash: [3, 2])
            s.arc(p.eye, 24, from: 0, to: 16, Sketch.good)
            s.label("≈15–20°", CGPoint(x: 78, y: 51), Sketch.good, anchor: .leading)
            p.draw(s)
        },
    ]

    // MARK: Viewing distance

    static let viewingDistance: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Leaning in to read", caption: "Moving your head toward the screen instead of enlarging the text.") { s in
            room(s)
            Furniture.keyboard(s, x: 82, deskY: deskY)
            let m = Furniture.monitor(s, top: CGPoint(x: 132, y: 33), deskY: deskY)
            let p = SidePerson(head: CGPoint(x: 100, y: 38), shoulder: CGPoint(x: 80, y: 53), hip: CGPoint(x: 62, y: 88),
                               elbow: CGPoint(x: 80, y: 72), hand: CGPoint(x: 96, y: 67),
                               knee: CGPoint(x: 96, y: 88), ankle: CGPoint(x: 98, y: 120), toe: CGPoint(x: 108, y: 121), gaze: 12)
            s.arrow(CGPoint(x: p.eye.x + 2, y: 18), CGPoint(x: m.top.x - 4, y: 18), Sketch.bad, heads: (true, true))
            s.label("too close", CGPoint(x: (p.eye.x + m.top.x) / 2, y: 11), Sketch.bad)
            p.draw(s, highlight: [.torso, .neck, .head])
        },
        IllustrationPanel(kind: .recommended, title: "About an arm's length", caption: "Sit back against the chair; for most people that's roughly 50–100 cm (20–40 in).") { s in
            room(s)
            Furniture.keyboard(s, x: 77, deskY: deskY)
            let m = Furniture.monitor(s, top: CGPoint(x: 132, y: 33), deskY: deskY)
            let p = upright
            s.arrow(CGPoint(x: p.eye.x + 2, y: 16), CGPoint(x: m.top.x - 4, y: 16), Sketch.good, heads: (true, true))
            s.line([CGPoint(x: p.eye.x + 2, y: 13), CGPoint(x: p.eye.x + 2, y: p.eye.y - 3)], Sketch.faint, width: 1, dash: [2, 2])
            s.line([CGPoint(x: m.top.x - 4, y: 13), CGPoint(x: m.top.x - 4, y: m.top.y - 2)], Sketch.faint, width: 1, dash: [2, 2])
            s.label("roughly 50–100 cm", CGPoint(x: (p.eye.x + m.top.x) / 2, y: 8), Sketch.good)
            p.draw(s)
        },
    ]

    // MARK: Screen angle and glare

    /// Top view of a desk against the far wall; the person at the bottom.
    static func glareRoom(_ s: Sketch, window: (CGPoint, CGPoint)) {
        s.rect(CGRect(x: 10, y: 6, width: 180, height: 118), Sketch.faint, width: 1.2, corner: 2)
        s.line([window.0, window.1], Sketch.furniture, width: 5)
    }

    static let screenAngle: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Window behind you", caption: "Daylight from behind reflects off the screen into your eyes (seen from above).", viewport: CGRect(x: 6, y: 2, width: 188, height: 126)) { s in
            glareRoom(s, window: (CGPoint(x: 60, y: 124), CGPoint(x: 140, y: 124)))
            s.label("window", CGPoint(x: 100, y: 113), .secondary)
            s.rect(CGRect(x: 55, y: 18, width: 90, height: 26), Sketch.furniture, width: 1.3, fill: Sketch.faint.opacity(0.25), corner: 2)
            TopView.monitor(s, at: CGPoint(x: 100, y: 30), width: 48)
            TopView.person(s, at: CGPoint(x: 100, y: 70))
            for x in [76.0, 124.0] {
                s.arrow(CGPoint(x: x, y: 110), CGPoint(x: x + (100 - x) * 0.35, y: 36), Sketch.bad, width: 1.3, dash: [3, 2])
                s.arrow(CGPoint(x: x + (100 - x) * 0.35, y: 36), CGPoint(x: x + (100 - x) * 0.8, y: 64), Sketch.bad, width: 1.3, dash: [3, 2])
            }
            s.label("reflection", CGPoint(x: 150, y: 54), Sketch.bad)
        },
        IllustrationPanel(kind: .recommended, title: "Side-on to the window", caption: "Screen at a right angle to the window, so daylight passes across it.", viewport: CGRect(x: 6, y: 2, width: 188, height: 126)) { s in
            glareRoom(s, window: (CGPoint(x: 10, y: 30), CGPoint(x: 10, y: 100)))
            s.label("window", CGPoint(x: 18, y: 112), .secondary, anchor: .leading)
            s.rect(CGRect(x: 70, y: 18, width: 90, height: 26), Sketch.furniture, width: 1.3, fill: Sketch.faint.opacity(0.25), corner: 2)
            TopView.monitor(s, at: CGPoint(x: 115, y: 30), width: 48)
            TopView.person(s, at: CGPoint(x: 115, y: 70))
            for y in [54.0, 92.0] {
                s.arrow(CGPoint(x: 16, y: y), CGPoint(x: 70, y: y), Sketch.good, width: 1.3, dash: [3, 2])
            }
        },
        IllustrationPanel(kind: .recommended, title: "Tilted back slightly", caption: "Tilt the screen back a little, often about 10–20°; tilt less if it picks up ceiling lights.", viewport: CGRect(x: 16, y: 14, width: 172, height: 100)) { s in
            Furniture.floor(s)
            Furniture.desk(s, topY: 92, x0: 70, x1: 190)
            let top = CGPoint(x: 128, y: 30)
            let m = Furniture.monitor(s, top: top, height: 52, tilt: 15, deskY: 92)
            s.line([top, CGPoint(x: top.x, y: m.bottom.y + 2)], Sketch.faint, width: 1, dash: [3, 3])
            s.arc(top, 42, from: 90, to: 105, Sketch.good, width: 2)
            s.label("≈10–20°", CGPoint(x: 134, y: 74), Sketch.good, anchor: .leading)
            let eye = CGPoint(x: 42, y: 40)
            s.circle(CGPoint(x: 37, y: 41), 8.5, Sketch.ink, width: 2.4)
            s.circle(eye, 1.2, Sketch.ink, width: 0, fill: Sketch.ink)
            s.arrow(CGPoint(x: eye.x + 3, y: eye.y + 2), CGPoint(x: m.centre.x - 4, y: m.centre.y - 2), Sketch.good, dash: [3, 2])
        },
    ]

    // MARK: External monitors

    static let externalMonitor: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Main screen off to the side", caption: "Working for hours on a screen to one side keeps your neck turned.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 58, y: 34), width: 50, angle: -20, color: Sketch.bad)
            TopView.monitor(s, at: CGPoint(x: 128, y: 28), width: 50)
            TopView.keyboard(s, at: CGPoint(x: 100, y: 70))
            TopView.person(s, at: CGPoint(x: 100, y: 106), facing: -135, color: Sketch.ink)
            s.arrow(CGPoint(x: 92, y: 98), CGPoint(x: 66, y: 48), Sketch.bad, width: 1.3, dash: [3, 2])
            s.label("main screen", CGPoint(x: 52, y: 8), Sketch.bad)
        },
        IllustrationPanel(kind: .recommended, title: "Main screen centred", caption: "The screen you use most straight ahead, in line with the keyboard; a second one to the side, angled in.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 100, y: 28), width: 54, color: Sketch.good)
            TopView.monitor(s, at: CGPoint(x: 156, y: 36), width: 40, angle: 25)
            TopView.keyboard(s, at: CGPoint(x: 100, y: 70))
            TopView.person(s, at: CGPoint(x: 100, y: 106))
            s.line([CGPoint(x: 100, y: 34), CGPoint(x: 100, y: 95)], Sketch.good, width: 1, dash: [3, 3])
            s.label("main", CGPoint(x: 100, y: 8), Sketch.good)
            s.label("secondary", CGPoint(x: 160, y: 8), .secondary)
        },
        IllustrationPanel(kind: .recommended, title: "Two used equally", caption: "Edges touching, the seam in front of you, both angled in slightly at about the same height.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 76, y: 32), width: 50, angle: -12, color: Sketch.good)
            TopView.monitor(s, at: CGPoint(x: 124, y: 32), width: 50, angle: 12, color: Sketch.good)
            TopView.keyboard(s, at: CGPoint(x: 100, y: 70))
            TopView.person(s, at: CGPoint(x: 100, y: 106))
            s.line([CGPoint(x: 100, y: 30), CGPoint(x: 100, y: 95)], Sketch.good, width: 1, dash: [3, 3])
            s.label("seam centred on you", CGPoint(x: 100, y: 8), Sketch.good)
        },
    ]

    // MARK: Chair

    static let chairHeight: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Perched forward", caption: "Sitting on the front of the seat leaves your back unsupported.") { s in
            room(s)
            Furniture.keyboard(s, x: 84, deskY: deskY)
            let p = SidePerson(head: CGPoint(x: 80, y: 34), shoulder: CGPoint(x: 74, y: 52), hip: CGPoint(x: 72, y: 88),
                               elbow: CGPoint(x: 76, y: 72), hand: CGPoint(x: 96, y: 67),
                               knee: CGPoint(x: 104, y: 90), ankle: CGPoint(x: 100, y: 120), toe: CGPoint(x: 110, y: 121), gaze: 12)
            s.arrow(CGPoint(x: 44, y: 66), CGPoint(x: 66, y: 66), Sketch.bad, width: 1.3, heads: (true, true))
            s.label("no back support", CGPoint(x: 28, y: 16), Sketch.bad, anchor: .leading)
            p.draw(s, highlight: [.torso])
        },
        IllustrationPanel(kind: .recommended, title: "Back supported, feet flat", caption: "Feet flat, thighs roughly level, knees about hip height; a slight recline (roughly 100–110°) is fine.") { s in
            room(s)
            Furniture.keyboard(s, x: 77, deskY: deskY)
            let p = upright
            // Lower-back support and the hip-to-knee line.
            s.line([CGPoint(x: 43, y: 82), CGPoint(x: 47, y: 74), CGPoint(x: 44, y: 66)], Sketch.good, width: 3.4)
            s.circle(p.knee, 2.6, Sketch.good, width: 0, fill: Sketch.good)
            s.label("knees ≈ hip height", CGPoint(x: 101, y: 99), Sketch.good, anchor: .leading)
            s.arc(p.hip, 12, from: -96, to: 0, Sketch.good, width: 1.4)
            s.label("≈100–110°", CGPoint(x: 72, y: 79), Sketch.good, anchor: .leading)
            p.draw(s)
        },
    ]

    static let footSupport: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Feet dangling", caption: "A chair raised to suit the desk can leave your feet off the floor.") { s in
            Furniture.floor(s)
            Furniture.chair(s, seatY: 84, backTop: CGPoint(x: 37, y: 40))
            Furniture.desk(s, topY: 66)
            let p = SidePerson(head: CGPoint(x: 57, y: 25), shoulder: CGPoint(x: 54, y: 43), hip: CGPoint(x: 58, y: 81),
                               elbow: CGPoint(x: 55, y: 63), hand: CGPoint(x: 80, y: 60),
                               knee: CGPoint(x: 94, y: 81), ankle: CGPoint(x: 97, y: 110), toe: CGPoint(x: 104, y: 113), gaze: 12)
            s.arrow(CGPoint(x: 116, y: 113), CGPoint(x: 116, y: 123), Sketch.bad, width: 1.3, heads: (true, true))
            s.label("gap", CGPoint(x: 120, y: 118), Sketch.bad, anchor: .leading)
            p.draw(s, highlight: [.legs])
        },
        IllustrationPanel(kind: .recommended, title: "Footrest", caption: "Both feet supported, on the floor or a footrest (a sturdy box works).") { s in
            Furniture.floor(s)
            Furniture.chair(s, seatY: 84, backTop: CGPoint(x: 37, y: 40))
            Furniture.desk(s, topY: 66)
            s.rect(CGRect(x: 88, y: 113, width: 30, height: 11), Sketch.good, width: 1.6, fill: Sketch.good.opacity(0.15))
            let p = SidePerson(head: CGPoint(x: 57, y: 25), shoulder: CGPoint(x: 54, y: 43), hip: CGPoint(x: 58, y: 81),
                               elbow: CGPoint(x: 55, y: 63), hand: CGPoint(x: 80, y: 60),
                               knee: CGPoint(x: 94, y: 81), ankle: CGPoint(x: 96, y: 111), toe: CGPoint(x: 106, y: 112), gaze: 12)
            s.label("footrest", CGPoint(x: 122, y: 118), Sketch.good, anchor: .leading)
            p.draw(s)
        },
    ]

    // MARK: Desk

    static let deskHeight: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Desk too high", caption: "Reaching up to the keys lifts the shoulders and bends the wrists.") { s in
            Furniture.floor(s)
            Furniture.chair(s, seatY: 91, backTop: CGPoint(x: 37, y: 46))
            Furniture.desk(s, topY: 60)
            Furniture.keyboard(s, x: 80, deskY: 60)
            let p = SidePerson(head: CGPoint(x: 57, y: 29), shoulder: CGPoint(x: 55, y: 46), hip: CGPoint(x: 58, y: 88),
                               elbow: CGPoint(x: 62, y: 66), hand: CGPoint(x: 84, y: 55),
                               knee: CGPoint(x: 94, y: 88), ankle: CGPoint(x: 96, y: 120), toe: CGPoint(x: 106, y: 121), gaze: 10)
            s.label("shoulders up", CGPoint(x: 26, y: 12), Sketch.bad, anchor: .leading)
            s.arrow(CGPoint(x: 48, y: 50), CGPoint(x: 48, y: 42), Sketch.bad, width: 1.3)
            p.draw(s, highlight: [.arms])
        },
        IllustrationPanel(kind: .recommended, title: "Keys at elbow height", caption: "Shoulders relaxed, elbows bent at roughly 90–120°, forearms about level.") { s in
            room(s)
            Furniture.keyboard(s, x: 77, deskY: deskY, color: Sketch.good)
            let p = upright
            s.line([CGPoint(x: p.elbow.x - 8, y: p.elbow.y), CGPoint(x: 112, y: p.elbow.y)], Sketch.good, width: 1, dash: [3, 3])
            s.label("elbow height", CGPoint(x: 178, y: p.elbow.y + 14), Sketch.good, anchor: .trailing)
            let up = atan2(p.shoulder.y - p.elbow.y, p.shoulder.x - p.elbow.x) * 180 / .pi
            let fore = atan2(p.hand.y - p.elbow.y, p.hand.x - p.elbow.x) * 180 / .pi
            s.arc(p.elbow, 9, from: up, to: fore, Sketch.good, width: 1.6)
            s.label("≈90–120°", CGPoint(x: 68, y: 52), Sketch.good, anchor: .leading)
            p.draw(s)
        },
    ]

    // MARK: Keyboard

    static let keyboard: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Far away or off-centre", caption: "Reaching forward or sideways to type, seen from above.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 100, y: 24), width: 54)
            TopView.keyboard(s, at: CGPoint(x: 130, y: 44), color: Sketch.bad)
            TopView.person(s, at: CGPoint(x: 100, y: 106))
            TopView.arms(s, person: CGPoint(x: 100, y: 106), left: CGPoint(x: 116, y: 50), right: CGPoint(x: 144, y: 50))
            s.line([CGPoint(x: 100, y: 36), CGPoint(x: 100, y: 95)], Sketch.faint, width: 1, dash: [3, 3])
        },
        IllustrationPanel(kind: .recommended, title: "Close and centred", caption: "Letter keys centred on you, close enough that your elbows stay near your sides.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 100, y: 24), width: 54)
            TopView.keyboard(s, at: CGPoint(x: 100, y: 74), color: Sketch.good)
            TopView.person(s, at: CGPoint(x: 100, y: 108))
            TopView.arms(s, person: CGPoint(x: 100, y: 108), left: CGPoint(x: 88, y: 80), right: CGPoint(x: 112, y: 80))
            s.line([CGPoint(x: 100, y: 36), CGPoint(x: 100, y: 97)], Sketch.good, width: 1, dash: [3, 3])
        },
        IllustrationPanel(kind: .recommended, title: "Wrists roughly straight", caption: "A flat keyboard (feet folded) often helps; avoid pressing wrists on a hard edge.", viewport: CGRect(x: 14, y: 38, width: 176, height: 66)) { s in
            Furniture.desk(s, topY: 88, x0: 14, x1: 210)
            // A flat keyboard.
            s.shape([CGPoint(x: 96, y: 88), CGPoint(x: 160, y: 88), CGPoint(x: 160, y: 83), CGPoint(x: 96, y: 84.5)], Sketch.furniture, width: 1.3, fill: Sketch.faint.opacity(0.5))
            // Forearm, then the hand, in one line over the keys.
            s.shape([CGPoint(x: 18, y: 64), CGPoint(x: 100, y: 70), CGPoint(x: 100, y: 78), CGPoint(x: 18, y: 78)], Sketch.ink, width: 2, fill: Sketch.ink.opacity(0.12))
            s.shape([CGPoint(x: 100, y: 70), CGPoint(x: 128, y: 72), CGPoint(x: 142, y: 78), CGPoint(x: 144, y: 82), CGPoint(x: 130, y: 81), CGPoint(x: 100, y: 78)], Sketch.ink, width: 2, fill: Sketch.ink.opacity(0.12))
            s.line([CGPoint(x: 18, y: 59), CGPoint(x: 132, y: 66.5)], Sketch.good, width: 1.2, dash: [3, 3])
            s.label("forearm, wrist and hand in line", CGPoint(x: 18, y: 48), Sketch.good, anchor: .leading)
            s.line([CGPoint(x: 100, y: 79), CGPoint(x: 100, y: 96)], Sketch.faint, width: 1)
            s.label("wrist", CGPoint(x: 104, y: 97), .secondary, anchor: .leading)
        },
    ]

    // MARK: Mouse

    static let mouse: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Mouse far out", caption: "A wide keyboard pushes the mouse out, so the arm reaches to the side.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 100, y: 24), width: 54)
            TopView.keyboard(s, at: CGPoint(x: 108, y: 72), width: 58, numpad: true)
            TopView.mouse(s, at: CGPoint(x: 162, y: 72), color: Sketch.bad)
            TopView.person(s, at: CGPoint(x: 100, y: 108))
            TopView.arms(s, person: CGPoint(x: 100, y: 108), left: CGPoint(x: 90, y: 78), right: CGPoint(x: 158, y: 78))
            s.line([CGPoint(x: 115, y: 114), CGPoint(x: 158, y: 78)], Sketch.bad, width: 2.2)
        },
        IllustrationPanel(kind: .recommended, title: "Right beside the keyboard", caption: "Mouse next to the keys at the same height, used with the elbow near your side.", viewport: top) { s in
            TopView.desk(s)
            TopView.monitor(s, at: CGPoint(x: 100, y: 24), width: 54)
            TopView.keyboard(s, at: CGPoint(x: 96, y: 74))
            TopView.mouse(s, at: CGPoint(x: 126, y: 74), color: Sketch.good)
            TopView.person(s, at: CGPoint(x: 100, y: 108))
            TopView.arms(s, person: CGPoint(x: 100, y: 108), left: CGPoint(x: 86, y: 80), right: CGPoint(x: 124, y: 80))
            s.line([CGPoint(x: 115, y: 114), CGPoint(x: 124, y: 80)], Sketch.good, width: 2.2)
        },
    ]

    // MARK: Forearms

    static func frontChair(_ s: Sketch, armrestY: CGFloat) {
        s.rect(CGRect(x: 76, y: 44, width: 48, height: 66), Sketch.faint, width: 1.4, fill: Sketch.faint.opacity(0.2), corner: 6)
        s.line([CGPoint(x: 56, y: armrestY), CGPoint(x: 74, y: armrestY)], Sketch.furniture, width: 3.4)
        s.line([CGPoint(x: 126, y: armrestY), CGPoint(x: 144, y: armrestY)], Sketch.furniture, width: 3.4)
        s.line([CGPoint(x: 66, y: armrestY), CGPoint(x: 70, y: 112)], Sketch.furniture, width: 1.6)
        s.line([CGPoint(x: 134, y: armrestY), CGPoint(x: 130, y: 112)], Sketch.furniture, width: 1.6)
    }

    static let forearmSupport: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Shoulders holding the arms up", caption: "No support, or armrests set too high: the shoulders lift and the elbows go out.", viewport: front) { s in
            frontChair(s, armrestY: 80)
            let f = FrontPerson(shoulderY: 58, lift: 10, elbowOut: 4, elbowY: 77)
            f.draw(s, highlight: [.torso])
            s.arrow(CGPoint(x: 66, y: 60), CGPoint(x: 66, y: 47), Sketch.bad, width: 1.4)
            s.arrow(CGPoint(x: 134, y: 60), CGPoint(x: 134, y: 47), Sketch.bad, width: 1.4)
            s.label("armrests too high", CGPoint(x: 100, y: 120), Sketch.bad)
        },
        IllustrationPanel(kind: .recommended, title: "Forearms supported", caption: "Forearms rest on low armrests or the desk; the shoulders stay down and relaxed.", viewport: front) { s in
            frontChair(s, armrestY: 92)
            let f = FrontPerson(shoulderY: 58, elbowY: 89.5)
            f.draw(s)
            s.line([CGPoint(x: 56, y: 92), CGPoint(x: 74, y: 92)], Sketch.good, width: 3.4)
            s.line([CGPoint(x: 126, y: 92), CGPoint(x: 144, y: 92)], Sketch.good, width: 3.4)
            s.label("shoulders down, forearms resting", CGPoint(x: 100, y: 120), Sketch.good)
        },
    ]

    // MARK: Neck and shoulders

    static let neckShoulders: [IllustrationPanel] = [
        IllustrationPanel(kind: .mistake, title: "Phone held on the shoulder", caption: "Cradling a phone tilts the head and hitches one shoulder up.", viewport: front) { s in
            let f = FrontPerson(headY: 32, headTilt: 24, shoulderY: 62, rightLift: 9, elbowY: 98)
            f.draw(s, highlight: [.neck, .head])
            let h = f.headCentre, rs = f.rightShoulder
            let mid = CGPoint(x: (h.x + rs.x) / 2 + 3, y: (h.y + rs.y) / 2 + 1)
            s.shape(TopView.box(mid, w: 7, h: 20, angle: -40), Sketch.bad, width: 1.6, fill: Sketch.bad.opacity(0.3))
        },
        IllustrationPanel(kind: .recommended, title: "Headset for calls", caption: "A headset or speaker keeps the head level and both shoulders down.", viewport: front) { s in
            let f = FrontPerson(headY: 32, shoulderY: 62, elbowY: 98)
            f.draw(s)
            let h = f.headCentre
            s.arc(h, 13, from: 180, to: 360, Sketch.good, width: 2.2)
            s.rect(CGRect(x: h.x - 16, y: h.y - 4, width: 5, height: 10), Sketch.good, width: 1.4, fill: Sketch.good.opacity(0.3))
            s.rect(CGRect(x: h.x + 11, y: h.y - 4, width: 5, height: 10), Sketch.good, width: 1.4, fill: Sketch.good.opacity(0.3))
            s.line([CGPoint(x: h.x - 13, y: h.y + 6), CGPoint(x: h.x - 8, y: h.y + 13)], Sketch.good, width: 1.4)
        },
        IllustrationPanel(kind: .recommended, title: "Documents beside the screen", caption: "Papers you read often go next to the screen at about the same height, not flat on the desk.", viewport: CGRect(x: 10, y: 8, width: 180, height: 108)) { s in
            Furniture.floor(s, y: 112, x0: 14, x1: 186)
            s.rect(CGRect(x: 14, y: 92, width: 172, height: 4), Sketch.furniture, width: 1.4, fill: Sketch.faint.opacity(0.4))
            // Screen, front view.
            s.rect(CGRect(x: 52, y: 30, width: 76, height: 46), Sketch.ink, width: 2.2, corner: 3)
            s.line([CGPoint(x: 90, y: 76), CGPoint(x: 90, y: 92)], Sketch.furniture, width: 2.2)
            s.line([CGPoint(x: 78, y: 91), CGPoint(x: 102, y: 91)], Sketch.furniture, width: 2.4)
            // Document holder at the same height.
            s.rect(CGRect(x: 138, y: 34, width: 30, height: 40), Sketch.good, width: 1.8, fill: Sketch.good.opacity(0.12), corner: 2)
            for i in 0..<5 { s.line([CGPoint(x: 143, y: 42 + CGFloat(i) * 6), CGPoint(x: 163, y: 42 + CGFloat(i) * 6)], Sketch.good.opacity(0.6), width: 1) }
            s.line([CGPoint(x: 153, y: 74), CGPoint(x: 153, y: 92)], Sketch.furniture, width: 1.6)
            s.line([CGPoint(x: 40, y: 30), CGPoint(x: 176, y: 30)], Sketch.good, width: 1, dash: [3, 3])
            s.label("same height", CGPoint(x: 153, y: 22), Sketch.good)
        },
    ]

    // MARK: Varying position

    static let variation: [IllustrationPanel] = [
        IllustrationPanel(kind: .recommended, title: "Change position often", caption: "Sit, stand and move in turns through the day. Short breaks every half hour or so matter more than one perfect posture.", viewport: CGRect(x: 0, y: 0, width: 400, height: 126)) { s in
            Furniture.floor(s, y: 92, x0: 10, x1: 390)
            // Sitting.
            Furniture.chair(s, seatY: 66, seatX0: 34, seatX1: 72, backTop: CGPoint(x: 30, y: 28), floorY: 92)
            SidePerson(head: CGPoint(x: 50, y: 14), shoulder: CGPoint(x: 47, y: 30), hip: CGPoint(x: 50, y: 63),
                       elbow: CGPoint(x: 49, y: 47), hand: CGPoint(x: 68, y: 45),
                       knee: CGPoint(x: 80, y: 63), ankle: CGPoint(x: 82, y: 90), toe: CGPoint(x: 90, y: 91), headR: 7.5).draw(s)
            // Standing.
            SidePerson(head: CGPoint(x: 200, y: 10), shoulder: CGPoint(x: 199, y: 26), hip: CGPoint(x: 199, y: 58),
                       elbow: CGPoint(x: 200, y: 42), hand: CGPoint(x: 206, y: 56),
                       knee: CGPoint(x: 200, y: 75), ankle: CGPoint(x: 199, y: 90), toe: CGPoint(x: 207, y: 91), headR: 7.5).draw(s)
            // Walking.
            let w = SidePerson(head: CGPoint(x: 336, y: 10), shoulder: CGPoint(x: 334, y: 26), hip: CGPoint(x: 332, y: 58),
                               elbow: CGPoint(x: 342, y: 40), hand: CGPoint(x: 350, y: 50),
                               knee: CGPoint(x: 344, y: 74), ankle: CGPoint(x: 352, y: 90), toe: CGPoint(x: 360, y: 91), headR: 7.5)
            s.line([CGPoint(x: 332, y: 58), CGPoint(x: 324, y: 75), CGPoint(x: 314, y: 88), CGPoint(x: 320, y: 91)], Sketch.ink, width: 2.6)
            s.line([CGPoint(x: 334, y: 26), CGPoint(x: 326, y: 40), CGPoint(x: 320, y: 50)], Sketch.ink, width: 2.4)
            w.draw(s)
            s.arrow(CGPoint(x: 104, y: 50), CGPoint(x: 172, y: 50), Sketch.good, dash: [4, 3])
            s.arrow(CGPoint(x: 232, y: 50), CGPoint(x: 296, y: 50), Sketch.good, dash: [4, 3])
            s.label("sit", CGPoint(x: 55, y: 104), .secondary)
            s.label("stand", CGPoint(x: 200, y: 104), .secondary)
            s.label("move", CGPoint(x: 336, y: 104), .secondary)
            s.label("change every half hour or so", CGPoint(x: 200, y: 119), Sketch.good)
        },
    ]
}
