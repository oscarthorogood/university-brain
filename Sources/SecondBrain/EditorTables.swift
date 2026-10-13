import AppKit

// Tables in the editor work like Apple Notes' tables: a real grid, cells that wrap, Tab to the next cell, a "+" on the edges to add a row or column.
// The note stays plain Markdown. The table's lines are hidden in the text (they only keep a gap the height of the grid) and a `TableGridView` sits over
// the gap. Every edit in a cell is written back into the Markdown, and a change made to the Markdown some other way (undo, a restored version) is
// read back into the grid.

/// A Markdown table as rows of cells: the header row first, then the body rows. `sep` holds the alignment line's cells (`---`, `:--`…).
@MainActor struct TableModel {
    var prefix = ""             // the quote marks in front of every line when the table is inside a quote or callout
    var cells: [[String]] = []
    var sep: [String] = []
    var columns: Int { sep.count }

    /// The cells of one line, trimmed and still escaped. A `\|` is part of a cell, not a divider.
    static func split(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return [] }
        t.removeFirst()
        var out: [String] = [], cur = ""
        var prev: Character = " "
        for ch in t {
            if ch == "|", prev != "\\" { out.append(cur); cur = "" } else { cur.append(ch) }
            prev = ch
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }      // a last cell with no closing `|`
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }
    /// A cell as you type it: `\|` is a bar and `<br>` a line break.
    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "\\|", with: "|").replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(of: "<br />", with: "\n")
    }
    static func encode(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\r\n", with: "<br>").replacingOccurrences(of: "\n", with: "<br>")
    }

    /// The lines of a table (the header, the `| --- |` line, the rows) as the model; nil when they are not a table.
    static func parse(_ source: String) -> TableModel? {
        let lines = source.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        func cut(_ l: String) -> Int { MarkdownStyler.quoteRX.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length))?.range.length ?? 0 }
        var m = TableModel()
        m.prefix = (lines[0] as NSString).substring(to: cut(lines[0]))
        var rows: [[String]] = []
        for (i, l) in lines.enumerated() {
            let row = (l as NSString).substring(from: cut(l))
            guard row.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return nil }
            if i == 1 {
                guard MarkdownStyler.isTableSeparator(row) else { return nil }
                m.sep = split(row)
            } else { rows.append(split(row).map(decode)) }
        }
        let n = max(m.sep.count, rows.map(\.count).max() ?? 1, 1)
        m.sep += Array(repeating: "---", count: n - m.sep.count)
        m.cells = rows.map { $0 + Array(repeating: "", count: n - $0.count) }
        return m
    }

    func serialize() -> String {
        func line(_ cs: [String]) -> String { prefix + "| " + cs.joined(separator: " | ") + " |" }
        let body = cells.map { line($0.map(Self.encode)) }
        return ([body[0], line(sep)] + body.dropFirst()).joined(separator: "\n")
    }

    /// Part of `--check`.
    static func check() {
        let src = "> | Term | Definition (my words) |\n> | --- | :-: |\n> | Ethics | Right \\| wrong<br>second line |\n> | Maxim |"
        guard let m = parse(src) else { preconditionFailure("a quoted table parses") }
        precondition(m.prefix == "> " && m.columns == 2 && m.cells.count == 3 && m.cells[0] == ["Term", "Definition (my words)"], "header and quote marks: \(m.cells)")
        precondition(m.cells[1] == ["Ethics", "Right | wrong\nsecond line"] && m.cells[2] == ["Maxim", ""], "escapes, line breaks and a short row: \(m.cells)")
        precondition(m.sep == ["---", ":-:"], "alignment kept")
        let out = m.serialize()
        precondition(out == "> | Term | Definition (my words) |\n> | --- | :-: |\n> | Ethics | Right \\| wrong<br>second line |\n> | Maxim |  |", "written back: \(out)")
        precondition(parse(out)?.serialize() == out, "reading what was written changes nothing")
        precondition(parse("| a | b |\nnot a table") == nil && parse("| a |") == nil, "not a table")
        let doc = "intro\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n```\n| x | y |\n| --- | --- |\n```\n> | C |\n> | --- |\n> | 3 |\n| lone |\n"
        let blocks = MarkdownStyler.tableBlocks(in: doc as NSString)
        precondition(blocks.count == 2 && blocks[0].prefix == "" && blocks[1].prefix == "> " && blocks[0].lines.count == 3, "tables found outside code, quoted ones too: \(blocks.count)")
        precondition((doc as NSString).substring(with: blocks[0].content) == "| A | B |\n| --- | --- |\n| 1 | 2 |", "a table's text")
        print("tables ok: parsed and written back unchanged, escapes and quotes kept, code fences left alone")
    }
}

