import SwiftUI
import AppKit

// A live Markdown editor: you type in the document itself and it looks like the finished note (headings, bold, lists, checkboxes),
// like Apple Notes. The file stays plain Markdown, so Obsidian reads it the same. Marks such as ** and # stay in the text, dimmed.

/// A note split into its YAML frontmatter and its body. The editor only ever touches the body.
enum NoteText {
    static func split(_ s: String) -> (front: String, body: String) {
        guard s.hasPrefix("---\n") else { return ("", s) }
        let ns = s as NSString
        var loc = 4
        while loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            if ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                var front = ns.substring(to: NSMaxRange(r)), body = ns.substring(from: NSMaxRange(r))
                while body.hasPrefix("\n") { front += "\n"; body.removeFirst() }
                return (front, body)
            }
            loc = NSMaxRange(r)
        }
        return ("", s)
    }
    static func body(_ s: String) -> String { split(s).body }
    static func front(_ s: String) -> String { split(s).front }
}

/// Lets the toolbar and the inspector act on the editor that is on screen.
@MainActor final class EditorController {
    weak var textView: MDTextView?

    func focus() { textView?.window?.makeFirstResponder(textView) }
    /// Gives focus once the editor exists (a brand-new note opens ready to type).
    func focusSoon() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.focus() } }

    private func replace(_ r: NSRange, with s: String) {
        guard let tv = textView, tv.shouldChangeText(in: r, replacementString: s) else { return }
        tv.replaceCharacters(in: r, with: s)
        tv.didChangeText()
    }

    /// Scrolls to a line of the body (0-based).
    func reveal(line: Int) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        var loc = 0, n = 0
        while n < line, loc < ns.length { loc = NSMaxRange(ns.lineRange(for: NSRange(location: loc, length: 0))); n += 1 }
        let r = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
        tv.scrollRangeToVisible(r)
        tv.setSelectedRange(NSRange(location: r.location, length: 0))
    }

    /// Wraps the selection in marks, takes them off again if they are already there, or drops a pair at the cursor to type into.
    func wrap(_ open: String, _ close: String? = nil) {
        guard let tv = textView else { return }
        focus()
        let close = close ?? open
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let o = (open as NSString).length, c = (close as NSString).length
        if sel.length > 0, sel.location >= o, NSMaxRange(sel) + c <= ns.length,
           ns.substring(with: NSRange(location: sel.location - o, length: o)) == open,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: c)) == close {
            let outer = NSRange(location: sel.location - o, length: sel.length + o + c)
            replace(outer, with: ns.substring(with: sel))
            tv.setSelectedRange(NSRange(location: sel.location - o, length: sel.length))
        } else {
            replace(sel, with: open + ns.substring(with: sel) + close)
            tv.setSelectedRange(NSRange(location: sel.location + o, length: sel.length))
        }
    }

    /// Sets the current line's prefix (a heading, list or quote); choosing the same one again removes it.
    func linePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        focus()
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let lr = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: lr)
        let oldLen = MarkdownStyler.prefixRX.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range.length ?? 0
        let old = ns.substring(with: NSRange(location: lr.location, length: oldLen))
        let new = old == prefix ? "" : prefix
        replace(NSRange(location: lr.location, length: oldLen), with: new)
        tv.setSelectedRange(NSRange(location: max(lr.location, sel.location + (new as NSString).length - oldLen), length: 0))
    }

    /// Puts text at the cursor, replacing any selection.
    func insert(_ s: String) {
        guard let tv = textView else { return }
        focus()
        let sel = tv.selectedRange()
        replace(sel, with: s)
        tv.setSelectedRange(NSRange(location: sel.location + (s as NSString).length, length: 0))
    }

    /// Puts a block (a table, a divider) on its own lines after the selection.
    func block(_ s: String) {
        guard let tv = textView else { return }
        focus()
        let ns = tv.string as NSString
        let at = NSMaxRange(tv.selectedRange())
        let before = at == 0 || ns.substring(with: NSRange(location: at - 1, length: 1)) == "\n" ? "" : "\n"
        let text = before + s + "\n"
        replace(NSRange(location: at, length: 0), with: text)
        tv.setSelectedRange(NSRange(location: at + (text as NSString).length, length: 0))
    }
}

/// The text view. It draws what the Markdown stands for (bullets, checkboxes, callout boxes, rules), adds the shortcuts, and ticks a checkbox on click.
final class MDTextView: NSTextView {
    weak var controller: EditorController?
    var decorations: [MarkdownStyler.Decoration] = []

