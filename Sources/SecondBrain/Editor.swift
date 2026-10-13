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
    /// Called with the target of a link that was Command-clicked in the text: a note's name, a file, or a web address.
    var openLink: (@MainActor (String) -> Void)?

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

    /// Puts an edit in and moves the selection to where the rules in `EditorLogic` say.
    private func apply(_ result: (edit: EditorLogic.Edit, selection: NSRange)?) {
        guard let result, let tv = textView else { return }
        replace(result.edit.range, with: result.edit.text)
        tv.setSelectedRange(result.selection)
    }

    /// Wraps the selection in marks, takes them off again if they are already there, or drops a pair at the cursor to type into.
    func wrap(_ open: String, _ close: String? = nil) {
        guard let tv = textView else { return }
        focus()
        apply(EditorLogic.wrap(tv.string, selection: tv.selectedRange(), open: open, close: close ?? open))
    }

    /// Sets the prefix (a heading, list or quote) of every selected line; choosing the same one again removes it.
    func linePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        focus()
        apply(EditorLogic.linePrefix(tv.string, selection: tv.selectedRange(), prefix: prefix))
    }

    /// Puts text at the cursor, replacing any selection.
    func insert(_ s: String) {
        guard let tv = textView else { return }
        focus()
        let sel = tv.selectedRange()
        replace(sel, with: s)
        tv.setSelectedRange(NSRange(location: sel.location + (s as NSString).length, length: 0))
    }

    /// Puts a block (a table, a divider) on its own lines after the selection. A table has the caret put in its first cell.
    func block(_ s: String, focusTable: Bool = false) {
        guard let tv = textView else { return }
        focus()
        let ns = tv.string as NSString
        let at = NSMaxRange(tv.selectedRange())
        let before = at == 0 || ns.substring(with: NSRange(location: at - 1, length: 1)) == "\n" ? "" : "\n"
        let text = before + s + "\n"
        replace(NSRange(location: at, length: 0), with: text)
        tv.setSelectedRange(NSRange(location: at + (text as NSString).length, length: 0))
        if focusTable { let loc = at + (before as NSString).length; Task { @MainActor [weak tv] in tv?.focusTable(at: loc) } }
    }
}

/// The text view. It draws what the Markdown stands for (bullets, checkboxes, callout boxes, rules), adds the shortcuts, and ticks a checkbox on click.
final class MDTextView: NSTextView {
    weak var controller: EditorController?
    var decorations: [MarkdownStyler.Decoration] = []
    /// The tables drawn as grids (see EditorTables.swift): where each is in the text, and its view.
    var tableBlocks: [MarkdownStyler.TableBlock] = []
    var tableViews: [TableGridView] = []
    var positioningTables = false

    /// Styles the text and keeps the drawn extras in step with it.
    func restyle() {
        guard let storage = textStorage else { return }
        decorations = MarkdownStyler.apply(to: storage)
        syncTables()
        needsDisplay = true
    }

