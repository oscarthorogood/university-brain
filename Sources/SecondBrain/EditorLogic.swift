import Foundation

/// The rules behind the formatting toolbar and the keyboard shortcuts, written as plain functions of the text and the selection so `--check` can
/// try them without a window. The editor applies the edits they return and moves the selection as they say.
enum EditorLogic {
    struct Edit: Equatable {
        let range: NSRange
        let text: String
    }

    // MARK: Lines
    /// The lines (with their line breaks) a selection touches. A selection that ends at the very start of a line leaves that line out.
    static func lines(in ns: NSString, touching sel: NSRange) -> [NSRange] {
        let last = sel.length > 0 ? NSMaxRange(sel) - 1 : sel.location
        var out: [NSRange] = []
        var at = min(sel.location, ns.length)
        while true {
            let r = ns.lineRange(for: NSRange(location: at, length: 0))
            out.append(r)
            if NSMaxRange(r) > last || NSMaxRange(r) >= ns.length { break }
            at = NSMaxRange(r)
        }
        return out
    }

    /// A line's text without its line break, and the line break.
    private static func parts(_ ns: NSString, _ line: NSRange) -> (body: String, ending: String) {
        let text = ns.substring(with: line)
        let body = text.trimmingCharacters(in: .newlines)
        return (body, (text as NSString).substring(from: (body as NSString).length))
    }

    /// The smallest edit that turns the text in `range` into `new`: what the two share at the start and at the end is left out.
    static func edit(replacing range: NSRange, of ns: NSString, with new: String) -> Edit {
        let was = ns.substring(with: range) as NSString, now = new as NSString
        var head = 0
        while head < was.length, head < now.length, was.character(at: head) == now.character(at: head) { head += 1 }
        var tail = 0
        while tail < was.length - head, tail < now.length - head, was.character(at: was.length - 1 - tail) == now.character(at: now.length - 1 - tail) { tail += 1 }
        return Edit(range: NSRange(location: range.location + head, length: was.length - head - tail),
                    text: now.substring(with: NSRange(location: head, length: now.length - head - tail)))
    }

    /// Several separate edits (in order, none overlapping) as one, so they are one step to undo and one restyle.
    private static func combine(_ edits: [Edit], in ns: NSString) -> Edit? {
        guard let first = edits.first, let last = edits.last else { return nil }
        let span = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        var out = "", at = span.location
        for e in edits {
            out += ns.substring(with: NSRange(location: at, length: e.range.location - at)) + e.text
            at = NSMaxRange(e.range)
        }
        out += ns.substring(with: NSRange(location: at, length: NSMaxRange(span) - at))
        return edit(replacing: span, of: ns, with: out)
    }

    // MARK: A line's marks
    /// How many characters the mark at `i` takes (a heading's `## `, a bullet, a checkbox, a number, a quote's `> `); 0 when there is none.
    private static func markLength(_ u: [UInt16], from i: Int) -> Int {
        func at(_ k: Int) -> UInt16 { k < u.count ? u[k] : 0 }
        var k = i
        while at(k) == 35 { k += 1 }
        if k > i, k - i <= 6, at(k) == 32 { return k + 1 - i }
        if at(i) == 62, at(i + 1) == 32 { return 2 }
        if at(i) == 45 || at(i) == 42 || at(i) == 43, at(i + 1) == 32 {
            if at(i + 2) == 91, at(i + 3) == 32 || at(i + 3) == 120 || at(i + 3) == 88, at(i + 4) == 93, at(i + 5) == 32 { return 6 }
            return 2
        }
        k = i
        while at(k) >= 48, at(k) <= 57 { k += 1 }
        if k > i, at(k) == 46 || at(k) == 41, at(k + 1) == 32 { return k + 2 - i }
        return 0
    }

