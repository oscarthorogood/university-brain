import AppKit
import CoreGraphics

// Draws the University Brain app icon: a Liquid Glass–style tile with three white books on a shelf. `swift icon.swift out.png`
let S = 1024.0
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
func ctx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

let c = ctx(Int(S), Int(S))
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius = 190.0
let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// soft drop shadow under the tile
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: rgb(0, 0, 0, 0.35))
c.addPath(tilePath); c.setFillColor(rgb(0.5, 0.3, 0.3)); c.fillPath()
c.restoreGState()

// glass body: warm clay/rose gradient
c.saveGState()
c.addPath(tilePath); c.clip()
let body = CGGradient(colorsSpace: cs, colors: [rgb(0.95, 0.68, 0.58), rgb(0.80, 0.50, 0.49), rgb(0.62, 0.38, 0.43)] as CFArray, locations: [0, 0.55, 1])!
c.drawLinearGradient(body, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 720, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// light refracting from below (glass thickness)
let glow = CGGradient(colorsSpace: cs, colors: [rgb(1, 0.85, 0.75, 0.55), rgb(1, 0.85, 0.75, 0)] as CFArray, locations: [0, 1])!
c.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 80), startRadius: 0, endCenter: CGPoint(x: 512, y: 80), endRadius: 520, options: [])
// top specular sheen
c.saveGState()
c.addEllipse(in: CGRect(x: 40, y: 560, width: 944, height: 700)); c.clip()
let sheen = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1, 0.42), rgb(1, 1, 1, 0.04)] as CFArray, locations: [0, 1])!
c.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
c.restoreGState()
c.restoreGState()

// glass rim: bright top-left edge, darker bottom-right
c.saveGState()
c.addPath(tilePath); c.clip()
c.setLineWidth(10)
c.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: radius - 2, cornerHeight: radius - 2, transform: nil))
c.replacePathWithStrokedPath(); c.clip()
let rim = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1, 0.95), rgb(1, 1, 1, 0.12), rgb(1, 1, 1, 0.5)] as CFArray, locations: [0, 0.55, 1])!
c.drawLinearGradient(rim, start: CGPoint(x: 140, y: 924), end: CGPoint(x: 880, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
c.restoreGState()

// ---- the glyph: three books on a shelf, on its own layer so spine bands can be cut out of it ----
let g = ctx(Int(S), Int(S))
g.setFillColor(rgb(1, 1, 1))
g.translateBy(x: 0, y: -30)
let base = 300.0
func book(left x: Double, width w: Double, height h: Double, lean: Double = 0, bands: [Double], label: Bool = false) {
    g.saveGState()
    g.translateBy(x: x + w, y: base); g.rotate(by: -lean * .pi / 180); g.translateBy(x: -w, y: 0)   // leans about its bottom-right corner
    g.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 26, cornerHeight: 26, transform: nil)); g.fillPath()
    g.setBlendMode(.clear); g.setLineCap(.round); g.setLineWidth(16)
    for y in bands { g.move(to: CGPoint(x: 24, y: y)); g.addLine(to: CGPoint(x: w - 24, y: y)); g.strokePath() }
    if label { g.addPath(CGPath(roundedRect: CGRect(x: 30, y: h * 0.5 - 56, width: w - 60, height: 112), cornerWidth: 18, cornerHeight: 18, transform: nil)); g.fillPath() }
    g.restoreGState()
}
book(left: 256, width: 138, height: 450, bands: [450 - 80, 450 - 128, 70])
book(left: 410, width: 156, height: 560, bands: [560 - 80, 70], label: true)
book(left: 582, width: 138, height: 470, lean: 13, bands: [470 - 80, 470 - 128, 70])
g.setBlendMode(.normal)
g.addPath(CGPath(roundedRect: CGRect(x: 214, y: base - 36, width: 600, height: 36), cornerWidth: 18, cornerHeight: 18, transform: nil)); g.fillPath()
let glyph = g.makeImage()!

// `swift icon.swift out.png glyph.png` also writes the books alone (for the layered Icon Composer file)
if CommandLine.arguments.count > 2 {
    try! NSBitmapImageRep(cgImage: glyph).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}

// glyph shadow + glow, then glyph
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: rgb(0.3, 0.1, 0.15, 0.45))
c.draw(glyph, in: CGRect(x: 0, y: 0, width: S, height: S))
c.restoreGState()
c.setAlpha(0.96)
c.draw(glyph, in: CGRect(x: 0, y: 0, width: S, height: S))

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