extension MarkdownStyler {
    /// A table the editor draws as a grid: its lines (without their line breaks) and the quote marks in front of them.
    struct TableBlock {
        let content: NSRange        // from the start of the first line to the end of the last line's text
        let lines: [NSRange]
        let prefix: String
    }
    /// The height of each table's gap in the text, in the order the tables come; set by the editor from what the grids need.
    static var tableHeights: [Int: CGFloat] = [:]

    static func gridParagraph(height: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 0; p.paragraphSpacingBefore = 0; p.paragraphSpacing = 8
        p.minimumLineHeight = height; p.maximumLineHeight = height
        return p
    }
    static let collapsedLine: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 0; p.paragraphSpacing = 0; p.paragraphSpacingBefore = 0; p.minimumLineHeight = 1; p.maximumLineHeight = 1
        return p
    }()

    /// Every table of the text that has a header, a `| --- |` line and rows, outside code fences. Anything else that starts with `|` stays plain text.
    static func tableBlocks(in ns: NSString) -> [TableBlock] {
        guard ns.length > 0, ns.range(of: "|").location != NSNotFound else { return [] }
        var out: [TableBlock] = []
        var cur: [NSRange] = [], cuts: [Int] = [], fenced = false
        func flush() {
            defer { cur = []; cuts = [] }
            guard cur.count >= 2 else { return }
            let second = ns.substring(with: cur[1]) as NSString
            guard isTableSeparator(second.substring(from: cuts[1])) else { return }
            let first = cur[0], last = cur[cur.count - 1]
            out.append(TableBlock(content: NSRange(location: first.location, length: NSMaxRange(last) - first.location), lines: cur,
                                  prefix: (ns.substring(with: first) as NSString).substring(to: cuts[0])))
        }
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            let t = ns.substring(with: r) as NSString
            if t.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); flush(); return }
            if fenced { flush(); return }
            let cut = quoteRX.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length))?.range.length ?? 0
            if t.substring(from: cut).trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                if let c = cuts.last, c != cut { flush() }
                cur.append(r); cuts.append(cut)
            } else { flush() }
        }
        flush()
        return out
    }
}

// MARK: One cell

/// A cell: an editable, wrapping text. While you are in it you see the Markdown you typed; when you leave, bold, italic, code, strikethrough and links show as styled text.
final class TableCellView: NSTextView {
    var row = 0, col = 0
    weak var grid: TableGridView?
    var raw = ""

    static func make(_ text: String, row: Int, col: Int, grid: TableGridView) -> TableCellView {
        let c = TableCellView(usingTextLayoutManager: false)
        c.row = row; c.col = col; c.grid = grid; c.raw = text
        c.drawsBackground = false
        c.isRichText = true
        c.importsGraphics = false
        c.allowsUndo = false
        c.isAutomaticQuoteSubstitutionEnabled = false
        c.isAutomaticDashSubstitutionEnabled = false
        c.isAutomaticTextReplacementEnabled = false
        c.isAutomaticSpellingCorrectionEnabled = false
        c.isAutomaticLinkDetectionEnabled = false
        c.textContainerInset = .zero
        c.textContainer?.lineFragmentPadding = 0
        c.textContainer?.widthTracksTextView = false
        c.isHorizontallyResizable = false
        c.isVerticallyResizable = false
        c.insertionPointColor = MarkdownStyler.accent
        c.setAccessibilityLabel("Row \(row + 1), column \(col + 1)")
        c.showDisplay()
        return c
    }

    private var header: Bool { row == 0 }
    private static func baseFont(_ header: Bool) -> NSFont { MarkdownStyler.font(14, header ? .semibold : .regular) }
    private var base: [NSAttributedString.Key: Any] { [.font: Self.baseFont(header), .foregroundColor: NSColor.labelColor] }