    /// A line split into its indent, its mark and the rest.
    static func split(_ body: String) -> (indent: String, mark: String, rest: String) {
        let u = Array(body.utf16)
        var i = 0
        while i < u.count, u[i] == 32 || u[i] == 9 { i += 1 }
        var n = markLength(u, from: i)
        if n > 0, u[i] == 35, i > 0 { n = 0 }       // an indented # is just text
        func text(_ r: Range<Int>) -> String { String(decoding: u[r], as: UTF16.self) }
        return (text(0..<i), text(i..<(i + n)), text((i + n)..<u.count))
    }

    /// A bullet, checkbox or number, as opposed to a heading or a quote.
    private static func isList(_ mark: String) -> Bool {
        guard let c = mark.unicodeScalars.first else { return false }
        return c != "#" && c != ">"
    }

    /// Rewrites every line the selection touches with `change` (given the line's number and its text) and gives back one edit for the lot, with the
    /// selection moved to match. Nil when nothing changes.
    private static func rewrite(_ ns: NSString, _ sel: NSRange, _ change: (Int, String) -> String) -> (edit: Edit, selection: NSRange)? {
        let ranges = lines(in: ns, touching: sel)
        guard let first = ranges.first, let last = ranges.last else { return nil }
        var out = "", changed = false, firstDelta = 0, lastEnding = 0
        for (i, r) in ranges.enumerated() {
            let (body, ending) = parts(ns, r)
            let new = change(i, body)
            if new != body { changed = true }
            if i == 0 { firstDelta = (new as NSString).length - (body as NSString).length }
            lastEnding = (ending as NSString).length
            out += new + ending
        }
        guard changed else { return nil }
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let selection = ranges.count == 1
            ? NSRange(location: max(first.location, sel.location + firstDelta), length: sel.length)
            : NSRange(location: first.location, length: (out as NSString).length - lastEnding)
        return (edit(replacing: block, of: ns, with: out), selection)
    }

    // MARK: Headings, lists and quotes
    /// Sets the mark in front of every selected line (a heading, bullet, checkbox, number or quote). When all of them already have it, it comes off.
    static func linePrefix(_ s: String, selection sel: NSRange, prefix: String) -> (edit: Edit, selection: NSRange)? {
        let ns = s as NSString
        let rows = lines(in: ns, touching: sel).map { split(parts(ns, $0).body) }
        let isNumbered = prefix.first?.isNumber == true
        func blank(_ i: Int) -> Bool { rows.count > 1 && rows[i].mark.isEmpty && rows[i].rest.trimmingCharacters(in: .whitespaces).isEmpty }
        func same(_ mark: String) -> Bool {         // a ticked box is still a checklist, `*` and `+` are still bullets
            if isNumbered { return mark.first?.isNumber == true }
            if prefix.contains("[") { return mark.contains("[") }
            if prefix == "- " { return ["- ", "* ", "+ "].contains(mark) }
            return mark == prefix
        }
        let active = rows.indices.filter { !blank($0) }
        let remove = !active.isEmpty && active.allSatisfy { same(rows[$0].mark) }
        var count = 0
        return rewrite(ns, sel) { i, body in
            guard !blank(i) else { return body }
            count += 1
            let mark = remove ? "" : isNumbered ? "\(count). " : prefix
            return (mark.hasPrefix("#") ? "" : rows[i].indent) + mark + rows[i].rest
        }
    }

    /// Tab and Shift-Tab: moves every selected list item one level in or out. Nil when none of the lines is a list item.
    static func indent(_ s: String, selection sel: NSRange, by dir: Int) -> (edit: Edit, selection: NSRange)? {
        rewrite(s as NSString, sel) { _, body in
            guard isList(split(body).mark) else { return body }
            if dir > 0 { return "  " + body }
            if body.hasPrefix("\t") { return String(body.dropFirst()) }
            return String(body.dropFirst(min(body.prefix { $0 == " " }.count, 2)))
        }
    }

