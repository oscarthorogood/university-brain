import SwiftUI

// MARK: - Design system
//
// Two layers, never mixed:
//   • Liquid Glass is the UI layer: panes, controls, fields, rows being pointed at or selected, speech bubbles in the interface.
//   • Content (notes, lists, cards, the line-art agents) is flat and sits underneath it.
// Everything glass comes from this file, so shapes, sizes and behaviour stay the same across the app.

enum DS {
    /// One corner-radius scale. Nested shapes step down so they stay concentric: pane > card > tile > row.
    enum Radius {
        static let pane: CGFloat = 26
        static let card: CGFloat = 20
        static let tile: CGFloat = 14
        static let row: CGFloat = 12
    }
    /// One control-height scale.
    enum Height {
        static let header: CGFloat = 44    // actions and round buttons in a page header
        static let control: CGFloat = 36   // inline buttons, segmented controls, fields
        static let compact: CGFloat = 30   // sidebar rows and compact buttons
        static let icon: CGFloat = 26      // small icon buttons in window chrome
    }
}

/// Hover / press / selection for anything glass: it appears under the pointer, the control springs when pressed,
/// and a selected one stays glass with a soft tint. Reduce Motion keeps the glass but drops the scale.
struct GlassHover: ViewModifier {
    var shape: AnyShape
    var selected = false
    var hoverOnly = true            // false: always glass (a control that is a control, not a row)
    var pressed = false
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .contentShape(shape)
            .glassEffect(glass, in: shape)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.35), value: pressed)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
    }
    private var glass: Glass {
        if selected { return .regular.tint(Color.ink.opacity(0.12)).interactive() }
        return hover || pressed || !hoverOnly ? .regular.interactive() : .identity
    }
}

/// Rows, tiles and icons: glass on hover, press and selection.
struct GlassButtonStyle: ButtonStyle {
    var radius: CGFloat = DS.Radius.row
    var shape: AnyShape? = nil
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(GlassHover(shape: shape ?? AnyShape(.rect(cornerRadius: radius)), selected: selected, pressed: configuration.isPressed))
    }
}

/// A quiet sidebar row: no chrome until pointed at, then a soft pill; the open page sits on a raised one.
struct SideRowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { SideRowBody(label: configuration.label, selected: selected, pressed: configuration.isPressed) }
    private struct SideRowBody: View {
        let label: ButtonStyleConfiguration.Label; let selected: Bool; let pressed: Bool
        @State private var hover = false
        var body: some View {
            label
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                        .fill(selected ? Color.card.opacity(0.85) : Color.ink.opacity(pressed ? 0.1 : hover ? 0.05 : 0))
                        .shadow(color: .black.opacity(selected ? 0.07 : 0), radius: 3, y: 1)
                }
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// A button that is always glass: a capsule for actions, optionally tinted dark for the primary one.
struct GlassActionStyle: ButtonStyle {
    enum Size { case header, control, compact, chip }
    var size = Size.control
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let h: CGFloat = size == .header ? DS.Height.header : size == .control ? DS.Height.control : size == .compact ? DS.Height.compact : 26
        configuration.label
            .font(.system(size: size == .header ? 14 : size == .chip ? 11 : 13, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.card : Color.ink)
            .padding(.horizontal, size == .header ? 18 : size == .chip ? 12 : 16).frame(minHeight: h)
            .contentShape(.capsule)
            .glassEffect(prominent ? .regular.tint(Color.ink.opacity(0.9)).interactive() : .regular.interactive(), in: .capsule)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A round glass icon button.
struct GlassIconStyle: ButtonStyle {
    var size: CGFloat = DS.Height.header
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.card : Color.ink2)
            .frame(width: size, height: size)
            .contentShape(.circle)
            .glassEffect(prominent ? .regular.tint(Color.ink.opacity(0.9)).interactive() : .regular.interactive(), in: .circle)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glassRow: GlassButtonStyle { GlassButtonStyle(radius: DS.Radius.row) }
    static func glass(radius: CGFloat, selected: Bool = false) -> GlassButtonStyle { GlassButtonStyle(radius: radius, selected: selected) }
    static var glassCircle: GlassButtonStyle { GlassButtonStyle(shape: AnyShape(.circle)) }
    static var glassCapsule: GlassButtonStyle { GlassButtonStyle(shape: AnyShape(.capsule)) }
}
extension ButtonStyle where Self == GlassActionStyle {
    static var glassAction: GlassActionStyle { GlassActionStyle() }
    static func glassAction(_ size: GlassActionStyle.Size, prominent: Bool = false) -> GlassActionStyle { GlassActionStyle(size: size, prominent: prominent) }
}
extension ButtonStyle where Self == GlassIconStyle {
    static func glassIcon(_ size: CGFloat = DS.Height.header, prominent: Bool = false) -> GlassIconStyle { GlassIconStyle(size: size, prominent: prominent) }
}

extension View {
    /// A single-line text field: a glass capsule.
    func glassField(height: CGFloat = DS.Height.control) -> some View {
        padding(.horizontal, 14).frame(height: height).glassEffect(.regular, in: .capsule)
    }
    /// A glass panel for a group of controls inside a glass pane (a raised tile).
    func glassTile(radius: CGFloat = DS.Radius.tile) -> some View { glassEffect(.regular, in: .rect(cornerRadius: radius)) }
}

/// A speech bubble in the interface: glass, with a small tail on the left, right or bottom.
/// One continuous outline (the tail is part of it, not a second shape), so the glass has no seam where it joins.
struct BubbleShape: Shape {
    enum Tail { case left, right, bottom }
    var tail = Tail.left
    var radius: CGFloat = 16
    var tailAt: CGFloat? = nil   // bottom tail: where its tip sits along the width (0...1); nil keeps it near the left
    func path(in r: CGRect) -> Path {
        var b = r   // the body, without the tail
        switch tail {
        case .left: b.origin.x += 8; b.size.width -= 8
        case .right: b.size.width -= 8
        case .bottom: b.size.height -= 10
        }
        let rad = min(radius, b.height / 2, b.width / 2), hw: CGFloat = 6
        var p = Path()
        p.move(to: CGPoint(x: b.midX, y: b.minY))
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.maxY), radius: rad)
        if tail == .right {
            p.addLine(to: CGPoint(x: b.maxX, y: b.midY - hw)); p.addLine(to: CGPoint(x: r.maxX, y: b.midY)); p.addLine(to: CGPoint(x: b.maxX, y: b.midY + hw))
        }
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.maxY), radius: rad)
        if tail == .bottom {
            let want = tailAt.map { r.minX + r.width * $0 } ?? r.minX + 22
            let tip = min(max(want, b.minX + rad + hw), max(b.minX + rad + hw, b.maxX - rad - hw))
            p.addLine(to: CGPoint(x: tip + hw, y: b.maxY)); p.addLine(to: CGPoint(x: tip, y: r.maxY)); p.addLine(to: CGPoint(x: tip - hw, y: b.maxY))
        }
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.minY), radius: rad)
        if tail == .left {
            p.addLine(to: CGPoint(x: b.minX, y: b.midY + hw)); p.addLine(to: CGPoint(x: r.minX, y: b.midY)); p.addLine(to: CGPoint(x: b.minX, y: b.midY - hw))
        }
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY), radius: rad)
        p.closeSubpath()
        return p
    }
}