    func showEditing() {
        textStorage?.setAttributedString(NSAttributedString(string: raw, attributes: base))
        typingAttributes = base
    }
    func showDisplay() { textStorage?.setAttributedString(Self.display(raw, header: header)) }

    /// The cell's text as it reads when you are not editing it.
    static func display(_ raw: String, header: Bool) -> NSAttributedString {
        let font = baseFont(header)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        var text = raw.replacingOccurrences(of: #"\[\[([^\]|]+)\|([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        guard !text.isEmpty, let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: text, attributes: attrs)
        }
        let out = NSMutableAttributedString(string: String(parsed.characters), attributes: attrs)
        for run in parsed.runs {
            let r = NSRange(run.range, in: parsed)
            guard r.length > 0, NSMaxRange(r) <= out.length else { continue }
            if let intent = run.inlinePresentationIntent {
                var f = font
                if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
                if intent.contains(.code) {
                    out.addAttributes([.font: MarkdownStyler.font(13, mono: true), .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)], range: r)
                } else { out.addAttribute(.font, value: f, range: r) }
                if intent.contains(.strikethrough) { out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            }
            if run.link != nil { out.addAttributes([.foregroundColor: MarkdownStyler.accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: r) }
        }
        return out
    }

    /// How tall the text is at `width`, at least one line.
    func fittingHeight(width: CGFloat) -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 18 }
        tc.containerSize = NSSize(width: max(width, 20), height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        return ceil(max(lm.usedRect(for: tc).height, lm.defaultLineHeight(for: Self.baseFont(header))))
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { showEditing(); grid?.cellFocused(self) }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { raw = string; showDisplay(); grid?.cellBlurred(self) }
        return ok
    }
    override func didChangeText() {
        super.didChangeText()
        raw = string
        grid?.cellEdited(self)
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    /// Whether the caret is on the first and on the last line of the cell's text.
    private func edge() -> (first: Bool, last: Bool) {
        guard let lm = layoutManager, let tc = textContainer else { return (true, true) }
        lm.ensureLayout(for: tc)
        let glyphs = lm.numberOfGlyphs
        guard glyphs > 0 else { return (true, true) }
        let g = min(lm.glyphIndexForCharacter(at: min(selectedRange().location, max((string as NSString).length - 1, 0))), glyphs - 1)
        var r = NSRange()
        _ = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &r)
        return (r.location == 0, NSMaxRange(r) >= glyphs)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertTab(_:)): grid?.tab(self, forward: true)
        case #selector(NSResponder.insertBacktab(_:)): grid?.tab(self, forward: false)
        case #selector(NSResponder.insertNewline(_:)): grid?.step(self, 1, addingRow: true)
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), #selector(NSResponder.insertLineBreak(_:)):
            insertText("\n", replacementRange: selectedRange())      // Option-Return: a second line in the same cell
        case #selector(NSResponder.moveDown(_:)): if edge().last { grid?.step(self, 1, addingRow: false) } else { super.doCommand(by: selector) }
        case #selector(NSResponder.moveUp(_:)): if edge().first { grid?.step(self, -1, addingRow: false) } else { super.doCommand(by: selector) }
        case #selector(NSResponder.moveRight(_:)):
            if selectedRange().length == 0, selectedRange().location >= (string as NSString).length { grid?.tab(self, forward: true, selectAll: false) } else { super.doCommand(by: selector) }
        case #selector(NSResponder.moveLeft(_:)):
            if selectedRange().length == 0, selectedRange().location == 0 { grid?.tab(self, forward: false, selectAll: false) } else { super.doCommand(by: selector) }
        default: super.doCommand(by: selector)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = super.menu(for: event) ?? NSMenu()
        guard let grid else { return m }
        m.addItem(.separator())
        for (tag, title) in [(1, "Add Row Above"), (2, "Add Row Below"), (3, "Add Column Left"), (4, "Add Column Right"), (5, "Delete Row"), (6, "Delete Column"), (7, "Delete Table")] {
            if tag == 1 && row == 0 { continue }
            if tag == 5 && row == 0 { continue }
            if tag == 6 && grid.columnCount < 2 { continue }
            let item = NSMenuItem(title: title, action: #selector(TableGridView.menuAction(_:)), keyEquivalent: "")
            item.target = grid; item.tag = tag
            m.addItem(item)
        }
        grid.contextCell = self
        return m
    }
}