    /// A numbered item (its indent, its number, and where the digits are); nil for any other line.
    private static func numbered(_ l: NSString) -> (indent: Int, number: Int, digits: NSRange)? {
        var i = 0
        while i < l.length, l.character(at: i) == 32 || l.character(at: i) == 9 { i += 1 }
        let start = i
        while i < l.length, l.character(at: i) >= 48, l.character(at: i) <= 57 { i += 1 }
        guard i > start, i - start <= 9, i + 1 < l.length, l.character(at: i) == 46 || l.character(at: i) == 41, l.character(at: i + 1) == 32,
              let n = Int(l.substring(with: NSRange(location: start, length: i - start))) else { return nil }
        return (start, n, NSRange(location: start, length: i - start))
    }

    /// After a numbered item is added, the items under it count on from it: 1, 2, 2, 3 becomes 1, 2, 3, 4. Items nested deeper are passed over, and the
    /// list ends at the first line that is not part of it.
    static func renumber(_ s: String, fromLine line: NSRange) -> Edit? {
        let ns = s as NSString
        guard NSMaxRange(line) <= ns.length, let head = numbered(parts(ns, line).body as NSString) else { return nil }
        var number = head.number, at = NSMaxRange(line)
        let start = at
        var out = "", end = at, changed = false
        while at < ns.length {
            let r = ns.lineRange(for: NSRange(location: at, length: 0))
            let (body, ending) = parts(ns, r)
            let b = body as NSString
            if let item = numbered(b), item.indent == head.indent {
                number += 1
                if item.number != number { changed = true }
                out += b.replacingCharacters(in: item.digits, with: "\(number)") + ending
            } else if !body.trimmingCharacters(in: .whitespaces).isEmpty, split(body).indent.count > head.indent {
                out += body + ending                // a nested item, or a line carried on under the item
            } else { break }
            at = NSMaxRange(r); end = at
        }
        guard changed else { return nil }
        return edit(replacing: NSRange(location: start, length: end - start), of: ns, with: out)
    }

    // MARK: Bold, italic, highlight, code, links
    /// Puts marks round the selection, takes them off if they are already there (round it, or in it when the selection reaches over them), or drops a
    /// pair at the cursor to type into. Over several lines each line is marked on its own, after its bullet or heading.
    static func wrap(_ s: String, selection sel: NSRange, open: String, close: String) -> (edit: Edit, selection: NSRange)? {
        let ns = s as NSString
        let o = (open as NSString).length, c = (close as NSString).length
        let star = open == close && open.allSatisfy { $0 == "*" }
        /// How many `*` in a row from `i` in direction `step`, staying inside `lo..<hi`. Italic is one, bold two and both three, so `**word**`
        /// is bold and not italic: a single `*` belongs to italic only when the number round the word is odd.
        func starRun(from i: Int, step: Int, _ lo: Int, _ hi: Int) -> Int {
            var n = 0, k = i
            while k >= lo, k < hi, ns.character(at: k) == 42 { n += 1; k += step }
            return n
        }
        func hasStars(_ n: Int) -> Bool { o == 1 ? n % 2 == 1 : n >= 2 }
        func text(_ at: Int, _ n: Int) -> String { at >= 0 && at + n <= ns.length ? ns.substring(with: NSRange(location: at, length: n)) : "" }

        if sel.length == 0 {
            let lr = ns.lineRange(for: sel)
            let on = star
                ? hasStars(min(starRun(from: sel.location - 1, step: -1, lr.location, NSMaxRange(lr)), starRun(from: sel.location, step: 1, lr.location, NSMaxRange(lr)), 3))
                : text(sel.location - o, o) == open && text(sel.location, c) == close
            if on { return (Edit(range: NSRange(location: sel.location - o, length: o + c), text: ""), NSRange(location: sel.location - o, length: 0)) }
            return (Edit(range: sel, text: open + close), NSRange(location: sel.location + o, length: 0))
        }

        struct Part { let a: Int, b: Int, on: Bool }
        var spans: [Part] = []
        for lr in lines(in: ns, touching: sel) {
            let body = Self.parts(ns, lr).body
            let end = lr.location + (body as NSString).length
            let row = split(body)
            var a = max(sel.location, lr.location + (row.indent as NSString).length + (row.mark as NSString).length), b = min(NSMaxRange(sel), end)
            while a < b, [32, 9].contains(ns.character(at: a)) { a += 1 }
            while b > a, [32, 9].contains(ns.character(at: b - 1)) { b -= 1 }
            // marks the selection itself reaches over (a triple-click takes the whole line, a drag over several lines takes every line to its end) are
            // the word's own, so each end is brought in to the word itself
            if star {
                while a < b, ns.character(at: a) == 42 { a += 1 }
                while b > a, ns.character(at: b - 1) == 42 { b -= 1 }
            } else {
                if b - a > o, text(a, o) == open { a += o }
                if b - a > c, text(b - c, c) == close { b -= c }
            }
            guard b > a else { continue }
            let on = star
                ? hasStars(min(starRun(from: a - 1, step: -1, lr.location, end), starRun(from: b, step: 1, lr.location, end), 3))
                : a - o >= lr.location && b + c <= end && text(a - o, o) == open && text(b, c) == close
            spans.append(Part(a: a, b: b, on: on))
        }
        guard !spans.isEmpty else { return nil }

        let removing = spans.allSatisfy { $0.on }
        var edits: [Edit] = [], shift = 0, from = 0, to = 0
        for (k, p) in spans.enumerated() {
            let (before, after) = removing ? (-o, -c) : p.on ? (0, 0) : (o, c)
            if removing {
                edits.append(Edit(range: NSRange(location: p.a - o, length: o), text: ""))
                edits.append(Edit(range: NSRange(location: p.b, length: c), text: ""))
            } else if !p.on {
                edits.append(Edit(range: NSRange(location: p.a, length: 0), text: open))
                edits.append(Edit(range: NSRange(location: p.b, length: 0), text: close))
            }
            if k == 0 { from = p.a + shift + before }
            to = p.b + shift + before
            shift += before + after
        }
        guard let edit = combine(edits, in: ns) else { return nil }
        return (edit, NSRange(location: from, length: to - from))
    }