    /// Styles the text and keeps the drawn extras in step with it.
    func restyle() {
        guard let storage = textStorage else { return }
        decorations = MarkdownStyler.apply(to: storage)
        needsDisplay = true
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, let k = event.charactersIgnoringModifiers {
            switch k {
            case "b": controller?.wrap("**"); return true
            case "i": controller?.wrap("*"); return true
            case "k": controller?.wrap("[[", "]]"); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// A click on a checkbox ticks it, anywhere else places the cursor as usual.
    override func mouseDown(with event: NSEvent) {
        let i = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let ns = string as NSString
        if event.clickCount == 1, ns.length > 0 {
            let lr = ns.lineRange(for: NSRange(location: min(i, ns.length - 1), length: 0))
            let line = ns.substring(with: lr)
            if let m = MarkdownStyler.checkRX.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let box = NSRange(location: lr.location + m.range(at: 3).location, length: m.range(at: 3).length)
                if i >= box.location - 1, i <= NSMaxRange(box) + 1 {
                    let now = ns.substring(with: box) == "[ ]" ? "[x]" : "[ ]"
                    if shouldChangeText(in: box, replacementString: now) { replaceCharacters(in: box, with: now); didChangeText() }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Drawing the things the marks stand for
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let o = textContainerOrigin, width = tc.size.width
        for d in decorations {
            let gr = lm.glyphRange(forCharacterRange: d.range, actualCharacterRange: nil)
            guard gr.length > 0 else { continue }
            var b = lm.boundingRect(forGlyphRange: gr, in: tc)
            b.origin.x += o.x; b.origin.y += o.y
            guard b.maxY >= rect.minY - 60, b.minY <= rect.maxY + 60 else { continue }
            switch d.kind {
            case .callout(let tint):
                let box = NSRect(x: o.x, y: b.minY - 6, width: width, height: b.height + 12)
                tint.withAlphaComponent(0.10).setFill()
                NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
                tint.setFill()
                NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY + 3, width: 3, height: box.height - 6), xRadius: 1.5, yRadius: 1.5).fill()
            case .quote:
                MarkdownStyler.faint.setFill()
                NSBezierPath(roundedRect: NSRect(x: o.x, y: b.minY, width: 3, height: b.height), xRadius: 1.5, yRadius: 1.5).fill()
            case .code:
                let box = NSRect(x: o.x, y: b.minY - 2, width: width, height: b.height + 4)
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            case .rule, .tableRule:
                MarkdownStyler.faint.setFill()
                NSBezierPath(rect: NSRect(x: o.x, y: b.midY, width: width, height: 1)).fill()
            case .bullet:
                MarkdownStyler.accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: b.midX - 2.5, y: b.midY - 2.5, width: 5, height: 5)).fill()
            case .checkbox(let done):
                let box = NSRect(x: b.minX + 1, y: b.midY - 8.5, width: 17, height: 17)
                let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
                if done {
                    MarkdownStyler.accent.setFill(); path.fill()
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: box.minX + 4.5, y: box.midY))
                    tick.line(to: NSPoint(x: box.minX + 7.5, y: box.midY + 3.2))
                    tick.line(to: NSPoint(x: box.minX + 12.5, y: box.midY - 3.6))
                    NSColor.white.setStroke(); tick.lineWidth = 2; tick.lineCapStyle = .round; tick.lineJoinStyle = .round; tick.stroke()
                } else {
                    MarkdownStyler.faint.setStroke(); path.lineWidth = 1.5; path.stroke()
                }
            }
        }
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MDTextView {
        let tv = MDTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
        tv.layoutManager?.delegate = context.coordinator
        tv.controller = controller
        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.insertionPointColor = MarkdownStyler.accent
        tv.string = text
        tv.restyle()
        controller.textView = tv
        return tv
    }