// MARK: The grid

final class TableGridView: NSView {
    private(set) var model = TableModel()
    /// The Markdown this grid last read or wrote; when the text differs from it, the text changed some other way and the grid reads it again.
    var lastSource = ""
    var onChange: ((TableGridView, String) -> Void)?
    var onExit: ((TableGridView, Int) -> Void)?       // -1: the caret leaves above the table, 1: below
    var onDelete: ((TableGridView) -> Void)?
    weak var contextCell: TableCellView?

    private var cellViews: [[TableCellView]] = []
    private var colWidths: [CGFloat] = [], rowHeights: [CGFloat] = []
    private var tableWidth: CGFloat = 0
    private var focused: (row: Int, col: Int)?
    private var hovering = false
    private let addRowButton = NSButton(), addColumnButton = NSButton()

    static let padX: CGFloat = 10, padY: CGFloat = 7, minRow: CGFloat = 34
    /// Room around the table for the "+" on its right and bottom edges.
    static let handle: CGFloat = 14
    var columnCount: Int { model.columns }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (b, symbol, label, action) in [(addRowButton, "plus.circle.fill", "Add row", #selector(addRowTapped)), (addColumnButton, "plus.circle.fill", "Add column", #selector(addColumnTapped))] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            b.isBordered = false; b.imagePosition = .imageOnly; b.contentTintColor = MarkdownStyler.accent
            b.target = self; b.action = action; b.toolTip = label; b.setAccessibilityLabel(label)
            b.isHidden = true
            addSubview(b)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityRole(.table)
        setAccessibilityLabel("Table")
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // MARK: Reading and writing

    /// Shows `m`, keeping the caret in the same cell if one of them has it.
    func load(_ m: TableModel, source: String) {
        let was = focused, selection = was.flatMap { f in cellViews.indices.contains(f.row) && cellViews[f.row].indices.contains(f.col) ? cellViews[f.row][f.col].selectedRange() : nil }
        model = m; lastSource = source
        rebuildCells()
        if let was { focusCell(row: min(was.row, model.cells.count - 1), col: min(was.col, model.columns - 1), selection: selection) }
    }

    private func rebuildCells() {
        for r in cellViews { for c in r { c.removeFromSuperview() } }
        cellViews = model.cells.enumerated().map { r, row in
            row.enumerated().map { c, text in
                let v = TableCellView.make(text, row: r, col: c, grid: self)
                addSubview(v, positioned: .below, relativeTo: addRowButton)
                return v
            }
        }
        focused = nil
        colWidths = []; rowHeights = []      // measured again before the next layout
        needsLayout = true; needsDisplay = true
    }

    private func commit() {
        let s = model.serialize()
        lastSource = s
        needsLayout = true; needsDisplay = true
        onChange?(self, s)
    }

    func cellEdited(_ c: TableCellView) {
        guard model.cells.indices.contains(c.row), model.cells[c.row].indices.contains(c.col) else { return }
        model.cells[c.row][c.col] = c.raw
        commit()
    }
    func cellFocused(_ c: TableCellView) { focused = (c.row, c.col); updateHandles(); needsDisplay = true; c.scrollToVisible(c.bounds.insetBy(dx: -4, dy: -8)) }
    func cellBlurred(_ c: TableCellView) {
        if let f = focused, f.row == c.row, f.col == c.col { focused = nil }
        updateHandles(); needsDisplay = true
    }

    // MARK: Layout

    /// The height the grid needs when it is `width` wide (the table and the room under it for the "+").
    func fittingHeight(width: CGFloat) -> CGFloat {
        measure(tableWidth: max(width - Self.handle, 120))
        needsLayout = true; needsDisplay = true
        return rowHeights.reduce(0, +) + Self.handle
    }

    private func measure(tableWidth w: CGFloat) {
        tableWidth = w
        let n = max(model.columns, 1)
        // Columns share the width in proportion to the longest text in them, so a narrow "Term" and a wide "Definition" both read well.
        let weights = (0..<n).map { c -> CGFloat in
            CGFloat(min(max(model.cells.map { $0.indices.contains(c) ? ($0[c] as NSString).length : 0 }.max() ?? 0, 6), 60))
        }
        let total = weights.reduce(0, +)
        colWidths = weights.map { max(w * $0 / total, 64) }
        let sum = colWidths.reduce(0, +)
        if sum > w { colWidths = colWidths.map { $0 * w / sum } }
        rowHeights = []
        for row in cellViews {
            var tallest: CGFloat = 0
            for (c, cell) in row.enumerated() { tallest = max(tallest, cell.fittingHeight(width: colWidths[min(c, colWidths.count - 1)] - 2 * Self.padX)) }
            rowHeights.append(max(tallest + 2 * Self.padY, Self.minRow))
        }
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - Self.handle - tableWidth) > 0.5 || rowHeights.count != cellViews.count || colWidths.isEmpty { measure(tableWidth: max(bounds.width - Self.handle, 120)) }
        var y: CGFloat = 0
        for (r, row) in cellViews.enumerated() {
            var x: CGFloat = 0
            for (c, cell) in row.enumerated() {
                let w = colWidths[min(c, colWidths.count - 1)]
                cell.frame = NSRect(x: x + Self.padX, y: y + Self.padY, width: w - 2 * Self.padX, height: rowHeights[r] - 2 * Self.padY)
                x += w
            }
            y += rowHeights[r]
        }
        addRowButton.frame = NSRect(x: tableWidth / 2 - 10, y: y - 2, width: 20, height: 20)
        addColumnButton.frame = NSRect(x: tableWidth - 2, y: y / 2 - 10, width: 20, height: 20)
    }

    override func draw(_ dirty: NSRect) {
        let height = rowHeights.reduce(0, +)
        guard height > 0 else { return }
        let table = NSRect(x: 0, y: 0, width: tableWidth, height: height)
        let outline = NSBezierPath(roundedRect: table.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        MarkdownStyler.accent.withAlphaComponent(0.12).setFill()
        NSRect(x: 0, y: 0, width: tableWidth, height: rowHeights[0]).fill()
        NSGraphicsContext.restoreGraphicsState()
        let lines = NSBezierPath()
        var y: CGFloat = 0
        for h in rowHeights.dropLast() { y += h; lines.move(to: NSPoint(x: 0, y: y)); lines.line(to: NSPoint(x: tableWidth, y: y)) }
        var x: CGFloat = 0
        for w in colWidths.dropLast() { x += w; lines.move(to: NSPoint(x: x, y: 0)); lines.line(to: NSPoint(x: x, y: height)) }
        NSColor.separatorColor.setStroke()
        lines.lineWidth = 1; lines.stroke()
        outline.lineWidth = 1; outline.stroke()
        if let f = focused, f.row < rowHeights.count, f.col < colWidths.count {
            let rect = NSRect(x: colWidths[..<f.col].reduce(0, +), y: rowHeights[..<f.row].reduce(0, +), width: colWidths[f.col], height: rowHeights[f.row]).insetBy(dx: 1, dy: 1)
            let ring = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            MarkdownStyler.accent.setStroke(); ring.lineWidth = 2; ring.stroke()
        }
    }

    // MARK: The mouse

    override func mouseEntered(with event: NSEvent) { hovering = true; updateHandles() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateHandles() }
    private func updateHandles() { addRowButton.isHidden = !(hovering || focused != nil); addColumnButton.isHidden = addRowButton.isHidden }

    /// A click in a cell's padding, or on a border, goes to the cell under it.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var y: CGFloat = 0
        for (r, h) in rowHeights.enumerated() {
            defer { y += h }
            guard p.y >= y, p.y < y + h else { continue }
            var x: CGFloat = 0
            for (c, w) in colWidths.enumerated() {
                defer { x += w }
                if p.x >= x, p.x < x + w { focusCell(row: r, col: c); return }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Moving around

    func focusCell(row: Int, col: Int, selectAll: Bool = false, selection: NSRange? = nil) {
        guard cellViews.indices.contains(row), cellViews[row].indices.contains(col) else { return }
        let c = cellViews[row][col]
        window?.makeFirstResponder(c)
        let len = (c.string as NSString).length
        if selectAll { c.setSelectedRange(NSRange(location: 0, length: len)) }
        else if let selection { c.setSelectedRange(NSRange(location: min(selection.location, len), length: 0)) }
        else { c.setSelectedRange(NSRange(location: len, length: 0)) }
    }

    /// Tab goes to the next cell (the last one adds a row), Shift-Tab to the one before.
    func tab(_ c: TableCellView, forward: Bool, selectAll: Bool = true) {
        let rows = model.cells.count, cols = model.columns
        if forward {
            if c.col + 1 < cols { focusCell(row: c.row, col: c.col + 1, selectAll: selectAll) }
            else if c.row + 1 < rows { focusCell(row: c.row + 1, col: 0, selectAll: selectAll) }
            else { insertRow(at: rows, focusCol: 0) }
        } else {
            if c.col > 0 { focusCell(row: c.row, col: c.col - 1, selectAll: selectAll) }
            else if c.row > 0 { focusCell(row: c.row - 1, col: cols - 1, selectAll: selectAll) }
        }
    }

    /// Return and the down arrow go to the cell below, the up arrow to the one above; past the first or last row the caret leaves the table.
    func step(_ c: TableCellView, _ delta: Int, addingRow: Bool) {
        let target = c.row + delta
        if target >= 0, target < model.cells.count { focusCell(row: target, col: c.col, selectAll: addingRow); return }
        if delta < 0 { onExit?(self, -1) }
        else if addingRow { insertRow(at: model.cells.count, focusCol: c.col) }
        else { onExit?(self, 1) }
    }

    // MARK: Changing the table

    func insertRow(at i: Int, focusCol: Int = 0) {
        let at = min(max(i, 1), model.cells.count)
        model.cells.insert(Array(repeating: "", count: model.columns), at: at)
        rebuildCells(); commit()
        focusCell(row: at, col: focusCol)
    }
    func insertColumn(at i: Int) {
        let at = min(max(i, 0), model.columns)
        for r in model.cells.indices { model.cells[r].insert("", at: at) }
        model.sep.insert("---", at: at)
        rebuildCells(); commit()
        focusCell(row: 0, col: at)
    }
    func deleteRow(_ r: Int) {
        guard r > 0, r < model.cells.count else { return }
        model.cells.remove(at: r)
        rebuildCells(); commit()
    }
    func deleteColumn(_ c: Int) {
        guard model.columns > 1, c < model.columns else { return }
        for r in model.cells.indices { model.cells[r].remove(at: c) }
        model.sep.remove(at: c)
        rebuildCells(); commit()
    }

    @objc private func addRowTapped() { insertRow(at: model.cells.count) }
    @objc private func addColumnTapped() { insertColumn(at: model.columns) }
    @objc func menuAction(_ sender: NSMenuItem) {
        guard let c = contextCell else { return }
        switch sender.tag {
        case 1: insertRow(at: c.row)
        case 2: insertRow(at: c.row + 1)
        case 3: insertColumn(at: c.col)
        case 4: insertColumn(at: c.col + 1)
        case 5: deleteRow(c.row)
        case 6: deleteColumn(c.col)
        case 7: onDelete?(self)
        default: break
        }
    }
}

// MARK: In the text view

extension MDTextView {
    /// Makes one grid for each table in the text, reads in the ones whose Markdown changed some other way, and sizes the gaps they sit over.
    func syncTables() {
        let ns = string as NSString
        tableBlocks = MarkdownStyler.tableBlocks(in: ns)
        while tableViews.count < tableBlocks.count {
            let g = TableGridView(frame: .zero)
            g.onChange = { [weak self] grid, text in self?.tableEdited(grid, text) }
            g.onExit = { [weak self] grid, dir in self?.tableExit(grid, dir) }
            g.onDelete = { [weak self] grid in self?.tableDelete(grid) }
            addSubview(g)
            tableViews.append(g)
        }
        while tableViews.count > tableBlocks.count { tableViews.removeLast().removeFromSuperview() }
        for (k, b) in tableBlocks.enumerated() {
            let source = ns.substring(with: b.content)
            if tableViews[k].lastSource != source, let m = TableModel.parse(source) { tableViews[k].load(m, source: source) }
        }
        updateTableHeights()
    }

    /// Each table's gap in the text gets the height its grid needs at the text's width.
    func updateTableHeights() {
        guard let tc = textContainer, let st = textStorage else { return }
        for k in MarkdownStyler.tableHeights.keys where k >= tableBlocks.count { MarkdownStyler.tableHeights[k] = nil }
        let ns = string as NSString
        st.beginEditing()
        for (k, b) in tableBlocks.enumerated() where k < tableViews.count {
            let inset: CGFloat = b.prefix.isEmpty ? 0 : 14
            let h = ceil(tableViews[k].fittingHeight(width: max(tc.size.width - inset * 2, 200)))
            if abs((MarkdownStyler.tableHeights[k] ?? 0) - h) > 0.5 {
                MarkdownStyler.tableHeights[k] = h
                st.addAttribute(.paragraphStyle, value: MarkdownStyler.gridParagraph(height: h), range: ns.lineRange(for: NSRange(location: b.content.location, length: 0)))
            }
        }
        st.endEditing()
        positionTables()
    }

    /// Puts each grid over its gap.
    func positionTables() {
        guard !tableViews.isEmpty, !positioningTables, let lm = layoutManager, let tc = textContainer else { return }
        let blocks = MarkdownStyler.tableBlocks(in: string as NSString)
        guard blocks.count == tableViews.count else { syncTables(); return }     // (which ends by positioning them)
        positioningTables = true
        defer { positioningTables = false }
        tableBlocks = blocks
        let o = textContainerOrigin
        for (k, b) in blocks.enumerated() {
            let g = lm.glyphIndexForCharacter(at: b.content.location)
            guard g < lm.numberOfGlyphs else { continue }
            let rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let inset: CGFloat = b.prefix.isEmpty ? 0 : 14
            let frame = NSRect(x: o.x + inset, y: o.y + rect.minY, width: max(tc.size.width - inset * 2, 200), height: MarkdownStyler.tableHeights[k] ?? rect.height)
            if tableViews[k].frame != frame { tableViews[k].frame = frame }
        }
    }

    /// A cell was edited: the table's Markdown in the note becomes what the grid says.
    func tableEdited(_ grid: TableGridView, _ text: String) {
        let blocks = MarkdownStyler.tableBlocks(in: string as NSString)
        guard let k = tableViews.firstIndex(where: { $0 === grid }), k < blocks.count else { return }
        let r = blocks[k].content
        if shouldChangeText(in: r, replacementString: text) { replaceCharacters(in: r, with: text); didChangeText() }
    }

    /// The caret leaves the table, above it or below it.
    func tableExit(_ grid: TableGridView, _ dir: Int) {
        let blocks = MarkdownStyler.tableBlocks(in: string as NSString)
        guard let k = tableViews.firstIndex(where: { $0 === grid }), k < blocks.count else { return }
        let b = blocks[k]
        func insertBreak(at i: Int) {
            let r = NSRange(location: i, length: 0)
            if shouldChangeText(in: r, replacementString: "\n") { replaceCharacters(in: r, with: "\n"); didChangeText() }
        }
        window?.makeFirstResponder(self)
        if dir < 0 {
            if b.content.location == 0 { insertBreak(at: 0) }       // a table at the very top gets a line above it to stand on
            setSelectedRange(NSRange(location: max(b.content.location - 1, 0), length: 0))
        } else {
            if NSMaxRange(b.content) >= (string as NSString).length { insertBreak(at: (string as NSString).length) }
            setSelectedRange(NSRange(location: min(NSMaxRange(b.content) + 1, (string as NSString).length), length: 0))
        }
    }

    /// Delete Table: its lines go.
    func tableDelete(_ grid: TableGridView) {
        let ns = string as NSString
        let blocks = MarkdownStyler.tableBlocks(in: ns)
        guard let k = tableViews.firstIndex(where: { $0 === grid }), k < blocks.count else { return }
        let b = blocks[k]
        let r = NSRange(location: b.content.location, length: min(NSMaxRange(b.content) + 1, ns.length) - b.content.location)
        window?.makeFirstResponder(self)
        if shouldChangeText(in: r, replacementString: "") { replaceCharacters(in: r, with: ""); didChangeText() }
        setSelectedRange(NSRange(location: min(r.location, (string as NSString).length), length: 0))
    }

    /// The caret goes into the table at `location` (a table just added).
    func focusTable(at location: Int) {
        guard let k = tableBlocks.firstIndex(where: { $0.content.location <= location && location <= NSMaxRange($0.content) }), k < tableViews.count else { return }
        tableViews[k].focusCell(row: 0, col: 0, selectAll: true)
    }
}
