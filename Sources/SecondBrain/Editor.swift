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

/// The text view. It adds the shortcuts and the click on a checkbox.
final class MDTextView: NSTextView {
    weak var controller: EditorController?

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

    /// A click on a "[ ]" or "[x]" ticks it, anywhere else places the cursor as usual.
    override func mouseDown(with event: NSEvent) {
        let i = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let ns = string as NSString
        if event.clickCount == 1, ns.length > 0 {
            let lr = ns.lineRange(for: NSRange(location: min(i, ns.length - 1), length: 0))
            let line = ns.substring(with: lr)
            if let m = MarkdownStyler.checkRX.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let box = NSRange(location: lr.location + m.range(at: 3).location, length: m.range(at: 3).length)
                if i >= box.location - 1, i <= NSMaxRange(box) {
                    let now = ns.substring(with: box) == "[ ]" ? "[x]" : "[ ]"
                    if shouldChangeText(in: box, replacementString: now) { replaceCharacters(in: box, with: now); didChangeText() }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MDTextView {
        let tv = MDTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
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
        if let storage = tv.textStorage { MarkdownStyler.apply(to: storage) }
        controller.textView = tv
        return tv
    }

    func updateNSView(_ tv: MDTextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = tv
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            if let storage = tv.textStorage { MarkdownStyler.apply(to: storage) }
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

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            if !tv.hasMarkedText(), let storage = tv.textStorage { MarkdownStyler.apply(to: storage) }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)): return newline(tv)
            case #selector(NSResponder.insertTab(_:)): return indent(tv, 1)
            case #selector(NSResponder.insertBacktab(_:)): return indent(tv, -1)
            default: return false
            }
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
            if let m = MarkdownStyler.checkRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range); next = ls.substring(with: m.range(at: 1)) + ls.substring(with: m.range(at: 2)) + " [ ] "
            } else if let m = MarkdownStyler.bulletRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range); next = prefix
            } else if let m = MarkdownStyler.numberRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range)
                let digits = ls.substring(with: m.range(at: 2))
                let n = (Int(digits.dropLast()) ?? 0) + 1
                next = ls.substring(with: m.range(at: 1)) + "\(n)" + String(digits.last ?? ".") + " "
            } else if let m = MarkdownStyler.quoteRX.firstMatch(in: line, range: all) {
                prefix = ls.substring(with: m.range); next = prefix
            } else { return false }
            let prefixLen = (prefix as NSString).length
            guard sel.location - lr.location >= prefixLen else { return false }       // the cursor is inside the mark itself
            if line.trimmingCharacters(in: .whitespaces).count == prefix.trimmingCharacters(in: .whitespaces).count {
                // nothing after the mark: take it off and leave an empty line
                if tv.shouldChangeText(in: NSRange(location: lr.location, length: prefixLen), replacementString: "") {
                    tv.replaceCharacters(in: NSRange(location: lr.location, length: prefixLen), with: "")
                    tv.didChangeText()
                }
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
            let lead = line.prefix { $0 == " " }.count
            let drop = min(lead, 2)
            if drop > 0 { tv.insertText("", replacementRange: NSRange(location: lr.location, length: drop)) }
            return true
        }
    }
}