    /// Restyles only `window`, a few lines around an edit that changed the text's length by `delta`. What is drawn before the window stays, what is drawn
    /// after it moves along with the text, and what was inside it is replaced.
    func restyle(window: NSRange, delta: Int) {
        guard let storage = textStorage else { return }
        let oldEnd = NSMaxRange(window) - delta
        let kept = decorations.compactMap { d -> MarkdownStyler.Decoration? in
            if NSMaxRange(d.range) <= window.location { return d }
            if d.range.location >= oldEnd { return MarkdownStyler.Decoration(kind: d.kind, range: NSRange(location: d.range.location + delta, length: d.range.length)) }
            return nil
        }
        decorations = kept + MarkdownStyler.apply(to: storage, in: window)
        if !tableViews.isEmpty { tableBlocks = MarkdownStyler.tableBlocks(in: string as NSString) }      // the tables moved with the text
        needsDisplay = true
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    /// Bold, italic and link as in Notes; the paragraph styles use Notes' shortcuts too (Title, Heading, Subheading and Body are Shift-Command T, H, J and B;
    /// Shift-Command 7 is a bulleted list and 9 a numbered one; Command ' is a block quote).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder is TableCellView { return super.performKeyEquivalent(with: event) }      // the cell formats its own text
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let k = event.charactersIgnoringModifiers?.lowercased() {
            if flags == .command {
                switch k {
                case "b": controller?.wrap("**"); return true
                case "i": controller?.wrap("*"); return true
                case "k": controller?.wrap("[[", "]]"); return true
                case "'": controller?.linePrefix("> "); return true
                default: break
                }
            } else if flags == [.command, .shift] {
                switch k {
                case "t": controller?.linePrefix("# "); return true
                case "h": controller?.linePrefix("## "); return true
                case "j": controller?.linePrefix("### "); return true
                case "b": controller?.linePrefix(""); return true
                default: break
                }
                switch event.keyCode {      // the number row, whatever the keyboard layout calls the keys
                case 26: controller?.linePrefix("- "); return true
                case 25: controller?.linePrefix("1. "); return true
                default: break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// A click on a checkbox ticks it (in a callout too), Command-click on a link follows it, anywhere else places the cursor as usual.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let lm = layoutManager, let tc = textContainer {
            if event.modifierFlags.contains(.command), let target = link(at: p) { controller?.openLink?(target); return }
            let o = textContainerOrigin, ns = string as NSString
            for d in decorations {
                guard case .checkbox = d.kind, NSMaxRange(d.range) <= ns.length else { continue }
                let gr = lm.glyphRange(forCharacterRange: d.range, actualCharacterRange: nil)
                guard gr.length > 0 else { continue }
                var b = lm.boundingRect(forGlyphRange: gr, in: tc)
                b.origin.x += o.x; b.origin.y += o.y
                guard NSRect(x: b.minX - 3, y: b.midY - 12, width: 27, height: 24).contains(p) else { continue }
                let now = ns.substring(with: d.range) == "[ ]" ? "[x]" : "[ ]"
                if shouldChangeText(in: d.range, replacementString: now) { replaceCharacters(in: d.range, with: now); didChangeText() }
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// The target of the `[[note]]` or `[text](address)` under the point, if there is one.
    private func link(at p: NSPoint) -> String? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let o = textContainerOrigin
        var fraction: CGFloat = 0
        let i = lm.characterIndex(for: NSPoint(x: p.x - o.x, y: p.y - o.y), in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let ns = string as NSString
        guard i >= 0, i < ns.length else { return nil }
        let lr = ns.lineRange(for: NSRange(location: i, length: 0))
        let line = ns.substring(with: lr) as NSString
        let all = NSRange(location: 0, length: line.length), at = i - lr.location
        for re in [MarkdownStyler.wikiRX, MarkdownStyler.linkRX] {
            for m in re.matches(in: line as String, range: all) where NSLocationInRange(at, m.range) { return line.substring(with: m.range(at: 2)) }
        }
        return nil
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
            case .rule:
                MarkdownStyler.faint.setFill()
                NSBezierPath(rect: NSRect(x: o.x, y: b.midY, width: width, height: 1)).fill()
            case .tableRow(let header, let inset):   // a tinted header and a faint line under every row; inside a callout the table sits in from the bar
                let x = o.x + inset, w = width - inset - (inset > 0 ? 14 : 0)
                let row = NSRect(x: x, y: b.minY - 2, width: w, height: b.height + 4)
                if header { MarkdownStyler.accent.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: row, xRadius: 6, yRadius: 6).fill() }
                MarkdownStyler.faint.withAlphaComponent(header ? 1 : 0.55).setFill()
                NSBezierPath(rect: NSRect(x: x, y: row.maxY - 1, width: w, height: 1)).fill()
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
    /// The whole note, frontmatter and all. The editor shows and changes only what comes after the frontmatter, and writes the rest back as it was.
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
        let (front, body) = NoteText.split(text)
        context.coordinator.front = front
        tv.string = body
        tv.restyle()
        controller.textView = tv
        return tv
    }

    func updateNSView(_ tv: MDTextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        controller.textView = tv
        guard c.front + tv.string != text else { return }      // that is what the editor itself last wrote
        let (front, body) = NoteText.split(text)
        c.front = front
        guard tv.string != body else { return }                // only the frontmatter changed (a property in the side panel)
        // The note changed under the editor (another version restored, an agent's edit, another note opened here). Its undo steps point into the old
        // text, so they go too: undoing one would reach for characters that are no longer there.
        let sel = tv.selectedRange()
        tv.string = body
        tv.undoManager?.removeAllActions()
        tv.restyle()
        tv.setSelectedRange(NSRange(location: min(sel.location, (body as NSString).length), length: 0))
    }

    /// The text view grows with its text, so the page's own scroll view scrolls the title and the text together.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: MDTextView, context: Context) -> CGSize? {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let w = max(proposal.width ?? 600, 100)
        tc.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        tv.updateTableHeights()      // the tables' gaps are as tall as their grids need at this width
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        return CGSize(width: w, height: max(h + 140, 360))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSLayoutManagerDelegate {
        var parent: MarkdownEditor
        /// The note's frontmatter (and the blank line after it), kept apart from the text view and put back in front of it on every change.
        var front = ""
        init(_ parent: MarkdownEditor) { self.parent = parent }

        /// Up to this many characters the whole text is styled on every keystroke, which is exact and cheap. Past it, an edit inside one line restyles only
        /// the lines around it, and anything else waits for a pause in typing. A full pass always follows a pause, so nothing stays wrong for long.
        private static let wholeTextLimit = 5_000
        private var restyleTask: Task<Void, Never>?
        private var pendingEdit: (location: Int, removed: Int, added: Int)?

        /// Called before each change: remembers a change that stays inside one line (nothing with a line break going in or coming out).
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            let ns = tv.string as NSString, added = text ?? ""
            let inOneLine = !added.contains("\n") && NSMaxRange(range) <= ns.length && range.length <= 500 && !ns.substring(with: range).contains("\n")
            pendingEdit = inOneLine ? (range.location, range.length, (added as NSString).length) : nil
            return true
        }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? MDTextView else { return }
            let edit = pendingEdit; pendingEdit = nil
            restyleTask?.cancel()
            if !tv.hasMarkedText() {
                let length = tv.textStorage?.length ?? 0
                if length <= Self.wholeTextLimit { tv.restyle() }
                else if let edit, let window = Self.window(in: tv.string as NSString, around: NSRange(location: edit.location, length: edit.added)) {
                    tv.restyle(window: window, delta: edit.added - edit.removed)
                    after(milliseconds: 700, tv)
                } else { after(milliseconds: 150, tv) }
            }
            parent.text = front + tv.string
        }

        private func after(milliseconds: Int, _ tv: MDTextView) {
            restyleTask = Task { [weak tv] in try? await Task.sleep(for: .milliseconds(milliseconds)); if !Task.isCancelled { tv?.restyle() } }
        }

        /// The edited line with the one before and the one after, to restyle on its own. Nil when any of them could be part of something that spans lines
        /// (a code fence, a table, a quote or callout) or sits inside an open code fence, so the whole text has to be styled again.
        static func window(in ns: NSString, around edit: NSRange) -> NSRange? {
            guard ns.length > 0 else { return nil }
            let at = min(edit.location, ns.length - 1)
            var lines = [ns.lineRange(for: NSRange(location: at, length: 0))]
            if lines[0].location > 0 { lines.insert(ns.lineRange(for: NSRange(location: lines[0].location - 1, length: 0)), at: 0) }
            if let last = lines.last, NSMaxRange(last) < ns.length { lines.append(ns.lineRange(for: NSRange(location: NSMaxRange(last), length: 0))) }
            guard let first = lines.first, let last = lines.last else { return nil }
            for l in lines {
                let t = ns.substring(with: l).trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("```") || t.hasPrefix("|") || t.hasPrefix(">") { return nil }
            }
            var fences = 0, from = 0
            while from < first.location {
                let r = ns.range(of: "```", options: [], range: NSRange(location: from, length: first.location - from))
                if r.location == NSNotFound { break }
                fences += 1; from = NSMaxRange(r)
            }
            return fences % 2 == 0 ? NSRange(location: first.location, length: NSMaxRange(last) - first.location) : nil
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

        /// Once the text is laid out, each table's grid goes over its gap.
        func layoutManager(_ lm: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
            guard layoutFinishedFlag, let tv = lm.firstTextView as? MDTextView, !tv.tableViews.isEmpty else { return }
            Task { @MainActor [weak tv] in tv?.positionTables() }
        }

        private func run(_ key: NSAttributedString.Key, at i: Int, in st: NSTextStorage) -> NSRange? {
            guard i >= 0, i < st.length else { return nil }
            var r = NSRange()
            return st.attribute(key, at: i, longestEffectiveRange: &r, in: NSRange(location: 0, length: st.length)) != nil ? r : nil
        }

        /// The cursor never rests inside a hidden mark: the marks in front of a line's text (the `## ` of a heading, a bullet) are skipped,
        /// and so are the marks around a word. An arrow key pressed once has to move past something you can see: Left from the start of a line's
        /// text goes to the end of the line above, and Left or Right next to a word's hidden marks goes over the marks and the letter beside them.
        func textView(_ tv: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0, let st = tv.textStorage, st.length > 0 else { return new }
            let ns = st.string as NSString
            // A table's lines are hidden under its grid, so the caret never rests in them: arriving from above or below, the grid takes it; anywhere else it goes past the table.
            if let mtv = tv as? MDTextView, let k = mtv.tableBlocks.firstIndex(where: { new.location >= $0.content.location && new.location <= NSMaxRange($0.content) }), k < mtv.tableViews.count {
                let b = mtv.tableBlocks[k]
                let above = old.location < b.content.location, below = old.location > NSMaxRange(b.content)
                guard above || below else { return NSRange(location: min(NSMaxRange(b.content) + 1, st.length), length: 0) }
                let grid = mtv.tableViews[k]
                Task { @MainActor [weak grid] in grid?.focusCell(row: above ? 0 : max(grid?.model.cells.count ?? 1, 1) - 1, col: 0, selectAll: true) }
                return old
            }
            let movingBack = new.location < old.location
            var loc = min(new.location, st.length)
            var step = old.length == 0 ? loc - old.location : 0        // -1 or 1 for one press of an arrow key; anything else is a click or a bigger jump
            for _ in 0..<3 {
                let settled = snap(loc, movingBack: movingBack, step: step, from: old.location, in: st, ns)
                if settled == loc { break }
                loc = settled; step = 0
            }
            return NSRange(location: loc, length: 0)
        }

        private func snap(_ loc: Int, movingBack: Bool, step: Int, from old: Int, in st: NSTextStorage, _ ns: NSString) -> Int {
            let line = ns.lineRange(for: NSRange(location: min(loc, st.length - 1), length: 0))
            if let lead = run(MarkdownStyler.leadingKey, at: line.location, in: st), lead.location == line.location, loc < NSMaxRange(lead) {
                return step == -1 && old == NSMaxRange(lead) && line.location > 0 ? line.location - 1 : NSMaxRange(lead)
            }
            if let h = run(MarkdownStyler.hiddenKey, at: loc, in: st), h.location < loc {
                if step == -1, old == NSMaxRange(h) { return h.location > 0 ? ns.rangeOfComposedCharacterSequence(at: h.location - 1).location : 0 }
                if step == 1, old == h.location { return NSMaxRange(h) < ns.length ? NSMaxRange(ns.rangeOfComposedCharacterSequence(at: NSMaxRange(h))) : NSMaxRange(h) }
                return movingBack ? h.location : NSMaxRange(h)
            }
            return loc
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
                if ns.character(at: line.location) == 32, indent(tv, -1) { return true }       // a nested item steps out a level before its mark goes
                remove(lead, in: tv); return true
            }
            if let h = run(MarkdownStyler.hiddenKey, at: sel.location - 1, in: st) {
                guard h.location > 0 else { return true }
                let r = ns.rangeOfComposedCharacterSequence(at: h.location - 1)
                remove(r, in: tv)
                tv.setSelectedRange(NSRange(location: r.location, length: 0))
                dropEmptyMarks(tv)
                return true
            }
            return false
        }

        /// Taking the last letter out of a bold (or italic, highlighted, code) word takes its marks away too, so no bare `****` is left behind.
        private func dropEmptyMarks(_ tv: NSTextView) {
            guard let edit = EditorLogic.emptyMarks(in: tv.string, at: tv.selectedRange().location) else { return }
            remove(edit.range, in: tv)
            tv.setSelectedRange(NSRange(location: edit.range.location, length: 0))
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
            // Return in a table adds a row under it; Return on an empty row ends the table
            if let row = tableRow(line) {
                if ls.substring(from: row.cut).allSatisfy({ $0 == "|" || $0 == " " || $0 == "\t" }) {
                    remove(NSRange(location: lr.location + row.cut, length: ls.length - row.cut), in: tv)
                } else { addRow(tv, line: line, lineStart: lr.location, cut: row.cut, pipes: row.pipes) }
                return true
            }
            var prefix = "", next = "", numbered = false
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
                numbered = true
            } else { return false }
            let prefixLen = (prefix as NSString).length
            guard sel.location - lr.location >= prefixLen else { return false }       // the cursor is inside the mark itself
            if line.trimmingCharacters(in: .whitespaces).count == prefix.trimmingCharacters(in: .whitespaces).count {
                if line.hasPrefix(" "), indent(tv, -1) { return true }                  // an empty nested item steps out a level first
                remove(NSRange(location: lr.location, length: prefixLen), in: tv)      // nothing after the mark: end the list
                return true
            }
            tv.insertText("\n" + next, replacementRange: sel)
            if numbered { renumber(tv) }
            return true
        }

        /// The numbered items under the one just added count on from it.
        private func renumber(_ tv: NSTextView) {
            let line = (tv.string as NSString).lineRange(for: NSRange(location: tv.selectedRange().location, length: 0))
            guard let edit = EditorLogic.renumber(tv.string, fromLine: line) else { return }
            let keep = tv.selectedRange()
            if tv.shouldChangeText(in: edit.range, replacementString: edit.text) { tv.replaceCharacters(in: edit.range, with: edit.text); tv.didChangeText() }
            tv.setSelectedRange(keep)
        }

        // MARK: Tables
        /// A table row's quote marks (their length) and where its `|` marks are on the line; nil when the line is not a table row.
        private func tableRow(_ line: String) -> (cut: Int, pipes: [Int])? {
            let ns = line as NSString
            let cut = MarkdownStyler.quoteRX.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
            guard ns.substring(from: cut).trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return nil }
            return (cut, MarkdownStyler.pipePositions(in: ns, from: cut))
        }

        /// A new empty row under the one the cursor is on, with the same number of columns and the same quote marks; the cursor goes into its first cell.
        private func addRow(_ tv: NSTextView, line: String, lineStart: Int, cut: Int, pipes: [Int]) {
            let trailing = line.trimmingCharacters(in: .whitespaces).hasSuffix("|")
            let columns = max(trailing ? pipes.count - 1 : pipes.count, 1)
            let end = lineStart + (line as NSString).length
            tv.insertText("\n" + (line as NSString).substring(to: cut) + "|" + String(repeating: "  |", count: columns), replacementRange: NSRange(location: end, length: 0))
            tv.setSelectedRange(NSRange(location: end + 1 + cut + 2, length: 0))
        }

        /// Tab goes to the next cell (the last cell's Tab adds a row), Shift-Tab to the one before.
        func tableCell(_ tv: NSTextView, _ dir: Int) -> Bool {
            let sel = tv.selectedRange(), ns = tv.string as NSString
            let lr = ns.lineRange(for: sel)
            let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            guard let row = tableRow(line), !row.pipes.isEmpty else { return false }
            let c = sel.location - lr.location
            let k = row.pipes.firstIndex { $0 >= c } ?? row.pipes.count           // the pipe that ends the cell the cursor is in
            let trailing = line.trimmingCharacters(in: .whitespaces).hasSuffix("|")
            /// The caret position inside the cell that starts after `pipe` on the line at `at`: past the pipe and the space after it.
            func inside(_ at: NSRange, _ pipe: Int) -> Int {
                var p = at.location + pipe + 1
                if p < ns.length, ns.character(at: p) == 32 { p += 1 }
                return p
            }
            /// The next or previous row of this table that holds cells (the `| --- |` line is skipped), with its pipes.
            func neighbour(_ forward: Bool) -> (range: NSRange, pipes: [Int])? {
                var at = forward ? NSMaxRange(lr) : lr.location - 1
                while at >= 0, at < ns.length {
                    let r = ns.lineRange(for: NSRange(location: at, length: 0))
                    let l = ns.substring(with: r).trimmingCharacters(in: .newlines)
                    guard let t = tableRow(l) else { return nil }
                    if !MarkdownStyler.isTableSeparator((l as NSString).substring(from: t.cut)) { return (r, t.pipes) }
                    at = forward ? NSMaxRange(r) : r.location - 1
                }
                return nil
            }
            if dir > 0 {
                if k < (trailing ? row.pipes.count - 1 : row.pipes.count) { tv.setSelectedRange(NSRange(location: inside(lr, row.pipes[k]), length: 0)) }
                else if let next = neighbour(true), let first = next.pipes.first { tv.setSelectedRange(NSRange(location: inside(next.range, first), length: 0)) }
                else { addRow(tv, line: line, lineStart: lr.location, cut: row.cut, pipes: row.pipes) }
            } else if k >= 2 {
                tv.setSelectedRange(NSRange(location: inside(lr, row.pipes[k - 2]), length: 0))
            } else if let prev = neighbour(false) {
                let starts = (ns.substring(with: prev.range).trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("|")) ? Array(prev.pipes.dropLast()) : prev.pipes
                if let last = starts.last { tv.setSelectedRange(NSRange(location: inside(prev.range, last), length: 0)) }
            }
            return true
        }

        /// Tab and Shift-Tab move between a table's cells, and nest and un-nest every selected list item.
        func indent(_ tv: NSTextView, _ dir: Int) -> Bool {
            if tableCell(tv, dir) { return true }
            if let (edit, sel) = EditorLogic.indent(tv.string, selection: tv.selectedRange(), by: dir) {
                if tv.shouldChangeText(in: edit.range, replacementString: edit.text) { tv.replaceCharacters(in: edit.range, with: edit.text); tv.didChangeText() }
                tv.setSelectedRange(sel)
                return true
            }
            return tv.selectedRange().length > 0       // Tab never replaces a selected passage with a tab character
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
        enum Kind { case bullet, checkbox(Bool), callout(NSColor), quote, code, rule, tableRow(header: Bool, inset: CGFloat) }
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
    static let headingRX = rx(#"^(#{1,6})[ \t]+"#)
    static let ruleRX = rx(#"^\s*(-{3,}|\*{3,}|_{3,})\s*$"#)
    static let quoteRX = rx(#"^(\s*>[ \t]?)+"#)
    static let checkRX = rx(#"^(\s*)([-*+])[ \t](\[[ xX]\])[ \t]"#)
    static let bulletRX = rx(#"^(\s*)([-*+])[ \t]"#)
    static let numberRX = rx(#"^(\s*)(\d+[.)])[ \t]"#)
    private static let calloutRX = rx(#"(\[!([A-Za-z]+)\][+-]?)[ \t]*"#)
    private static let codeRX = rx(#"`([^`\n]+)`"#)
    private static let boldItalicRX = rx(#"\*\*\*([^*\n]+)\*\*\*"#)
    private static let boldRX = rx(#"\*\*([^*\n]+)\*\*"#)
    private static let italicRX = rx(#"(?<![*\w])\*([^*\n]+)\*(?![*\w])"#)
    private static let strikeRX = rx(#"~~([^~\n]+)~~"#)
    private static let markRX = rx(#"==([^=\n]+)=="#)
    static let wikiRX = rx(#"(!?)\[\[([^\]\n|]+)(\|([^\]\n]+))?\]\]"#)
    static let linkRX = rx(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#)

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

    /// Styles the whole text, or only `window` (whole lines, none of them inside a code fence, table or quote): the extras to draw are returned for that part only.
    @discardableResult
    static func apply(to s: NSTextStorage, in window: NSRange? = nil) -> [Decoration] {
        let ns = s.string as NSString
        let full = window ?? NSRange(location: 0, length: ns.length)
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, r, _, _ in lines.append(r) }

        var decos: [Decoration] = []
        var fenced = false, fenceStart = 0, inTable = false
        var quote: (start: Int, end: Int, tint: NSColor?)? = nil

        s.beginEditing()
        s.setAttributes([.font: font(baseSize), .foregroundColor: ink, .paragraphStyle: paragraph()], range: full)
        var widths: [Int] = []      // the table's column widths, in characters
        // the lines of the tables that are drawn as grids: the first line holds the gap the grid sits over, the others take no room
        var gridLines: [Int: (ordinal: Int, first: Bool)] = [:]
        for (k, b) in tableBlocks(in: ns).enumerated() { for (i, l) in b.lines.enumerated() { gridLines[l.location] = (k, i == 0) } }
        for (idx, r) in lines.enumerated() {
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

            // a table with a header and a `| --- |` line is a grid laid over the text: its characters are hidden
            if let g = gridLines[r.location] {
                inTable = false
                if let q {
                    hide(q.range, leading: true)
                    quote = (start: quote?.start ?? r.location, end: NSMaxRange(r), tint: quote?.tint)
                }
                hide(all)
                s.addAttributes([.font: font(g.first ? 12 : 1), .paragraphStyle: g.first ? gridParagraph(height: tableHeights[g.ordinal] ?? 90) : collapsedLine], range: ns.lineRange(for: r))
                continue
            }

            // any other table: monospaced, columns lined up, a faint line under each row. Inside a quote or callout the row sits after the `>` marker.
            let cut = q?.range.length ?? 0
            let rowRange = NSRange(location: cut, length: len - cut)
            let row = (t as NSString).substring(with: rowRange)
            if row.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                let first = !inTable; inTable = true
                if first { widths = columnWidths(lines: lines, from: idx, in: ns) }
                if let q {
                    hide(q.range, leading: true)
                    quote = (start: quote?.start ?? r.location, end: NSMaxRange(r), tint: quote?.tint)
                }
                if isTableSeparator(row) {   // the `| --- |` line is not shown, and takes no height
                    hide(all)
                    let collapsed = NSMutableParagraphStyle()
                    collapsed.lineSpacing = 0; collapsed.paragraphSpacing = 0; collapsed.paragraphSpacingBefore = 0; collapsed.maximumLineHeight = 1; collapsed.minimumLineHeight = 1
                    s.addAttributes([.font: font(1), .paragraphStyle: collapsed], range: ns.lineRange(for: r))
                    continue
                }
                let inset: CGFloat = q == nil ? 0 : 14
                s.addAttribute(.font, value: font(13, first ? .bold : .regular, mono: true), range: at(rowRange))
                // the whole line, as every other kind of line does: a paragraph takes its style from its first character, which in a callout is the hidden `>`
                s.addAttribute(.paragraphStyle, value: paragraph(first: inset, head: inset, before: 3), range: r)
                let rowNS = row as NSString, pipes = pipePositions(in: rowNS, from: 0)
                for p in pipes { s.addAttribute(.foregroundColor, value: faint, range: at(NSRange(location: cut + p, length: 1))) }
                inline(r, t, s)
                // pad each cell with space after its text so the columns line up (the characters themselves never change)
                for k in stride(from: 1, to: pipes.count, by: 1) where k - 1 < widths.count {
                    let cell = rowNS.substring(with: NSRange(location: pipes[k - 1] + 1, length: pipes[k] - pipes[k - 1] - 1))
                    let extra = widths[k - 1] - shownLength(cell)
                    if extra > 0, !cell.isEmpty { s.addAttribute(.kern, value: CGFloat(extra) * monoAdvance, range: at(NSRange(location: cut + pipes[k] - 1, length: 1))) }
                }
                decos.append(Decoration(kind: .tableRow(header: first, inset: inset), range: r))
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

            // a heading inside a quote or callout (`> ### Before the tutorial`): sized and bold, its `#` marks hidden
            if q != nil, let h = headingRX.firstMatch(in: t, range: NSRange(location: start, length: len - start)) {
                let sizes: [CGFloat] = [20, 18, 16.5, 15.5, 15, 15]
                s.addAttributes([.font: font(sizes[h.range(at: 1).length - 1], .bold), .paragraphStyle: paragraph(first: indent, head: indent, before: 6)], range: at(NSRange(location: start, length: len - start)))
                hide(h.range, leading: true)
                inline(r, t, s); continue
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

    // MARK: Tables
    /// The width of one character of the table font, which every cell is padded in multiples of.
    private static var monoAdvance: CGFloat { (" " as NSString).size(withAttributes: [.font: font(13, mono: true)]).width }
    /// Where the `|` marks are in `ns` from `from` on (a `\|` is part of a cell, not a divider).
    static func pipePositions(in ns: NSString, from: Int) -> [Int] {
        var out: [Int] = []
        var i = from
        while i < ns.length {
            if ns.character(at: i) == 124, i == from || ns.character(at: i - 1) != 92 { out.append(i) }
            i += 1
        }
        return out
    }
    /// The `| --- | --- |` line under a table's header.
    static func isTableSeparator(_ row: String) -> Bool {
        row.contains("-") && row.trimmingCharacters(in: .whitespaces).range(of: #"^\|?[\s:\-|]+\|?$"#, options: .regularExpression) != nil
    }
    /// How many characters a cell shows: links show their name or alias and bold, code and highlight marks are hidden.
    private static func shownLength(_ cell: String) -> Int {
        var t = cell
        for (pattern, with) in [(#"\[\[[^\]|\\]+\\?\|([^\]]+)\]\]"#, "$1"), (#"\[\[([^\]]+)\]\]"#, "$1"), (#"\[([^\]]+)\]\([^)]+\)"#, "$1")] {
            t = t.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        for mark in ["**", "~~", "==", "`"] { t = t.replacingOccurrences(of: mark, with: "") }
        return t.count
    }
    /// The widest cell in each column over the rows of the table that starts at line `idx`.
    private static func columnWidths(lines: [NSRange], from idx: Int, in ns: NSString) -> [Int] {
        var widths: [Int] = []
        var i = idx
        while i < lines.count {
            let t = ns.substring(with: lines[i])
            let cut = quoteRX.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length))?.range.length ?? 0
            let row = (t as NSString).substring(from: cut)
            guard row.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { break }
            i += 1
            if isTableSeparator(row) { continue }
            let rowNS = row as NSString, pipes = pipePositions(in: rowNS, from: 0)
            for k in stride(from: 1, to: pipes.count, by: 1) {
                let n = shownLength(rowNS.substring(with: NSRange(location: pipes[k - 1] + 1, length: pipes[k] - pipes[k - 1] - 1)))
                if k - 1 < widths.count { widths[k - 1] = max(widths[k - 1], n) } else { widths.append(n) }
            }
        }
        return widths
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
        each(boldItalicRX) { m in trait(.boldFontMask, at(m.range(at: 1)), s); trait(.italicFontMask, at(m.range(at: 1)), s); around(m, 3) }
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
            tool("tablecells", "Table") { editor.block("|  |  |\n| --- | --- |\n|  |  |", focusTable: true) }
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
