import SwiftUI

/// Minimal SVG path reader (M L H V C S Z, absolute and relative) so the agents' hair and faces stay the same shapes as their portraits.
enum SVG {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Path] = [:]
    /// Parsed once: the agents are drawn many times a second and the same few hundred strings come up each time.
    static func path(_ d: String) -> Path {
        lock.lock(); let hit = cache[d]; lock.unlock()
        if let hit { return hit }
        let p = parse(d)
        lock.lock(); cache[d] = p; lock.unlock()
        return p
    }
    private static func parse(_ d: String) -> Path {
        let tokens = d.matches(of: /[a-zA-Z]|-?\d*\.?\d+/).map { String($0.0) }
        var p = Path(), i = 0, cmd: Character = "M", cur = CGPoint.zero, start = CGPoint.zero, lastCtl: CGPoint?
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = c; i += 1; if c == "z" || c == "Z" { p.closeSubpath(); cur = start; lastCtl = nil; continue } }
            let rel = cmd.isLowercase
            let o = rel ? cur : .zero
            switch cmd.uppercased() {
            case "M": cur = CGPoint(x: o.x + num(), y: o.y + num()); start = cur; p.move(to: cur); cmd = rel ? "l" : "L"; lastCtl = nil
            case "L": cur = CGPoint(x: o.x + num(), y: o.y + num()); p.addLine(to: cur); lastCtl = nil
            case "H": cur = CGPoint(x: (rel ? cur.x : 0) + num(), y: cur.y); p.addLine(to: cur); lastCtl = nil
            case "V": cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + num()); p.addLine(to: cur); lastCtl = nil
            case "C":
                let c1 = CGPoint(x: o.x + num(), y: o.y + num()), c2 = CGPoint(x: o.x + num(), y: o.y + num()), e = CGPoint(x: o.x + num(), y: o.y + num())
                p.addCurve(to: e, control1: c1, control2: c2); lastCtl = c2; cur = e
            case "S":
                let c1 = lastCtl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + num(), y: o.y + num()), e = CGPoint(x: o.x + num(), y: o.y + num())
                p.addCurve(to: e, control1: c1, control2: c2); lastCtl = c2; cur = e
            default: i += 1
            }
        }
        return p
    }
}

/// What an agent is doing with its body right now.
enum Doing { case type, read, sip, stand, walk, reach, stretch, talk, present, water, look, file, dig }   // file: putting a sheet away on a shelf; dig: rummaging in the Unsorted bin
/// What it is holding.
enum Carry { case none, book, openBook, paper, can }

/// A full-body line-art agent, drawn in a 96×232 design space with the hip at (48, 150). Same face, hair and cap as its portrait.
/// Seated agents' arms are a separate layer so they can be drawn in front of the desk.
struct Rig {
    enum Layer { case all, body, arms }
    static let design = CGSize(width: 96, height: 232)
    let id: String
    var course: String? = nil  // the course code for a course agent (looked up once, not per drawing call)
    var seat = 1.0             // 1 seated … 0 standing
    var doing = Doing.stand
    var carry = Carry.none
    var walk = 0.0             // walking phase in radians
    var facing = 1.0           // -1 mirrors the figure
    var hover = false, busy = false
    var lounge = false         // sitting on a sofa or armchair: no desk hides the legs
    let t: Double

    var seated: Bool { seat > 0.5 }
    var ink: GraphicsContext.Shading { .color(Color.ink) }
    var paper: GraphicsContext.Shading { .color(Color.card) }
    var shirt: GraphicsContext.Shading { .color(Agent.color(id).opacity(0.42)) }
    func wave(_ speed: Double, _ amp: Double, _ shift: Double = 0) -> Double { sin(t * speed + shift) * amp }

    // Two-bone arm: the elbow for a shoulder→hand reach (both bones 36 long), bending outwards.
    func elbow(_ s: CGPoint, _ h: CGPoint, outward: Double) -> CGPoint {
        let l = 36.0, dx = h.x - s.x, dy = h.y - s.y, len = max(hypot(dx, dy), 1), d = min(len, 2 * l - 0.5)
        let a = d / 2, hgt = sqrt(max(l * l - a * a, 0))
        let mx = s.x + dx / len * a, my = s.y + dy / len * a
        let nx = -dy / len, ny = dx / len
        let sign = (nx * outward >= 0 ? 1.0 : -1.0)
        return CGPoint(x: mx + nx * hgt * sign, y: my + ny * hgt * sign)
    }