/// Turns Markdown into what you see: sizes, weights, colours. Only attributes change, never the characters.
@MainActor enum MarkdownStyler {
    static let baseSize: CGFloat = 15
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
    private static let calloutRX = rx(#"^\s*>[ \t]?(\[![A-Za-z]+\][+-]?)"#)
    static let checkRX = rx(#"^(\s*)([-*+])[ \t](\[[ xX]\])[ \t]"#)
    static let bulletRX = rx(#"^(\s*)([-*+])[ \t]"#)
    static let numberRX = rx(#"^(\s*)(\d+[.)])[ \t]"#)
    private static let codeRX = rx(#"`([^`\n]+)`"#)
    private static let boldRX = rx(#"\*\*([^*\n]+)\*\*"#)
    private static let italicRX = rx(#"(?<![*\w])\*([^*\n]+)\*(?![*\w])"#)
    private static let strikeRX = rx(#"~~([^~\n]+)~~"#)
    private static let markRX = rx(#"==([^=\n]+)=="#)
    private static let wikiRX = rx(#"\[\[([^\]\n]+)\]\]"#)
    private static let linkRX = rx(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
        mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }
    private static func paragraph(first: CGFloat = 0, head: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4; p.paragraphSpacing = 2
        p.firstLineHeadIndent = first; p.headIndent = head
        return p
    }

    static func apply(to s: NSTextStorage) {
        let ns = s.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        s.beginEditing()
        s.setAttributes([.font: font(baseSize), .foregroundColor: ink, .paragraphStyle: paragraph()], range: full)
        var fenced = false
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            style(lineRange, ns.substring(with: lineRange), &fenced, s)
        }
        s.endEditing()
    }

    private static func style(_ r: NSRange, _ t: String, _ fenced: inout Bool, _ s: NSTextStorage) {
        let ns = t as NSString
        let all = NSRange(location: 0, length: ns.length)
        func at(_ x: NSRange) -> NSRange { NSRange(location: r.location + x.location, length: x.length) }
        let trimmed = t.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("```") { fenced.toggle(); s.addAttributes([.font: font(13, mono: true), .foregroundColor: faint], range: r); return }
        if fenced { s.addAttributes([.font: font(13, mono: true), .foregroundColor: ink2], range: r); return }
        if let h = headingRX.firstMatch(in: t, range: all) {
            let sizes: [CGFloat] = [30, 24, 20, 17, 16, 15]
            s.addAttribute(.font, value: font(sizes[h.range(at: 1).length - 1], .bold), range: r)
            s.addAttributes([.foregroundColor: faint, .font: font(12)], range: at(h.range))
            return
        }
        if ruleRX.firstMatch(in: t, range: all) != nil { s.addAttribute(.foregroundColor, value: faint, range: r); return }
        if trimmed.hasPrefix("|") { s.addAttribute(.font, value: font(13, mono: true), range: r); return }

        if let q = quoteRX.firstMatch(in: t, range: all) {
            s.addAttribute(.paragraphStyle, value: paragraph(first: 12, head: 12), range: r)
            s.addAttribute(.foregroundColor, value: faint, range: at(q.range))
            if let c = calloutRX.firstMatch(in: t, range: all) {      // > [!info] Title
                let tag = c.range(at: 1)
                s.addAttribute(.foregroundColor, value: accent, range: at(tag))
                trait(.boldFontMask, at(NSRange(location: NSMaxRange(tag), length: all.length - NSMaxRange(tag))), s)
            }
        } else if let c = checkRX.firstMatch(in: t, range: all) {
            let indent = CGFloat(c.range(at: 1).length) * 7
            s.addAttribute(.paragraphStyle, value: paragraph(first: indent, head: indent + 24), range: r)
            s.addAttribute(.foregroundColor, value: faint, range: at(c.range(at: 2)))
            let box = at(c.range(at: 3))
            s.addAttributes([.foregroundColor: accent, .font: font(15, .semibold, mono: true)], range: box)
            if ns.substring(with: c.range(at: 3)).lowercased() == "[x]" {
                let rest = NSRange(location: NSMaxRange(c.range), length: all.length - NSMaxRange(c.range))
                s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: ink2], range: at(rest))
            }
        } else if let b = bulletRX.firstMatch(in: t, range: all) {
            let indent = CGFloat(b.range(at: 1).length) * 7
            s.addAttribute(.paragraphStyle, value: paragraph(first: indent, head: indent + 16), range: r)
            s.addAttributes([.foregroundColor: accent, .font: font(15, .bold)], range: at(b.range(at: 2)))
        } else if let n = numberRX.firstMatch(in: t, range: all) {
            let indent = CGFloat(n.range(at: 1).length) * 7
            s.addAttribute(.paragraphStyle, value: paragraph(first: indent, head: indent + 22), range: r)
            s.addAttributes([.foregroundColor: accent, .font: font(15, .semibold)], range: at(n.range(at: 2)))
        }
        inline(r, t, s)
    }

    private static func trait(_ mask: NSFontTraitMask, _ range: NSRange, _ s: NSTextStorage) {
        var runs: [(NSFont, NSRange)] = []
        s.enumerateAttribute(.font, in: range) { v, rr, _ in if let f = v as? NSFont { runs.append((f, rr)) } }
        for (f, rr) in runs { s.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: mask), range: rr) }
    }

    /// Bold, italic, code, highlight, links inside a line. The marks around them are dimmed.
    private static func inline(_ r: NSRange, _ t: String, _ s: NSTextStorage) {
        let all = NSRange(location: 0, length: (t as NSString).length)
        func at(_ x: NSRange) -> NSRange { NSRange(location: r.location + x.location, length: x.length) }
        func dim(_ loc: Int, _ len: Int) { s.addAttribute(.foregroundColor, value: faint, range: NSRange(location: r.location + loc, length: len)) }
        func each(_ re: NSRegularExpression, _ f: (NSTextCheckingResult) -> Void) { for m in re.matches(in: t, range: all) { f(m) } }

        each(codeRX) { m in
            s.addAttributes([.font: font(13, mono: true), .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07)], range: at(m.range))
            dim(m.range.location, 1); dim(NSMaxRange(m.range) - 1, 1)
        }
        each(boldRX) { m in trait(.boldFontMask, at(m.range(at: 1)), s); dim(m.range.location, 2); dim(NSMaxRange(m.range) - 2, 2) }
        each(italicRX) { m in trait(.italicFontMask, at(m.range(at: 1)), s); dim(m.range.location, 1); dim(NSMaxRange(m.range) - 1, 1) }
        each(strikeRX) { m in
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: at(m.range(at: 1)))
            dim(m.range.location, 2); dim(NSMaxRange(m.range) - 2, 2)
        }
        each(markRX) { m in
            s.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), range: at(m.range(at: 1)))
            dim(m.range.location, 2); dim(NSMaxRange(m.range) - 2, 2)
        }
        each(wikiRX) { m in
            s.addAttribute(.foregroundColor, value: accent, range: at(m.range))
            dim(m.range.location, 2); dim(NSMaxRange(m.range) - 2, 2)
        }
        each(linkRX) { m in
            s.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: at(m.range(at: 1)))
            dim(m.range(at: 1).location - 1, 1)
            dim(NSMaxRange(m.range(at: 1)), m.range(at: 2).length + 3)
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