    func updateNSView(_ tv: MDTextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = tv
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.restyle()
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        }
    }

    /// The text view grows with its text, so the page's own scroll view scrolls the title and the text together.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: MDTextView, context: Context) -> CGSize? {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let w = max(proposal.width ?? 600, 100)
        tc.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        return CGSize(width: w, height: max(h + 140, 360))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSLayoutManagerDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? MDTextView else { return }
            if !tv.hasMarkedText() { tv.restyle() }
            parent.text = tv.string
        }

        // MARK: Hidden marks take no room
        /// Characters marked hidden by the styler get no glyph, so `**`, `#` and `>` simply are not there on screen.
        func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes idx: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
            guard let st = lm.textStorage else { return 0 }
            var out = [NSLayoutManager.GlyphProperty](repeating: [], count: range.length)
            var any = false
            for i in 0..<range.length {
                out[i] = props[i]
                let c = idx[i]
                if c < st.length, st.attribute(MarkdownStyler.hiddenKey, at: c, effectiveRange: nil) != nil { out[i].insert(.null); any = true }
            }
            guard any else { return 0 }
            lm.setGlyphs(glyphs, properties: out, characterIndexes: idx, font: font, forGlyphRange: range)
            return range.length
        }

        private func run(_ key: NSAttributedString.Key, at i: Int, in st: NSTextStorage) -> NSRange? {
            guard i >= 0, i < st.length else { return nil }
            var r = NSRange()
            return st.attribute(key, at: i, longestEffectiveRange: &r, in: NSRange(location: 0, length: st.length)) != nil ? r : nil
        }

        /// The cursor never rests inside a hidden mark: the marks in front of a line's text (the `## ` of a heading, a bullet) are skipped,
        /// and so are the marks around a word.
        func textView(_ tv: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0, let st = tv.textStorage, st.length > 0 else { return new }
            let ns = st.string as NSString
            var loc = min(new.location, st.length)
            let movingBack = loc < old.location
            let line = ns.lineRange(for: NSRange(location: min(loc, st.length - 1), length: 0))
            if let lead = run(MarkdownStyler.leadingKey, at: line.location, in: st), lead.location == line.location, loc < NSMaxRange(lead), loc >= lead.location {
                loc = movingBack && line.location > 0 ? line.location - 1 : NSMaxRange(lead)
            } else if let h = run(MarkdownStyler.hiddenKey, at: loc, in: st), h.location < loc {
                loc = movingBack ? h.location : NSMaxRange(h)
            }
            return NSRange(location: loc, length: 0)
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)): return newline(tv)
            case #selector(NSResponder.insertTab(_:)): return indent(tv, 1)
            case #selector(NSResponder.insertBacktab(_:)): return indent(tv, -1)
            case #selector(NSResponder.deleteBackward(_:)): return deleteBack(tv)
            case #selector(NSResponder.deleteForward(_:)): return deleteForward(tv)
            default: return false
            }
        }

        private func remove(_ r: NSRange, in tv: NSTextView) {
            if tv.shouldChangeText(in: r, replacementString: "") { tv.replaceCharacters(in: r, with: ""); tv.didChangeText() }
        }

        /// Backspace at the start of a line's text takes off its mark (a heading becomes body text, a bullet goes); otherwise it removes the
        /// character you can see, stepping over any hidden marks.
        func deleteBack(_ tv: NSTextView) -> Bool {
            let sel = tv.selectedRange()
            guard sel.length == 0, sel.location > 0, let st = tv.textStorage else { return false }
            let ns = st.string as NSString
            let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            if let lead = run(MarkdownStyler.leadingKey, at: line.location, in: st), lead.location == line.location, sel.location == NSMaxRange(lead) {
                remove(lead, in: tv); return true
            }
            if let h = run(MarkdownStyler.hiddenKey, at: sel.location - 1, in: st) {
                guard h.location > 0 else { return true }
                let r = ns.rangeOfComposedCharacterSequence(at: h.location - 1)
                remove(r, in: tv)
                tv.setSelectedRange(NSRange(location: r.location, length: 0))
                return true
            }
            return false
        }

        func deleteForward(_ tv: NSTextView) -> Bool {
            let sel = tv.selectedRange()
            guard sel.length == 0, let st = tv.textStorage, sel.location < st.length, let h = run(MarkdownStyler.hiddenKey, at: sel.location, in: st) else { return false }
            let end = NSMaxRange(h)
            guard end < st.length else { return true }
            remove((st.string as NSString).rangeOfComposedCharacterSequence(at: end), in: tv)
            return true
        }

        /// Return in a list starts the next item; Return on an empty item ends the list.
        func newline(_ tv: NSTextView) -> Bool {
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return false }
            let ns = tv.string as NSString
            let lr = ns.lineRange(for: sel)
            let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            let all = NSRange(location: 0, length: (line as NSString).length)
            let ls = line as NSString
            var prefix = "", next = ""
            if let q = MarkdownStyler.quoteRX.firstMatch(in: line, range: all) {
                // inside a quote or callout: keep the > marks, and carry on a list inside it
                let inner = NSRange(location: q.range.length, length: all.length - q.range.length)
                let marks = ls.substring(with: q.range)
                if let m = MarkdownStyler.checkRX.firstMatch(in: line, range: inner) {
                    prefix = marks + ls.substring(with: NSRange(location: m.range.location, length: m.range.length)); next = marks + ls.substring(with: m.range(at: 1)) + ls.substring(with: m.range(at: 2)) + " [ ] "
                    prefix = ls.substring(with: NSRange(location: 0, length: NSMaxRange(m.range)))
                } else if let m = MarkdownStyler.bulletRX.firstMatch(in: line, range: inner) {
                    prefix = ls.substring(with: NSRange(location: 0, length: NSMaxRange(m.range))); next = prefix
                } else { prefix = marks; next = marks }
            } else if let m = MarkdownStyler.checkRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range); next = ls.substring(with: m.range(at: 1)) + ls.substring(with: m.range(at: 2)) + " [ ] "
            } else if let m = MarkdownStyler.bulletRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range); next = prefix
            } else if let m = MarkdownStyler.numberRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range)
                let digits = ls.substring(with: m.range(at: 2))
                let n = (Int(digits.dropLast()) ?? 0) + 1
                next = ls.substring(with: m.range(at: 1)) + "\(n)" + String(digits.last ?? ".") + " "
            } else { return false }
            let prefixLen = (prefix as NSString).length
            guard sel.location - lr.location >= prefixLen else { return false }       // the cursor is inside the mark itself
            if line.trimmingCharacters(in: .whitespaces).count == prefix.trimmingCharacters(in: .whitespaces).count {
                remove(NSRange(location: lr.location, length: prefixLen), in: tv)      // nothing after the mark: end the list
                return true
            }
            tv.insertText("\n" + next, replacementRange: sel)
            return true
        }

        /// Tab and Shift-Tab nest and un-nest a list item.
        func indent(_ tv: NSTextView, _ dir: Int) -> Bool {
            let ns = tv.string as NSString
            let lr = ns.lineRange(for: tv.selectedRange())
            let line = ns.substring(with: lr)
            let all = NSRange(location: 0, length: (line as NSString).length)
            let isList = MarkdownStyler.checkRX.firstMatch(in: line, range: all) != nil || MarkdownStyler.bulletRX.firstMatch(in: line, range: all) != nil
                || MarkdownStyler.numberRX.firstMatch(in: line, range: all) != nil
            guard isList else { return false }
            if dir > 0 { tv.insertText("  ", replacementRange: NSRange(location: lr.location, length: 0)); return true }
            let drop = min(line.prefix { $0 == " " }.count, 2)
            if drop > 0 { tv.insertText("", replacementRange: NSRange(location: lr.location, length: drop)) }
            return true
        }
    }
}