    func tube(_ c: inout GraphicsContext, _ pts: [CGPoint], width: CGFloat = 9, fill: GraphicsContext.Shading? = nil) {
        var p = Path(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }
        c.stroke(p, with: ink, style: StrokeStyle(lineWidth: width + 3.4, lineCap: .round, lineJoin: .round))
        c.stroke(p, with: paper, style: StrokeStyle(lineWidth: width - 1.4, lineCap: .round, lineJoin: .round))
        if let fill { c.stroke(p, with: fill, style: StrokeStyle(lineWidth: width - 1.4, lineCap: .round, lineJoin: .round)) }
    }
    func arm(_ c: inout GraphicsContext, shoulder: CGPoint, hand: CGPoint, outward: Double) {
        tube(&c, [shoulder, elbow(shoulder, hand, outward: outward), hand], fill: shirt)
        let h = Path(ellipseIn: CGRect(x: hand.x - 5.5, y: hand.y - 5.5, width: 11, height: 11))
        c.fill(h, with: paper); c.stroke(h, with: ink, lineWidth: 2.6)
    }

    // MARK: Props, drawn at the hands
    func closedBook(_ c: inout GraphicsContext, at p: CGPoint, tilt: Double = 0) {
        var b = c; b.translateBy(x: p.x, y: p.y); b.rotate(by: .degrees(tilt))
        let r = Path(roundedRect: CGRect(x: -14, y: -12, width: 28, height: 24), cornerRadius: 3)
        b.fill(r, with: .color(Color.course(course ?? "MSOA").opacity(0.55))); b.stroke(r, with: ink, lineWidth: 2.4)
        b.stroke(SVG.path("M-8 -12v24"), with: ink, lineWidth: 1.6)
        for y in [-5.0, 1, 7] { b.stroke(SVG.path("M-2 \(y)h9"), with: ink, lineWidth: 1.3) }
    }
    func openBook(_ c: inout GraphicsContext, at p: CGPoint, tilt: Double = 0) {
        var b = c; b.translateBy(x: p.x, y: p.y); b.rotate(by: .degrees(tilt))
        let l = Path(roundedRect: CGRect(x: -20, y: -13, width: 20, height: 26), cornerRadius: 2), r = Path(roundedRect: CGRect(x: 0, y: -13, width: 20, height: 26), cornerRadius: 2)
        b.fill(l, with: paper); b.fill(r, with: paper); b.stroke(l, with: ink, lineWidth: 2.2); b.stroke(r, with: ink, lineWidth: 2.2)
        for y in [-6.0, 0, 6] { b.stroke(SVG.path("M-16 \(y)h12M4 \(y)h12"), with: ink, lineWidth: 1.2) }
    }
    func paperSheet(_ c: inout GraphicsContext, at p: CGPoint, tilt: Double = 0) {
        var b = c; b.translateBy(x: p.x, y: p.y); b.rotate(by: .degrees(tilt))
        let r = Path(roundedRect: CGRect(x: -14, y: -40, width: 28, height: 38), cornerRadius: 2)
        b.fill(r, with: paper); b.stroke(r, with: ink, lineWidth: 2.4)
        for y in [-29.0, -22, -15, -8] { b.stroke(SVG.path("M-8 \(y)h16"), with: ink, lineWidth: 1.4) }
        b.fill(Path(roundedRect: CGRect(x: -14, y: -40, width: 28, height: 8), cornerRadius: 2), with: .color(Color.ink.opacity(0.18)))
    }
    func wateringCan(_ c: inout GraphicsContext, at p: CGPoint) {
        var b = c; b.translateBy(x: p.x, y: p.y); b.rotate(by: .degrees(-18 + wave(1.2, 4)))
        let body = Path(roundedRect: CGRect(x: -12, y: -10, width: 24, height: 20), cornerRadius: 4)
        b.fill(body, with: paper); b.stroke(body, with: ink, lineWidth: 2.4)
        b.stroke(SVG.path("M-12 -2l-12 -10M12 -6h14"), with: ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        b.stroke(SVG.path("M-8 -10c0 -10 16 -10 16 0"), with: ink, lineWidth: 2.2)
    }
    func mug(_ c: inout GraphicsContext, at p: CGPoint) {
        let r = Path(roundedRect: CGRect(x: p.x - 7, y: p.y - 8, width: 14, height: 14), cornerRadius: 3)
        c.fill(r, with: paper); c.stroke(r, with: ink, lineWidth: 2.2)
        c.stroke(SVG.path("M\(p.x + 7) \(p.y - 4)c6 0 6 8 0 8"), with: ink, lineWidth: 2)
    }

    // MARK: Drawing
    func draw(_ c0: GraphicsContext, layer: Layer) {
        var c = c0
        if facing < 0 { c.translateBy(x: 96, y: 0); c.scaleBy(x: -1, y: 1) }
        let sL = CGPoint(x: 30, y: 96), sR = CGPoint(x: 66, y: 96)
        let breathe = 1 + 0.014 * sin(t * 1.7)
        let moving = doing == .walk
        let stride = sin(walk)

        if layer != .arms {
            if !seated || lounge {   // legs and shoes (shorter on a sofa, where the hip is low)
                for (i, x) in [38.0, 58.0].enumerated() {
                    let s = (i == 0 ? 1.0 : -1.0) * (moving ? stride : 0), l = moving ? max(0, (i == 0 ? 1.0 : -1.0) * cos(walk)) : 0
                    let foot = CGPoint(x: x + s * 8 + (x < 48 ? -1 : 1), y: (seated ? 182 : 208) - l * 7)
                    tube(&c, [CGPoint(x: x, y: 150), foot], width: 12, fill: .color(Color.ink.opacity(0.1)))
                    c.fill(Path(roundedRect: CGRect(x: foot.x - 11 + (x < 48 ? -3 : 3), y: foot.y, width: 22, height: 11), cornerRadius: 5.5), with: ink)
                }
            }
            var tc = c
            tc.translateBy(x: 48, y: 150); tc.scaleBy(x: 1, y: breathe); tc.translateBy(x: -48, y: -150)
            let torso = SVG.path("M30 88Q48 80 66 88C74 92 77 118 75 152L21 152C19 118 22 92 30 88Z")
            tc.fill(torso, with: paper); tc.fill(torso, with: shirt)
            tc.stroke(torso, with: ink, style: StrokeStyle(lineWidth: 3.2, lineJoin: .round))
            tc.stroke(SVG.path("M40 83l8 13 8-13"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            drawChest(&tc)
            drawHead(&c)
            if busy { thought(&c) }
        }
        if layer != .body { drawArms(&c, sL, sR, stride) }
    }

    /// Clothes that tell agents apart, then a name tag on a lanyard (its text is kept the right way round when the figure faces left).
    func drawChest(_ tc: inout GraphicsContext) {
        let look = Look.of(id), accent = Agent.color(id), ex = look.extras
        if ex.contains("scarf") {
            let sc = Path(roundedRect: CGRect(x: 31, y: 85, width: 34, height: 10), cornerRadius: 5)
            tc.fill(sc, with: .color(accent.opacity(0.9))); tc.stroke(sc, with: ink, lineWidth: 2.4)
            tc.stroke(SVG.path("M58 93l3 12"), with: .color(accent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        if ex.contains("bowtie") {
            let b = SVG.path("M48 91l-10-5v10zM48 91l10-5v10z")
            tc.fill(b, with: .color(accent)); tc.stroke(b, with: ink, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        if ex.contains("calculator") {   // a pocket calculator in the breast pocket
            let body = Path(roundedRect: CGRect(x: 30, y: 119, width: 15, height: 20), cornerRadius: 2.5)
            tc.fill(body, with: .color(accent.opacity(0.25))); tc.stroke(body, with: ink, lineWidth: 2)
            tc.stroke(SVG.path("M33 123h9"), with: ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            for r in 0..<3 { for c in 0..<3 { tc.fill(Path(ellipseIn: CGRect(x: 32.2 + CGFloat(c) * 4.2, y: 128 + CGFloat(r) * 3.6, width: 2, height: 2)), with: ink) } }
        }
        if ex.contains("magnifier") {   // a magnifying glass on a cord
            tc.stroke(SVG.path("M44 86L58 118"), with: ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            let lens = Path(ellipseIn: CGRect(x: 53, y: 117, width: 14, height: 14))
            tc.fill(lens, with: .color(accent.opacity(0.25))); tc.stroke(lens, with: ink, lineWidth: 2.2)
            tc.stroke(SVG.path("M64 129l6 7"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if ex.contains("lapels") { tc.stroke(SVG.path("M38 84l-5 24 13-9M58 84l5 24-13-9"), with: ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)) }
        let name = Agent.role(id).name, fs = min(8.5, 36 / (CGFloat(name.count) * 0.62))
        tc.stroke(SVG.path("M37 85L33 100M59 85L63 100"), with: ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        let tag = Path(roundedRect: CGRect(x: 27, y: 100, width: 42, height: 15), cornerRadius: 3)
        tc.fill(tag, with: paper); tc.stroke(tag, with: ink, lineWidth: 1.8)
        tc.fill(Path(roundedRect: CGRect(x: 27, y: 100, width: 42, height: 4.5), cornerRadius: 2.2), with: .color(accent))
        var tt = tc
        if facing < 0 { tt.translateBy(x: 96, y: 0); tt.scaleBy(x: -1, y: 1) }
        tt.draw(Text(name).font(.system(size: fs, weight: .heavy, design: .rounded)).foregroundColor(Color.ink), at: CGPoint(x: 48, y: 109.5), anchor: .center)
    }

    func drawArms(_ c: inout GraphicsContext, _ sL: CGPoint, _ sR: CGPoint, _ stride: Double) {
        let work = busy ? 2.4 : 1.0
        var kind = doing
        if hover, [.type, .stand, .read, .look, .sip].contains(kind) { kind = .present }   // point at an agent and it waves
        let waving = hover && kind == .present
        var l = CGPoint(x: 25, y: 160 + wave(1.5, 1.5)), r = CGPoint(x: 71, y: 160 + wave(1.3, 1.5, 1))
        var prop: ((inout GraphicsContext) -> Void)?

        switch kind {
        case .type:
            let tap = wave(11 * work, 3.2), tap2 = wave(11 * work, 3.2, 2.2)
            l = CGPoint(x: 40 + wave(5, 1.5), y: 128 + tap); r = CGPoint(x: 58 + wave(5, 1.5, 1), y: 128 + tap2)
        case .read:
            l = CGPoint(x: 36, y: 132); r = CGPoint(x: 60, y: 132)
            prop = { openBook(&$0, at: CGPoint(x: 48, y: 126 + wave(1.1, 1)), tilt: wave(0.7, 2)) }
        case .sip:
            let up = 0.5 + 0.5 * sin(t * 1.6)
            l = CGPoint(x: 40, y: 128); r = CGPoint(x: 62 - up * 4, y: 128 - up * 58)
            let hand = r
            prop = { mug(&$0, at: CGPoint(x: hand.x + 5, y: hand.y - 6)) }
        case .walk:
            l = CGPoint(x: 26 - stride * 3, y: 154 + stride * 8); r = CGPoint(x: 70 + stride * 3, y: 154 - stride * 8)
        case .reach:
            r = CGPoint(x: 72, y: 50 + wave(3, 3)); l = CGPoint(x: 26, y: 158)
        case .stretch:
            l = CGPoint(x: 20 + wave(2, 3), y: 36 + wave(3, 3)); r = CGPoint(x: 76 + wave(2, 3, 1), y: 36 + wave(3, 3, 1))
        case .talk:
            r = CGPoint(x: 80 + wave(6, 3), y: 112 + wave(7, 8)); l = CGPoint(x: 26, y: 158)
        case .present:
            if waving { r = CGPoint(x: 86 + wave(9, 5), y: 60 + wave(9, 4, 1.6)) }
            else { r = CGPoint(x: 77, y: 112 + wave(1.5, 2)); l = CGPoint(x: 24, y: 158) }
        case .file:
            r = CGPoint(x: 74, y: 56 + wave(2.5, 3)); l = CGPoint(x: 28, y: 150)
            let hand = r
            prop = { paperSheet(&$0, at: CGPoint(x: hand.x + 3, y: hand.y + 4), tilt: 8 + wave(2.5, 4)) }
        case .dig:
            l = CGPoint(x: 38 + wave(5, 2), y: 136 + wave(6, 9)); r = CGPoint(x: 58 + wave(5, 2, 1.7), y: 136 + wave(6, 9, 2.4))
            let hand = l
            prop = { paperSheet(&$0, at: CGPoint(x: hand.x + 1, y: hand.y + 2), tilt: -6 + wave(6, 8)) }
        case .water:
            r = CGPoint(x: 70, y: 124 + wave(1.2, 3)); l = CGPoint(x: 28, y: 158)
            let hand = r
            prop = { wateringCan(&$0, at: CGPoint(x: hand.x + 10, y: hand.y)) }
        case .look, .stand: break
        }
        // what it is carrying while its hands are free to hold it
        switch carry {
        case .book where [.walk, .stand, .look, .present, .talk].contains(kind):
            l = CGPoint(x: 36, y: 128); r = CGPoint(x: 60, y: 128); prop = { closedBook(&$0, at: CGPoint(x: 48, y: 122), tilt: wave(2, 2)) }
        case .openBook where [.stand, .look].contains(kind):
            l = CGPoint(x: 36, y: 132); r = CGPoint(x: 60, y: 132); prop = { openBook(&$0, at: CGPoint(x: 48, y: 126), tilt: wave(0.7, 2)) }
        case .paper where !waving && kind != .file && kind != .dig:
            r = CGPoint(x: 76, y: 116 + (kind == .present ? wave(1.5, 2) : 0))
            let hand = r
            prop = { paperSheet(&$0, at: CGPoint(x: hand.x + 2, y: hand.y), tilt: 5 + wave(1.4, 3)) }
        default: break
        }
        arm(&c, shoulder: sL, hand: l, outward: -1)
        if let prop { prop(&c) }
        arm(&c, shoulder: sR, hand: r, outward: 1)
    }

    func drawHead(_ c: inout GraphicsContext) {
        var h = c
        let looking = doing == .look
        let nod = seated ? wave(2.0, 1.6) : wave(0.8, 1.8)
        var tilt = hover ? 7 : nod + (busy ? 3 : 0)
        if doing == .read { tilt = 7 + wave(0.7, 1.5) }
        if doing == .stretch { tilt = -9 }
        if looking { tilt = wave(0.6, 9) }
        h.translateBy(x: 0, y: wave(1.7, 1.1) - (doing == .walk ? abs(sin(walk)) * 2.5 : 0))
        h.translateBy(x: 48, y: 78); h.rotate(by: .degrees(tilt)); h.translateBy(x: -48, y: -78)

        c.stroke(SVG.path("M42 70v14M56 70v14"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))   // neck, behind the head
        h.fill(SVG.path("M30 40c0 18 8 30 18 30s18-12 18-30z"), with: paper)
        h.stroke(SVG.path("M30 40c0 18 8 30 18 30s18-12 18-30"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        let look = Look.of(id), accent = Agent.color(id), ex = look.extras
        let hairFill: GraphicsContext.Shading = look.hairTint.map { .color($0) } ?? ink
        func hairShape(_ p: Path) { h.fill(p, with: hairFill); if look.hairTint != nil { h.stroke(p, with: ink, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)) } }
        switch look.hair {
        case "curly":
            for (x, y, r) in [(31.0, 35.0, 9.0), (35, 22, 9), (46, 15, 10), (58, 16, 9), (65, 25, 9), (67, 37, 8)] { hairShape(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))) }
        case "long":
            hairShape(Path(roundedRect: CGRect(x: 20, y: 30, width: 12, height: 56), cornerRadius: 6))
            hairShape(Path(roundedRect: CGRect(x: 64, y: 30, width: 12, height: 56), cornerRadius: 6))
            hairShape(SVG.path(Portrait.hair["SM"]!.components(separatedBy: " M48 4").first!))
        default:
            hairShape(SVG.path((Portrait.hair[look.hair] ?? Portrait.hair["MSOA"]!).components(separatedBy: " M48 4").first!))
            if look.hair == "librarian" { hairShape(Path(ellipseIn: CGRect(x: 40, y: -4, width: 16, height: 16))) }
        }
        if ex.contains("cap") {   // a beanie in the agent's colour
            let cap = SVG.path("M27 38C26 14 38 8 48 8s22 6 21 30z")
            h.fill(cap, with: .color(accent.opacity(0.92))); h.stroke(cap, with: ink, style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            h.stroke(SVG.path("M27 33h42"), with: ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            h.fill(Path(ellipseIn: CGRect(x: 43, y: 2, width: 10, height: 10)), with: .color(accent)); h.stroke(Path(ellipseIn: CGRect(x: 43, y: 2, width: 10, height: 10)), with: ink, lineWidth: 2)
        }
        if ex.contains("beret") {
            var b = h; b.translateBy(x: 48, y: 15); b.rotate(by: .degrees(-10))
            let beret = Path(ellipseIn: CGRect(x: -27, y: -9, width: 56, height: 21))
            b.fill(beret, with: .color(accent.opacity(0.92))); b.stroke(beret, with: ink, lineWidth: 2.6); b.stroke(SVG.path("M1 -9v-5"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if course != nil {   // mortarboard with a tassel that swings
            h.fill(SVG.path("M18 17l30-13 30 13-30 13z"), with: ink)
            h.stroke(SVG.path("M35 26v9c8 5 18 5 26 0v-9"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            h.stroke(SVG.path("M76 17v\(14 + wave(3, 1.5))"), with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            h.fill(Path(ellipseIn: CGRect(x: 73.5, y: 32 + wave(3, 1.5), width: 5, height: 5)), with: ink)
        }
        if ex.contains("pencil") { h.stroke(SVG.path("M64 34l9-13"), with: ink, lineWidth: 3.5) }   // behind the ear
        if ex.contains("headset") { h.stroke(SVG.path("M29 42c-5 0-5 12 0 12M29 54c0 8 8 10 14 8"), with: ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round)) }
        switch look.glasses {
        case .round:
            for x in [41.0, 56.0] { h.stroke(Path(ellipseIn: CGRect(x: x - 5.5, y: 40.5, width: 11, height: 11)), with: ink, lineWidth: 2.6) }
            h.stroke(SVG.path("M46.5 46h4"), with: ink, lineWidth: 2.6)
        case .square:
            for x in [41.0, 56.0] { h.stroke(Path(roundedRect: CGRect(x: x - 6.5, y: 40.5, width: 13, height: 11), cornerRadius: 2.5), with: ink, lineWidth: 2.4) }
            h.stroke(SVG.path("M47.5 45h1"), with: ink, lineWidth: 2.4)
        case .half:   // half-moon reading glasses, low on the nose
            for x in [41.0, 56.0] { h.stroke(Path(ellipseIn: CGRect(x: x - 5.5, y: 47.5, width: 11, height: 7)), with: ink, lineWidth: 2.2) }
            h.stroke(SVG.path("M46.5 51h4M30 49l5 2M66 49l-5 2"), with: ink, lineWidth: 1.8)
        case .none: break
        }
        if ex.contains("freckles") { for p in [(38.0, 52.0), (42, 54), (54, 54), (58, 52)] { h.fill(Path(ellipseIn: CGRect(x: p.0 - 1, y: p.1 - 1, width: 2, height: 2)), with: ink) } }
        if ex.contains("stubble") { for p in [(40.0, 62.0), (44, 65), (48, 66), (52, 65), (56, 62), (36, 58), (60, 58)] { h.fill(Path(ellipseIn: CGRect(x: p.0 - 0.9, y: p.1 - 0.9, width: 1.8, height: 1.8)), with: ink) } }
        if ex.contains("moustache") { h.fill(SVG.path("M37 58c4-3 8-2 11 0 3-2 7-3 11 0-3 5-8 3-11 1-3 2-8 4-11-1z"), with: ink) }
        if ex.contains("earrings") { for x in [29.0, 67.0] { h.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: 53, width: 5, height: 5)), with: .color(accent)); h.stroke(Path(ellipseIn: CGRect(x: x - 2.5, y: 53, width: 5, height: 5)), with: ink, lineWidth: 1.4) } }

        // eyes: look around (or at the page), blink every few seconds
        let cycle = 3.6 + Double(abs(id.hashValue % 7)) * 0.3
        let blink = (t.truncatingRemainder(dividingBy: cycle)) < 0.14
        let gx = looking ? wave(0.6, 2.4) : busy ? 1.6 : wave(0.5, 1.4), gy = doing == .read ? 1.8 : (seated ? 0.4 : 0)
        for x in [41.0, 56.0] {
            let ry = blink ? 0.4 : 2.0
            h.fill(Path(ellipseIn: CGRect(x: x - 2 + gx, y: 46 + gy - ry, width: 4, height: ry * 2)), with: ink)
        }
        h.stroke(SVG.path("M48 51l-3 8h5"), with: ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        if busy { h.fill(Path(ellipseIn: CGRect(x: 45.5, y: 60, width: 5, height: 5)), with: ink) }
        else if doing == .talk { let o = 2 + abs(wave(9, 2.5)); h.fill(Path(ellipseIn: CGRect(x: 48 - o, y: 60, width: o * 2, height: o + 1.5)), with: ink) }
        else if doing == .stretch { h.fill(Path(ellipseIn: CGRect(x: 44, y: 59, width: 8, height: 9)), with: ink) }   // a yawn
        else { h.stroke(SVG.path(hover || doing == .present ? "M41 61c4 6 10 6 14 0" : "M43 62c3 2 7 2 10 0"), with: ink, style: StrokeStyle(lineWidth: 2.8, lineCap: .round)) }
    }

    /// A thought bubble with animated dots above the head while the agent is working on something.
    func thought(_ c: inout GraphicsContext) {
        let cloud = Path(roundedRect: CGRect(x: 56, y: -30, width: 42, height: 24), cornerRadius: 12)
        c.fill(cloud, with: paper); c.stroke(cloud, with: ink, lineWidth: 2.4)
        for (i, r) in [(0, 3.0), (1, 2.2)] {
            let p = CGPoint(x: 52 - Double(i) * 6, y: -2 + Double(i) * 6), dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            c.fill(dot, with: paper); c.stroke(dot, with: ink, lineWidth: 1.8)
        }
        for i in 0..<3 {
            let on = Int(t * 3) % 3 == i, r = on ? 3.6 : 2.4
            c.fill(Path(ellipseIn: CGRect(x: 66 + Double(i) * 11 - r, y: -18 - r, width: r * 2, height: r * 2)), with: ink)
        }
    }
}

/// A small animated agent for cards: stands with its book, looks around, reads, waves when you point at it or when it has something for you.
/// At rest it is a cached picture whose pose changes every few seconds; it only animates live (24 frames a second) when you point at it,
/// it is working, or it has something for you. Redrawing it continuously, even ten times a second, kept about a third of a CPU core busy.
struct MiniAgent: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String
    var hover = false

    nonisolated static func draw(_ ctx: GraphicsContext, _ size: CGSize, id: String, t: Double, hover: Bool, busy: Bool, asking: Bool) {
        let k = size.height / (Rig.design.height + 38)   // room above the head for the thought bubble
        var c = ctx
        c.translateBy(x: (size.width - Rig.design.width * k) / 2, y: 38 * k); c.scaleBy(x: k, y: k)
        c.fill(Path(ellipseIn: CGRect(x: 18, y: 216, width: 60, height: 14)), with: .color(Color.ink.opacity(0.12)))
        let cycle = t.truncatingRemainder(dividingBy: 18)
        var doing = Doing.stand, carry = Carry.book
        if asking { doing = .present; carry = .paper }
        else if cycle > 9 && cycle < 12 { doing = .look; carry = .none }
        else if cycle >= 12 { carry = .openBook }
        let beckon = asking && sin(t * 1.6) > 0.35
        Rig(id: id, course: Agent.role(id).course, seat: 0, doing: doing, carry: carry, hover: hover || beckon, busy: busy, t: t).draw(c, layer: .all)
    }

    var body: some View {
        let busy = store.thinking.contains(id), asking = store.inboxReady(id) > 0
        if hover || busy || asking {
            TimelineView(.animation(minimumInterval: Visibility.shared.active ? 1.0 / 24 : 1.0 / 6, paused: reduceMotion || !Visibility.shared.visible)) { tl in
                Canvas { ctx, size in Self.draw(ctx, size, id: id, t: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate + Double(abs(id.hashValue % 11)), hover: hover, busy: busy, asking: asking) }
            }
        } else {
            IdleAgent(id: id)
        }
    }
}

/// The agent at rest: one of three poses (standing with the book, looking around, reading), picked every three seconds, drawn once and kept.
private struct IdleAgent: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 3)) { tl in
            let cycle = reduceMotion ? 0 : (tl.date.timeIntervalSinceReferenceDate + Double(abs(id.hashValue % 11))).truncatingRemainder(dividingBy: 18)
            let pose = cycle > 9 && cycle < 12 ? 1 : cycle >= 12 ? 2 : 0
            GeometryReader { g in IdlePictures.image(id, pose, g.size, scheme).resizable().scaledToFit().frame(width: g.size.width, height: g.size.height) }
        }
    }
}

@MainActor private enum IdlePictures {
    private static var cache: [String: Image] = [:]
    static func image(_ id: String, _ pose: Int, _ size: CGSize, _ scheme: ColorScheme) -> Image {
        let key = "\(id)|\(pose)|\(Int(size.width))x\(Int(size.height))|\(scheme)"
        if let hit = cache[key] { return hit }
        let t = [3.0, 10.0, 14.0][pose]   // a moment inside each stretch of the 18-second cycle
        let content = Canvas { ctx, sz in MiniAgent.draw(ctx, sz, id: id, t: t, hover: false, busy: false, asking: false) }
            .frame(width: max(size.width, 1), height: max(size.height, 1)).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let img = renderer.cgImage.map { Image(decorative: $0, scale: 2) } ?? Image(systemName: "person")
        cache[key] = img
        return img
    }
}


// MARK: - Who is who

extension Agent {
    /// Everyone has their own colour: the course agents keep their course's, each helper has one of its own, and the Manager is slate.
    static func color(_ id: String) -> Color {
        if let c = role(id).course { return Color.course(c) }
        return helperColors[id] ?? .ink2
    }
    static let helperColors: [String: Color] = [
        "sorter": Color(light: 0xD9A21B, dark: 0xF0C75A), "scribe": Color(light: 0x3D86D6, dark: 0x79B4F0),
        "librarian": Color(light: 0xCF4B58, dark: 0xF08A94), "planner": Color(light: 0x8C59CF, dark: 0xBE96F0),
        "tutor": Color(light: 0x20A6A8, dark: 0x66D3D4), "writer": Color(light: 0xE0609F, dark: 0xF59AC8),
        "researcher": Color(light: 0x6AA832, dark: 0xA6D96A), "analyst": Color(light: 0xE0702F, dark: 0xF5A878),
        "manager": Color(light: 0x56606F, dark: 0xA3AEC0),
    ]
}

/// What makes each agent recognisable besides its colour: hair, glasses and a few extras.
struct Look {
    enum Glasses { case none, round, square, half }
    var hair = "MSOA"                 // a key in `Portrait.hair`, or "curly" / "long"
    var hairTint: Color? = nil        // nil = drawn in ink
    var glasses = Glasses.none
    var extras: Set<String> = []      // cap, beret, bowtie, scarf, lapels, moustache, freckles, stubble, earrings, pencil, headset
    static func of(_ id: String) -> Look {
        switch id {
        case "sorter": Look(hair: "MSOA", hairTint: Color(light: 0x7A4A28, dark: 0xB98458), extras: ["cap", "freckles"])
        case "scribe": Look(hair: "SM", glasses: .square, extras: ["bowtie"])
        case "librarian": Look(hair: "librarian", hairTint: Color(light: 0x9AA0A8, dark: 0xC9CED6), glasses: .half, extras: ["earrings"])
        case "planner": Look(hair: "planner", hairTint: Color(light: 0x8B4A2B, dark: 0xC28A66), extras: ["scarf"])
        case "tutor": Look(hair: "TEM", hairTint: Color(light: 0xC9672B, dark: 0xE79A62), glasses: .round, extras: ["moustache"])
        case "writer": Look(hair: "long", hairTint: Color(light: 0x7A3B3B, dark: 0xB86F6F), extras: ["beret", "pencil"])
        case "analyst": Look(hair: "curly", hairTint: Color(light: 0xA0522D, dark: 0xD99A6C), glasses: .round, extras: ["calculator", "pencil"])
        case "researcher": Look(hair: "TEM", hairTint: Color(light: 0x2F4A3A, dark: 0x8FC1A0), glasses: .square, extras: ["magnifier"])
        case "manager": Look(hair: "SM", extras: ["headset", "lapels"])
        case "MSOA": Look(hair: "curly")
        case "SM": Look(hair: "SM", glasses: .square)
        case "TEM": Look(hair: "TEM", extras: ["stubble", "earrings"])
        default: Look()
        }
    }
}