    /// When the last letter has been taken out of a bold, italic, highlighted or code span, its marks round the cursor go too, so no bare `****` is left.
    static func emptyMarks(in s: String, at caret: Int) -> Edit? {
        let ns = s as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        func run(_ from: Int, _ step: Int) -> Int {
            var n = 0, i = from
            while i >= 0, i < ns.length, ns.character(at: i) == 42 { n += 1; i += step }
            return n
        }
        let n = min(run(caret - 1, -1), run(caret, 1))
        if n > 0 { return Edit(range: NSRange(location: caret - n, length: 2 * n), text: "") }
        for mark in ["~~", "==", "`"] {
            let k = (mark as NSString).length
            if caret >= k, caret + k <= ns.length, ns.substring(with: NSRange(location: caret - k, length: k)) == mark, ns.substring(with: NSRange(location: caret, length: k)) == mark {
                return Edit(range: NSRange(location: caret - k, length: 2 * k), text: "")
            }
        }
        return nil
    }

    // MARK: Check
    static func check() {
        func run(_ s: String, _ r: (edit: Edit, selection: NSRange)?) -> (text: String, selection: NSRange) {
            guard let r else { return (s, NSRange(location: NSNotFound, length: 0)) }
            return ((s as NSString).replacingCharacters(in: r.edit.range, with: r.edit.text), r.selection)
        }
        // bold goes on, and comes off again
        var r = run("one two three", wrap("one two three", selection: NSRange(location: 4, length: 3), open: "**", close: "**"))
        precondition(r.text == "one **two** three" && r.selection == NSRange(location: 6, length: 3), "bold on: \(r)")
        r = run(r.text, wrap(r.text, selection: r.selection, open: "**", close: "**"))
        precondition(r.text == "one two three" && r.selection == NSRange(location: 4, length: 3), "bold off: \(r)")
        // italic on bold makes it both, and a second italic takes only the italic off (it used to turn bold into italic)
        r = run("a **b** c", wrap("a **b** c", selection: NSRange(location: 4, length: 1), open: "*", close: "*"))
        precondition(r.text == "a ***b*** c", "italic on bold: \(r)")
        r = run(r.text, wrap(r.text, selection: r.selection, open: "*", close: "*"))
        precondition(r.text == "a **b** c", "italic off again: \(r)")
        r = run("a **b** c", wrap("a **b** c", selection: NSRange(location: 2, length: 5), open: "**", close: "**"))   // the marks themselves selected
        precondition(r.text == "a b c", "a selection that reaches over the marks: \(r)")
        // a pair at the cursor, and taking it away again
        r = run("ab", wrap("ab", selection: NSRange(location: 1, length: 0), open: "==", close: "=="))
        precondition(r.text == "a====b" && r.selection == NSRange(location: 3, length: 0), "pair at the cursor: \(r)")
        r = run(r.text, wrap(r.text, selection: r.selection, open: "==", close: "=="))
        precondition(r.text == "ab", "pair taken away: \(r)")
        // over lines: marks go after the bullet, blank lines are skipped, and all-marked lines are unmarked
        let list = "- one\n\n## two"
        r = run(list, wrap(list, selection: NSRange(location: 0, length: 13), open: "**", close: "**"))
        precondition(r.text == "- **one**\n\n## **two**", "bold over lines: \(r)")
        r = run(r.text, wrap(r.text, selection: r.selection, open: "**", close: "**"))
        precondition(r.text == list, "bold off over lines: \(r)")
        // headings, bullets, checklists, numbers
        r = run("one\ntwo", linePrefix("one\ntwo", selection: NSRange(location: 1, length: 0), prefix: "- "))
        precondition(r.text == "- one\ntwo" && r.selection == NSRange(location: 3, length: 0), "bullet: \(r)")
        r = run(r.text, linePrefix(r.text, selection: r.selection, prefix: "- "))
        precondition(r.text == "one\ntwo" && r.selection == NSRange(location: 1, length: 0), "bullet off: \(r)")
        r = run("a\nb\n\nc", linePrefix("a\nb\n\nc", selection: NSRange(location: 0, length: 4), prefix: "1. "))
        precondition(r.text == "1. a\n2. b\n\nc", "numbered over two lines: \(r)")
        r = run("- [x] done", linePrefix("- [x] done", selection: NSRange(location: 3, length: 0), prefix: "- [ ] "))
        precondition(r.text == "done", "a ticked box is still a checklist: \(r)")
        r = run("## Title", linePrefix("## Title", selection: NSRange(location: 4, length: 0), prefix: ""))
        precondition(r.text == "Title", "body takes a heading off: \(r)")
        // Tab and Shift-Tab over list items; plain text is left alone
        r = run("- a\n- b", indent("- a\n- b", selection: NSRange(location: 0, length: 7), by: 1))
        precondition(r.text == "  - a\n  - b", "indent: \(r)")
        r = run(r.text, indent(r.text, selection: r.selection, by: -1))
        precondition(r.text == "- a\n- b", "outdent: \(r)")
        precondition(indent("plain", selection: NSRange(location: 0, length: 0), by: 1) == nil, "plain text is not indented")
        // a numbered item added in the middle renumbers the ones under it
        let added = "1. a\n2. \n2. b\n3. c\nafter"
        let fix = renumber(added, fromLine: NSRange(location: 5, length: 4))
        precondition(fix.map { (added as NSString).replacingCharacters(in: $0.range, with: $0.text) } == "1. a\n2. \n3. b\n4. c\nafter", "renumbered")
        precondition(renumber("1. a\n2. b", fromLine: NSRange(location: 0, length: 5)) == nil, "nothing to renumber")
        // the last letter taken out of a bold word takes its marks too
        let gone = emptyMarks(in: "a **** b", at: 4)
        precondition(gone.map { ("a **** b" as NSString).replacingCharacters(in: $0.range, with: $0.text) } == "a  b", "empty marks go")
        precondition(emptyMarks(in: "a **b** c", at: 5) == nil, "marks round a word stay")
        print("editor ok: bold and italic toggle without turning into each other, formatting works over several lines, lists indent and renumber")
    }
}