/// Turns Markdown into what you see. The characters never change; the styler hides the marks (`**`, `#`, `>`, link syntax), sizes and
/// colours the rest, and lists what has to be drawn in their place (bullets, checkboxes, callout boxes, rules).
@MainActor enum MarkdownStyler {
    static let baseSize: CGFloat = 15
    static let hiddenKey = NSAttributedString.Key("sb.hidden")      // drawn with no room at all
    static let leadingKey = NSAttributedString.Key("sb.leading")    // the marks in front of a line's text: the cursor stays after them

    struct Decoration {
        enum Kind { case bullet, checkbox(Bool), callout(NSColor), quote, code, rule, tableRule }
        let kind: Kind
        let range: NSRange
    }

    static let ink = NSColor.labelColor
    static let ink2 = NSColor.secondaryLabelColor
    static let faint = NSColor.tertiaryLabelColor
    static let accent = NSColor(name: nil, dynamicProvider: { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.66, green: 0.61, blue: 0.94, alpha: 1) : NSColor(srgbRed: 0.44, green: 0.36, blue: 0.81, alpha: 1)
    })

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    static let prefixRX = rx(#"^(#{1,6} |- \[[ xX]\] |[-*+] |\d+[.)] |> )"#)
    static let headingRX = rx(#"^(#{1,6})[ \t]+"#)
    static let ruleRX = rx(#"^\s*(-{3,}|\*{3,}|_{3,})\s*$"#)
    static let quoteRX = rx(#"^(\s*>[ \t]?)+"#)
    static let checkRX = rx(#"^(\s*)([-*+])[ \t](\[[ xX]\])[ \t]"#)
    static let bulletRX = rx(#"^(\s*)([-*+])[ \t]"#)
    static let numberRX = rx(#"^(\s*)(\d+[.)])[ \t]"#)
    private static let calloutRX = rx(#"(\[!([A-Za-z]+)\][+-]?)[ \t]*"#)
    private static let codeRX = rx(#"`([^`\n]+)`"#)
    private static let boldRX = rx(#"\*\*([^*\n]+)\*\*"#)
    private static let italicRX = rx(#"(?<![*\w])\*([^*\n]+)\*(?![*\w])"#)
    private static let strikeRX = rx(#"~~([^~\n]+)~~"#)
    private static let markRX = rx(#"==([^=\n]+)=="#)
    private static let wikiRX = rx(#"(!?)\[\[([^\]\n|]+)(\|([^\]\n]+))?\]\]"#)
    private static let linkRX = rx(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
        mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }
    private static func paragraph(first: CGFloat = 0, head: CGFloat = 0, before: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4; p.paragraphSpacing = 2; p.paragraphSpacingBefore = before
        p.firstLineHeadIndent = first; p.headIndent = head
        return p
    }
    private static func tint(_ type: String) -> NSColor {
        switch type.lowercased() {
        case "tip", "hint", "success", "check", "done": .systemGreen
        case "warning", "caution", "attention", "question", "help", "faq": .systemOrange
        case "danger", "error", "failure", "fail", "bug", "missing": .systemRed
        case "quote", "cite": .systemGray
        case "example": .systemPurple
        default: .systemBlue
        }
    }

    @discardableResult
    static func apply(to s: NSTextStorage) -> [Decoration] {
        let ns = s.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, r, _, _ in lines.append(r) }

        var decos: [Decoration] = []
        var fenced = false, fenceStart = 0, inTable = false
        var quote: (start: Int, end: Int, tint: NSColor?)? = nil

        s.beginEditing()
        s.setAttributes([.font: font(baseSize), .foregroundColor: ink, .paragraphStyle: paragraph()], range: full)
        for r in lines {
            let t = ns.substring(with: r)
            let len = (t as NSString).length
            let all = NSRange(location: 0, length: len)
            func at(_ x: NSRange) -> NSRange { NSRange(location: r.location + x.location, length: x.length) }
            func hide(_ x: NSRange, leading: Bool = false) {
                guard x.length > 0 else { return }
                s.addAttribute(hiddenKey, value: true, range: at(x))
                if leading { s.addAttribute(leadingKey, value: true, range: at(x)) }
            }
            func lead(_ x: NSRange) { if x.length > 0 { s.addAttribute(leadingKey, value: true, range: at(x)) } }
            let trimmed = t.trimmingCharacters(in: .whitespaces)

            // a quote or callout block ends at the first line that is not part of it
            let q = fenced ? nil : quoteRX.firstMatch(in: t, range: all)
            if q == nil, let open = quote {
                decos.append(Decoration(kind: open.tint.map { Decoration.Kind.callout($0) } ?? Decoration.Kind.quote, range: NSRange(location: open.start, length: open.end - open.start)))
                quote = nil
            }

            if trimmed.hasPrefix("```") {                       // a code block: the fences vanish, the block gets a tinted panel
                if fenced { decos.append(Decoration(kind: .code, range: NSRange(location: fenceStart, length: NSMaxRange(r) - fenceStart))); fenced = false }
                else { fenced = true; fenceStart = r.location }
                hide(all); continue
            }
            if fenced { s.addAttributes([.font: font(13, mono: true), .foregroundColor: ink], range: r); continue }

            if trimmed.hasPrefix("|") {                          // a table: monospaced, faint bars, a rule under the header
                let first = !inTable; inTable = true
                if trimmed.contains("-"), trimmed.range(of: #"^\|?[\s:\-|]+\|?$"#, options: .regularExpression) != nil {
                    hide(all); decos.append(Decoration(kind: .tableRule, range: r)); continue
                }
                s.addAttribute(.font, value: font(13, first ? .bold : .regular, mono: true), range: r)
                for (i, ch) in t.utf16.enumerated() where ch == 124 { s.addAttribute(.foregroundColor, value: faint, range: at(NSRange(location: i, length: 1))) }
                continue
            } else { inTable = false }

            if let h = headingRX.firstMatch(in: t, range: all) {
                let sizes: [CGFloat] = [30, 24, 20, 17, 16, 15]
                s.addAttributes([.font: font(sizes[h.range(at: 1).length - 1], .bold), .paragraphStyle: paragraph(before: 10)], range: r)
                hide(h.range, leading: true)
                inline(r, t, s); continue
            }
            if ruleRX.firstMatch(in: t, range: all) != nil { hide(all); decos.append(Decoration(kind: .rule, range: r)); continue }

            var start = 0
            var indent: CGFloat = 0
            if let q {
                start = q.range.length; indent = 14
                hide(q.range, leading: true)
                var color = quote?.tint
                if let c = calloutRX.firstMatch(in: t, range: NSRange(location: start, length: len - start)), c.range.location == start {
                    color = tint(ns.substring(with: NSRange(location: r.location + c.range(at: 2).location, length: c.range(at: 2).length)))
                    hide(NSRange(location: c.range.location, length: c.range.length), leading: true)
                    start = NSMaxRange(c.range)
                    trait(.boldFontMask, at(NSRange(location: start, length: len - start)), s)    // the callout's title
                }
                quote = (start: quote?.start ?? r.location, end: NSMaxRange(r), tint: color)
            }

            var first = indent, head = indent
            let body = NSRange(location: start, length: len - start)
            if let c = checkRX.firstMatch(in: t, range: body) {
                let done = ns.substring(with: NSRange(location: r.location + c.range(at: 3).location, length: 3)).lowercased() == "[x]"
                let box = c.range(at: 3)
                first = indent + CGFloat(c.range(at: 1).length) * 7; head = first + 30
                hide(NSRange(location: c.range.location, length: box.location - c.range.location), leading: true)       // indent, "- "
                s.addAttributes([.foregroundColor: NSColor.clear, .font: font(12, mono: true)], range: at(NSRange(location: box.location, length: NSMaxRange(c.range) - box.location)))
                lead(NSRange(location: box.location, length: NSMaxRange(c.range) - box.location))
                decos.append(Decoration(kind: .checkbox(done), range: at(box)))
                if done { s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: ink2], range: at(NSRange(location: NSMaxRange(c.range), length: len - NSMaxRange(c.range)))) }
            } else if let b = bulletRX.firstMatch(in: t, range: body) {
                let dash = b.range(at: 2)
                first = indent + CGFloat(b.range(at: 1).length) * 7; head = first + 14
                hide(b.range(at: 1), leading: true)
                s.addAttribute(.foregroundColor, value: NSColor.clear, range: at(dash))
                lead(NSRange(location: dash.location, length: NSMaxRange(b.range) - dash.location))
                decos.append(Decoration(kind: .bullet, range: at(dash)))
            } else if let n = numberRX.firstMatch(in: t, range: body) {
                first = indent + CGFloat(n.range(at: 1).length) * 7; head = first + 22
                hide(n.range(at: 1), leading: true)
                s.addAttributes([.foregroundColor: accent, .font: font(15, .semibold)], range: at(n.range(at: 2)))
                lead(NSRange(location: n.range(at: 2).location, length: NSMaxRange(n.range) - n.range(at: 2).location))
            }
            if first != 0 || head != 0 { s.addAttribute(.paragraphStyle, value: paragraph(first: first, head: head), range: r) }
            inline(r, t, s)
        }
        if let open = quote { decos.append(Decoration(kind: open.tint.map { Decoration.Kind.callout($0) } ?? Decoration.Kind.quote, range: NSRange(location: open.start, length: open.end - open.start))) }
        if fenced { decos.append(Decoration(kind: .code, range: NSRange(location: fenceStart, length: ns.length - fenceStart))) }
        s.endEditing()
        for lm in s.layoutManagers {
            lm.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            lm.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        }
        return decos
    }

    private static func trait(_ mask: NSFontTraitMask, _ range: NSRange, _ s: NSTextStorage) {
        guard range.length > 0 else { return }
        var runs: [(NSFont, NSRange)] = []
        s.enumerateAttribute(.font, in: range) { v, rr, _ in if let f = v as? NSFont { runs.append((f, rr)) } }
        for (f, rr) in runs { s.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: mask), range: rr) }
    }

    /// Bold, italic, code, highlight and links inside a line. Their marks are hidden; what they wrap is styled.
    private static func inline(_ r: NSRange, _ t: String, _ s: NSTextStorage) {
        let all = NSRange(location: 0, length: (t as NSString).length)
        func at(_ x: NSRange) -> NSRange { NSRange(location: r.location + x.location, length: x.length) }
        func hide(_ loc: Int, _ len: Int) { if len > 0 { s.addAttribute(hiddenKey, value: true, range: NSRange(location: r.location + loc, length: len)) } }
        func around(_ m: NSTextCheckingResult, _ n: Int) { hide(m.range.location, n); hide(NSMaxRange(m.range) - n, n) }
        func each(_ re: NSRegularExpression, _ f: (NSTextCheckingResult) -> Void) { for m in re.matches(in: t, range: all) { f(m) } }

        each(codeRX) { m in
            s.addAttributes([.font: font(13, mono: true), .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)], range: at(m.range(at: 1)))
            around(m, 1)
        }
        each(boldRX) { m in trait(.boldFontMask, at(m.range(at: 1)), s); around(m, 2) }
        each(italicRX) { m in trait(.italicFontMask, at(m.range(at: 1)), s); around(m, 1) }
        each(strikeRX) { m in
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: at(m.range(at: 1)))
            around(m, 2)
        }
        each(markRX) { m in
            s.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), range: at(m.range(at: 1)))
            around(m, 2)
        }
        each(wikiRX) { m in         // [[note]] and ![[file]] show the name; [[note|alias]] shows the alias
            let alias = m.range(at: 4)
            let shown = alias.location != NSNotFound ? alias : m.range(at: 2)
            s.addAttribute(.foregroundColor, value: accent, range: at(shown))
            hide(m.range.location, shown.location - m.range.location)
            hide(NSMaxRange(shown), NSMaxRange(m.range) - NSMaxRange(shown))
        }
        each(linkRX) { m in         // [text](url) shows the text
            let text = m.range(at: 1)
            s.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: at(text))
            hide(m.range.location, 1)
            hide(NSMaxRange(text), NSMaxRange(m.range) - NSMaxRange(text))
        }
    }
}

/// The floating toolbar over the document: text style, checklist, table, attachment, link, dictation.
struct EditorToolbar: View {
    let editor: EditorController
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Title") { editor.linePrefix("# ") }
                Button("Heading") { editor.linePrefix("## ") }
                Button("Subheading") { editor.linePrefix("### ") }
                Button("Body") { editor.linePrefix("") }
                Divider()
                Button("Bold") { editor.wrap("**") }
                Button("Italic") { editor.wrap("*") }
                Button("Strikethrough") { editor.wrap("~~") }
                Button("Highlight") { editor.wrap("==") }
                Button("Code") { editor.wrap("`") }
                Divider()
                Button("Bulleted list") { editor.linePrefix("- ") }
                Button("Numbered list") { editor.linePrefix("1. ") }
                Button("Quote") { editor.linePrefix("> ") }
            } label: { Text("Aa").font(.system(size: 18)).frame(width: 48, height: 36).contentShape(.rect) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Text style")
            tool("checklist", "Checklist") { editor.linePrefix("- [ ] ") }
            tool("tablecells", "Table") { editor.block("| Column | Column |\n| --- | --- |\n|  |  |") }
            tool("paperclip", "Attach a file") { attach() }
            tool("link", "Link to a note") { editor.wrap("[[", "]]") }
            tool("waveform.circle", "Dictate: speak and it types into the note") { editor.focus(); Dictation.start() }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
    }

    func tool(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17)).frame(width: 44, height: 36).contentShape(.rect) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    /// Copies files into the vault's Unsorted folder (the Sorter files them later) and links them in the note by name, as Obsidian does.
    func attach() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let fm = FileManager.default
        let dir = Vault.root.appending(path: "Unsorted")
        var links: [String] = []
        for src in panel.urls {
            var dest = dir.appending(path: src.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = dir.appending(path: src.deletingPathExtension().lastPathComponent + " \(n)." + src.pathExtension); n += 1
            }
            do { try fm.copyItem(at: src, to: dest); links.append("![[\(dest.lastPathComponent)]]") }
            catch { store.error = error.localizedDescription }
        }
        guard !links.isEmpty else { return }
        editor.insert(links.joined(separator: "\n") + "\n")
        store.reload()
    }
}