/// For things that are not glass but should still spring when pressed (checkboxes, list ticks).
struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressScaleStyle { static var pressScale: PressScaleStyle { PressScaleStyle() } }

/// Fades and lifts content in once, staggered by `delay`. Skipped with Reduce Motion.
struct AppearIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(shown || reduceMotion ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(delay)) { shown = true } }
    }
}
extension View { func appearIn(_ delay: Double = 0) -> some View { modifier(AppearIn(delay: delay)) } }


/// Behind the glass panes: a soft wash of morning colour, so the window reads warm rather than grey.
struct WindowBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [Color(light: 0xFFC9A3, dark: 0x8A4B2A), Color(light: 0xF6E7D8, dark: 0x3A2C25), Color(light: 0xBFD6EE, dark: 0x1F3550)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).opacity(scheme == .dark ? 0.35 : 0.5)
        }
    }
}

// MARK: - Responsive layout
// The window can be made much smaller than the default. Pages ask how wide the main panel is and reflow:
// a side column drops under the main one and the page scrolls.

private struct MainWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 1100 }
extension EnvironmentValues { var mainWidth: CGFloat { get { self[MainWidthKey.self] } set { self[MainWidthKey.self] = newValue } } }

/// Two columns, one fixed width. When the main panel is too narrow for both, they stack (first, then second) and the page scrolls.
struct SplitPane<A: View, B: View>: View {
    enum Fixed { case first, second }
    var fixed: Fixed
    var width: CGFloat
    var minFlex: CGFloat = 400                 // narrowest the flexible column may get before stacking
    var stacked: (first: CGFloat, second: CGFloat)   // heights when stacked
    @ViewBuilder var first: A
    @ViewBuilder var second: B
    @Environment(\.mainWidth) private var mainWidth
    var body: some View {
        if mainWidth - 24 - 12 - width >= minFlex {
            HStack(spacing: 12) {
                if fixed == .first { first.frame(width: width); second } else { first; second.frame(width: width) }
            }
        } else {
            ScrollView { VStack(spacing: 12) { first.frame(height: stacked.first); second.frame(height: stacked.second) } }.scrollIndicators(.hidden)
        }
    }
}

extension View {
    /// In a short window, scroll instead of pushing the layout past the edge.
    func scrollsWhenShort() -> some View {
        ViewThatFits(in: .vertical) { self; ScrollView { self }.scrollIndicators(.hidden) }
    }
}
