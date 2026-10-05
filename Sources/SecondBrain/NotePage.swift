import SwiftUI
import AppKit

/// Renders Obsidian-flavoured Markdown the way Obsidian's reading view does: callout boxes, headings, lists, tasks, tables, code, links.
struct MarkdownView: View {
    @Environment(Store.self) private var store
    let text: String
    var body: some View {
        MarkdownBlocks(blocks: MD.parse(text.components(separatedBy: "\n")), anchors: true)
            .textSelection(.enabled)
            .tint(Color(light: 0x705DCF, dark: 0xA99BF0))
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "sbnote", let target = String(url.absoluteString.dropFirst(7)).removingPercentEncoding else { return .systemAction }
                open(target); return .handled
            })
    }
    func open(_ target: String) { store.openTarget(target) }
}

enum MD {
    indirect enum Block {
        case heading(Int, String), callout(String, String, String, [Block]), quote([Block])
        case bullet(String, Int), numbered(String, String, Int), task(String, Bool, Int)
        case table([[String]]), code(String), para(String), rule, image(String, CGFloat?)
    }

    static func inline(_ s: String) -> AttributedString {
        // [[target#heading|alias]] → a link the view handles; Obsidian shows the alias, else the target.
        let t = s.replacing(/!?\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]/) { m in
            let target = String(m.1)
            return "[\(m.2.map(String.init) ?? target)](sbnote:\(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))"
        }
        var a = (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
        // ==highlight== (Obsidian) → yellow marker behind the text.
        while let open = a.range(of: "=="), let close = a[open.upperBound...].range(of: "==") {
            a[open.upperBound..<close.lowerBound].backgroundColor = Color(light: 0xFFE066, dark: 0x8A7200).opacity(0.55)
            a.removeSubrange(close); a.removeSubrange(open)
        }
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(size: 13, design: .monospaced)
            a[run.range].backgroundColor = Color.ink.opacity(0.07)
        }
        return a
    }

    static func level(_ line: String) -> Int {
        let ws = line.prefix { $0 == " " || $0 == "\t" }
        return ws.filter { $0 == "\t" }.count + ws.filter { $0 == " " }.count / 2
    }

    static func parse(_ lines: [String]) -> [Block] {
        var out: [Block] = []; var i = 0
        while i < lines.count {
            let raw = lines[i]
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                var code: [String] = []; i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                out.append(.code(code.joined(separator: "\n"))); i += 1; continue
            }
            if raw.hasPrefix(">") {
                var group: [String] = []
                while i < lines.count, lines[i].hasPrefix(">") {
                    var l = String(lines[i].dropFirst()); if l.hasPrefix(" ") { l.removeFirst() }
                    group.append(l); i += 1
                }
                if let m = group[0].trimmingCharacters(in: .whitespaces).wholeMatch(of: /\[!(\w+)\]([+-]?)\s*(.*)/) {
                    let type = m.1.lowercased()
                    out.append(.callout(type, m.3.isEmpty ? type.capitalized : String(m.3), String(m.2), parse(Array(group.dropFirst()))))
                } else { out.append(.quote(parse(group))) }
                continue
            }
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") {
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    if r.wholeMatch(of: /[\s|:\-]+/) == nil {
                        rows.append(r.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                    }
                    i += 1
                }
                out.append(.table(rows)); continue
            }
            i += 1
            if t.isEmpty { continue }
            let lv = level(raw)
            if let m = t.wholeMatch(of: /(#{1,6})\s+(.*)/) { out.append(.heading(m.1.count, String(m.2))) }
            else if t == "---" || t == "***" { out.append(.rule) }
            else if let m = t.wholeMatch(of: /!\[\[([^\]|]+\.(?:png|jpe?g|gif|webp|heic|tiff?))(?:\|(\d+))?\]\]/.ignoresCase()) { out.append(.image(String(m.1), m.2.flatMap { Double($0) }.map { CGFloat($0) })) }
            else if let m = t.wholeMatch(of: /!\[[^\]]*\]\(([^)\s]+)\)/) { out.append(.image(String(m.1).removingPercentEncoding ?? String(m.1), nil)) }
            else if let m = t.wholeMatch(of: /[-*]\s\[([ xX])\]\s?(.*)/) { out.append(.task(String(m.2), m.1 != " ", lv)) }
            else if t == "-" || t == "*" { out.append(.bullet("", lv)) }
            else if let m = t.wholeMatch(of: /[-*+]\s+(.*)/) { out.append(.bullet(String(m.1), lv)) }
            else if let m = t.wholeMatch(of: /(\d+[.)])\s+(.*)/) { out.append(.numbered(String(m.1), String(m.2), lv)) }
            else { out.append(.para(t)) }
        }
        return out
    }

    /// Obsidian's default callout colours and icons.
    static func style(_ type: String) -> (Color, String) {
        switch type {
        case "abstract", "summary", "tldr": (Color(light: 0x00A8A6, dark: 0x53DFDD), "doc.text")
        case "tip", "hint", "important": (Color(light: 0x00A8A6, dark: 0x53DFDD), "flame")
        case "success", "check", "done": (Color(light: 0x08A045, dark: 0x44CF6E), "checkmark")
        case "question", "help", "faq": (Color(light: 0xD86A00, dark: 0xFA9A3B), "questionmark.circle")
        case "warning", "caution", "attention": (Color(light: 0xD86A00, dark: 0xFA9A3B), "exclamationmark.triangle")
        case "failure", "fail", "missing": (Color(light: 0xD7263D, dark: 0xFB464C), "xmark")
        case "danger", "error": (Color(light: 0xD7263D, dark: 0xFB464C), "bolt")
        case "bug": (Color(light: 0xD7263D, dark: 0xFB464C), "ant")
        case "example": (Color(light: 0x7852EE, dark: 0xA882FF), "list.bullet")
        case "quote", "cite": (Color(light: 0x8A8A8A, dark: 0x9E9E9E), "quote.opening")
        case "todo": (Color(light: 0x086DDD, dark: 0x027AFF), "checkmark.circle")
        default: (Color(light: 0x086DDD, dark: 0x027AFF), type == "note" ? "pencil" : "info.circle")   // note, info
        }
    }
}

struct MarkdownBlocks: View {
    let blocks: [MD.Block]
    var anchors = false   // top level only: each block can be scrolled to by id "h<index>" (the heading outline uses it)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                if anchors { MarkdownBlock(block: b).id("h\(i)") } else { MarkdownBlock(block: b) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownBlock: View {
    let block: MD.Block
    var body: some View {
        switch block {
        case .heading(let n, let s):
            Text(MD.inline(s)).font(.system(size: [26, 22, 18, 16, 15, 14][n - 1], weight: n == 1 ? .bold : .semibold)).padding(.top, n <= 2 ? 14 : 6)
        case .callout(let type, let title, let fold, let inner): Callout(type: type, title: title, fold: fold, inner: inner)
        case .quote(let inner):
            MarkdownBlocks(blocks: inner).padding(.leading, 14).foregroundStyle(Color.ink2)
                .overlay(alignment: .leading) { Rectangle().fill(Color(light: 0x705DCF, dark: 0xA99BF0)).frame(width: 2) }
        case .bullet(let s, let lv):
            HStack(alignment: .firstTextBaseline, spacing: 10) { Circle().fill(Color.ink2.opacity(0.7)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }; Text(MD.inline(s)).lineSpacing(4) }
                .font(.system(size: 14)).padding(.leading, CGFloat(lv) * 22 + 6)
        case .numbered(let n, let s, let lv):
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(n).foregroundStyle(Color.ink2).monospacedDigit(); Text(MD.inline(s)).lineSpacing(4) }
                .font(.system(size: 14)).padding(.leading, CGFloat(lv) * 22)
        case .task(let s, let done, let lv):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? Color(light: 0x705DCF, dark: 0xA99BF0) : Color.ink2)
                Text(MD.inline(s)).strikethrough(done).foregroundStyle(done ? Color.ink2 : Color.ink).lineSpacing(4)
            }.font(.system(size: 14)).padding(.leading, CGFloat(lv) * 22)
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MD.inline(cell)).font(.system(size: 13, weight: r == 0 ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading).border(Color.line, width: 0.5)
                        }
                    }.background(r == 0 ? Color.ink.opacity(0.04) : .clear)
                }
            }
        case .code(let s):
            Text(s).font(.system(size: 12.5, design: .monospaced)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink.opacity(0.05), in: .rect(cornerRadius: 6))
        case .para(let s): Text(MD.inline(s)).font(.system(size: 14)).lineSpacing(4)
        case .rule: Divider().padding(.vertical, 6)
        case .image(let name, let width): VaultImage(name: name, width: width)
        }
    }
}

/// An embedded image: a vault path or bare filename, or a web URL.
struct VaultImage: View {
    let name: String; let width: CGFloat?
    @State private var image: NSImage?
    var body: some View {
        Group {
            if name.hasPrefix("http"), let url = URL(string: name) {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().controlSize(.small) }
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Label(name.components(separatedBy: "/").last ?? name, systemImage: "photo").font(.system(size: 12)).foregroundStyle(Color.ink2)
            }
        }
        .frame(maxWidth: width ?? 640, alignment: .leading).clipShape(.rect(cornerRadius: 6)).accessibilityLabel(name)
        .task(id: name) {
            guard !name.hasPrefix("http") else { return }
            let direct = Vault.root.appending(path: name)
            let file = FileManager.default.fileExists(atPath: direct.path) ? direct
                : FileManager.default.enumerator(at: Vault.root.appending(path: "Resources"), includingPropertiesForKeys: nil)?.lazy.compactMap { $0 as? URL }.first { $0.lastPathComponent == (name as NSString).lastPathComponent }
            image = file.flatMap { NSImage(contentsOf: $0) }
        }
    }
}

/// An Obsidian callout: tinted box, coloured icon and title, `+`/`-` makes it foldable.
struct Callout: View {
    let type: String; let title: String; let fold: String; let inner: [MD.Block]
    @State private var open: Bool
    init(type: String, title: String, fold: String, inner: [MD.Block]) {
        self.type = type; self.title = title; self.fold = fold; self.inner = inner
        _open = State(initialValue: fold != "-")
    }
    var body: some View {
        let (color, icon) = MD.style(type)
        VStack(alignment: .leading, spacing: 10) {
            Button { if !fold.isEmpty { withAnimation(.spring(duration: 0.25)) { open.toggle() } } } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    Text(MD.inline(title)).font(.system(size: 14, weight: .semibold))
                    if !fold.isEmpty { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0)) }
                    Spacer(minLength: 0)
                }.foregroundStyle(color).contentShape(.rect)
            }.buttonStyle(.plain).allowsHitTesting(!fold.isEmpty)
            if open && !inner.isEmpty { MarkdownBlocks(blocks: inner).padding(.leading, 21) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.28)))
        .padding(.vertical, 2)
    }
}

/// Plain-text Markdown editor for filed notes; saves with ⌘S / Save.
struct NoteEditor: View {
    let url: URL
    @Binding var text: String
    @Binding var saved: String
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
            .padding(12)
    }
}

struct NotePage: View {
    @Environment(Store.self) private var store
    let url: URL
    @State private var text = ""
    @State private var saved = ""
    @State private var editing = false
    @State private var saveError: String?
    @State private var showHistory = false
    @State private var work: AgentWork?
    @State private var newTag = ""
    @State private var newLink = ""
    @State private var showOutline = false
    @AppStorage("noteInspector") private var showInspector = true
    @State private var jump: String?

    /// Headings of the note being read, with the id of the block each one lives in.
    func headings(_ s: String) -> [(id: String, level: Int, title: String)] {
        MD.parse(Vault.body(s).components(separatedBy: "\n")).enumerated().compactMap { i, b in
            if case .heading(let n, let t) = b { return ("h\(i)", n, t.replacingOccurrences(of: "*", with: "")) } else { return nil }
        }
    }
    func outline(_ hs: [(id: String, level: Int, title: String)]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(hs, id: \.id) { h in
                    Button { jump = h.id; showOutline = false } label: {
                        Text(h.title).font(.system(size: 12, weight: h.level <= 2 ? .semibold : .regular)).lineLimit(1)
                            .padding(.leading, CGFloat(max(0, h.level - 1)) * 12).padding(.vertical, 5).padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }.buttonStyle(.glassRow)
                }
            }.padding(6)
        }.frame(width: 280).frame(maxHeight: 360)
    }

    var note: Note? { store.notes.first { $0.id == url } }

    var body: some View {
        let fm = Vault.frontmatter(saved), lists = Vault.lists(saved)
        let title = note?.display ?? url.deletingPathExtension().lastPathComponent
        let sub = (isRelation ? [fm["type"] ?? fm["Type"], fm["year"], fm["publication"], note?.course] : [note?.course, note?.kind, note?.when.map(NoteRow.format), fm["location"]]).compactMap { $0 }.joined(separator: " · ")
        let subtitle = sub.isEmpty ? url.deletingLastPathComponent().lastPathComponent : sub
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                TabBar().padding(.horizontal, 14).padding(.top, 10)
                noteToolbar
                Card {
                    if editing {
                        HStack(spacing: 0) {
                            NoteEditor(url: url, text: $text, saved: $saved)
                            Divider()
                            ScrollView { MarkdownView(text: Vault.body(text)).padding(22) }
                        }
                    }
                    else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(title).font(.system(size: 30, weight: .bold)).lineLimit(3)
                                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.ink2).lineLimit(1)
                                    Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1).padding(.vertical, 6)
                                    readView
                                }
                                .frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 40).padding(.vertical, 30).frame(maxWidth: .infinity)
                            }
                            .onChange(of: jump) { if let j = jump { withAnimation(.smooth) { proxy.scrollTo(j, anchor: .top) }; jump = nil } }
                        }
                    }
                    if let saveError { Text(saveError).font(.caption).foregroundStyle(Color.redFG).padding(10) }
                }
                .padding([.horizontal, .bottom], 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(GlassPane())
            if showInspector {
                NoteInspector(title: title, subtitle: subtitle, tint: note?.course == nil ? nil : Color.course(note?.course), text: saved,
                              jump: { jump = $0 }, edit: { change in edit(change) }) {
                    propertiesTab(fm)
                } files: {
                    filesTab(lists)
                } links: {
                    linksTab
                } agent: {
                    agentTab
                }
                .padding(14).frame(width: 300).frame(maxHeight: .infinity)
                .modifier(GlassPane())
            }
        }
        .sheet(item: $work) { AgentWorkSheet(work: $0, note: url).environment(store) }
        .task(id: url) { load() }
        .onChange(of: store.revision) { if text == saved { load() } }   // live reload unless mid-edit
    }

    /// Revision, Research and Zotero notes hang off something else, so their side column says what they are and what they relate to, instead of a to-do's status, date and agents.
    var isRelation: Bool {
        let rel = Vault.rel(url)
        return SideNav.grouped.contains { name in rel.hasPrefix(Vault.dir(name) + "/") }
    }
    /// Notes in Files and Apps: what the item is (type, course, year, source…).
    func relationDetails(_ fm: [String: String]) -> some View {
        func clean(_ v: String?) -> String? { v.map { Vault.unlink($0).trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }.flatMap { $0.isEmpty ? nil : $0 } }
        let details: [(String, String)] = [("Type", clean(fm["type"] ?? fm["Type"])), ("Course", clean(fm["course"] ?? fm["Course"])), ("Year", clean(fm["year"])),
                                          ("Source", clean(fm["publication"])), ("Date", clean(fm["date"])), ("Status", clean(fm["status"]))].compactMap { k, v in v.map { (k, $0) } }
        return VStack(spacing: 12) {
            Card(title: "Details") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details, id: \.0) { Prop(key: $0.0, value: $0.1) }
                    if let u = clean(fm["url"]), let link = URL(string: u) {
                        Button { NSWorkspace.shared.open(link) } label: { Label("Open source", systemImage: "arrow.up.forward.square") }.buttonStyle(.glassRow).font(.system(size: 12))
                    }
                    if let z = fm["zotero"] { Button { NSWorkspace.shared.open(URL(string: "zotero://select/library/items/\(z)")!) } label: { Label("Open in Zotero", systemImage: "text.book.closed") }.buttonStyle(.glassRow).font(.system(size: 12)) }
                    if details.isEmpty { Text("No details").font(.system(size: 12)).foregroundStyle(Color.ink2) }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    /// Notes in Files and Apps: what they relate to.
    func relationRelates(_ lists: [String: [String]]) -> some View {
        let relates = (lists["related"] ?? []).map { (Vault.plain($0), false) } + (lists["collections"] ?? []).map { ($0, true) }
        return VStack(spacing: 12) {
            Card(title: "Relates to") {
                ScrollView {
                    VStack(spacing: 2) {
                        if relates.isEmpty { Text("Nothing related yet").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(10) }
                        ForEach(relates, id: \.0) { value, plain in
                            if plain { Label(value, systemImage: "folder").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading) }
                            else {
                                Button { open(value, isFile: false) } label: { HStack(spacing: 8) { Image(systemName: "link").foregroundStyle(Color.ink2).frame(width: 16); Text(value).lineLimit(2).multilineTextAlignment(.leading); Spacer() }
                                    .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 7) }.buttonStyle(.glassRow)
                            }
                        }
                    }.padding(.horizontal, 6).padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: Toolbar
    /// Back and New Note on the left; the note's controls and the inspector switch on the right.
    var noteToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) { toolbarLeading; Spacer(minLength: 16); toolbarTrailing.fixedSize() }
            VStack(alignment: .leading, spacing: 10) { toolbarLeading; ScrollView(.horizontal) { toolbarTrailing.padding(.vertical, 2) }.scrollIndicators(.hidden) }
        }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 10)
    }
    var toolbarLeading: some View {
        HStack(spacing: 10) {
            Button { store.goBack() } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .medium)) }
                .buttonStyle(.glassIcon()).disabled(!store.canGoBack).help("Back (⌘[)").accessibilityLabel("Back")
            Button { store.newNote() } label: { Image(systemName: "plus").font(.system(size: 15, weight: .medium)) }
                .buttonStyle(.glassIcon(prominent: true)).help("New Note (⌘N)").accessibilityLabel("New note")
        }
    }
    var infoButton: some View {
        Button { withAnimation(.snappy(duration: 0.25)) { showInspector.toggle() } } label: { Image(systemName: "info.circle").font(.system(size: 15)) }
            .buttonStyle(.glassIcon(prominent: showInspector)).help("Inspector: contents, tasks, attachments, find, properties, agent").accessibilityLabel("Inspector")
    }
    @ViewBuilder var toolbarTrailing: some View {
        if isRelation {
            HStack(spacing: 10) {
                Button { openInObsidian() } label: { Label("Open", systemImage: "arrow.up.forward.app") }.buttonStyle(.glassAction(.header)).help("Open in Obsidian")
                infoButton
            }
        } else {
            HStack(spacing: 10) {
                if let note {
                    Button { withAnimation(.spring(duration: 0.3)) { store.cycle(note) } } label: {
                        Label(note.state.label, systemImage: note.state.icon)
                    }.buttonStyle(.glassAction(.header)).help("Press to go to: \(note.state.next.label)")
                }
                Pills(options: [(false, "Read"), (true, "Edit")], selection: $editing)
                RoundButton(icon: "waveform.circle", label: "Dictate: speak and it types into the note") {
                    editing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Dictation.start() }
                }
                if editing {
                    Button("Save") { save() }.keyboardShortcut("s").disabled(text == saved)
                        .buttonStyle(.glassAction(.header, prominent: true))
                }
                RoundButton(icon: "clock.arrow.circlepath", label: "Version history") { showHistory = true }
                    .popover(isPresented: $showHistory) { history }
                RoundButton(icon: "arrow.up.forward.app", label: "Open in Obsidian") { openInObsidian() }
                infoButton
            }
        }
    }

    // MARK: Inspector tabs that hold what the old side column did
    /// What the note is (course, date, status, tags) and what it relates to. Notes in Files and Apps show their details instead.
    @ViewBuilder func propertiesTab(_ fm: [String: String]) -> some View {
        if isRelation { relationDetails(fm) }
        else {
                    Card(title: "Properties") {
                        VStack(alignment: .leading, spacing: 10) {
                            PropRow(icon: "graduationcap.fill", label: "Course") {
                                let name = fm["course"].map(Vault.unlink) ?? ""
                                Button { if let c = note?.course { store.page = .course(c) } } label: {
                                    GlassChip(tint: Color.course(note?.course)) {
                                        HStack(spacing: 6) { Circle().fill(Color.course(note?.course)).frame(width: 7, height: 7); Text(name.isEmpty ? "—" : name).lineLimit(1) }
                                    }
                                }.buttonStyle(.plain).disabled(note?.course == nil)
                            }
                            PropRow(icon: "calendar", label: "Date") { dateControl(fm) }
                            PropRow(icon: "circle.dotted", label: "Status") {
                                let st = fm["status"] ?? ""
                                Menu {
                                    ForEach(Array(NSOrderedSet(array: TaskState.allCases.map(\.rawValue) + [fm["status"]].compactMap { $0 })) as! [String], id: \.self) { opt in
                                        Button(opt) { edit { Vault.setField($0, "status", to: opt) } }
                                    }
                                } label: {
                                    GlassChip(tint: NoteColor.status(st)) {
                                        HStack(spacing: 6) { Image(systemName: (TaskState(rawValue: st) ?? .notStarted).icon); Text(st.isEmpty ? "—" : st) }.foregroundStyle(NoteColor.status(st) == .ink2 ? Color.ink : NoteColor.status(st))
                                    }
                                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            }
                            PropRow(icon: "tag.fill", label: "Tags") {
                                FlowLayout(spacing: 6) {
                                    ForEach(lists["tags"] ?? [], id: \.self) { t in
                                        GlassChip(tint: NoteColor.tag(t)) {
                                            HStack(spacing: 5) {
                                                Text(t)
                                                Button { edit { Vault.editList($0, "tags") { $0.removeAll { Vault.plain($0) == t } } } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.ink2) }
                                                    .buttonStyle(.plain).accessibilityLabel("Remove tag \(t)")
                                            }
                                        }
                                    }
                                    TextField("Add tag", text: $newTag).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 80).padding(.horizontal, 10).padding(.vertical, 5)
                                        .glassEffect(.regular, in: .capsule)
                                        .onSubmit {
                                            let t = newTag.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
                                            newTag = ""
                                            if !t.isEmpty { edit { Vault.editList($0, "tags") { if !$0.contains(t) { $0.append(t) } } } }
                                        }
                                }
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 14).disabled(text != saved)
                    }.fixedSize(horizontal: false, vertical: true)
        }
    }
    /// The Files tab: what in the vault relates to this note (Resources, Research, Zotero, other notes) and a field to relate another.
    @ViewBuilder func filesTab(_ lists: [String: [String]]) -> some View {
        if isRelation { relationRelates(lists) }
        else if let note {
                        RelationsCard(note: note, newLink: $newLink) { q in
                            let q = q.trimmingCharacters(in: .whitespaces); newLink = ""
                            guard let n = store.notes.first(where: { $0.title.caseInsensitiveCompare(q) == .orderedSame || $0.display.caseInsensitiveCompare(q) == .orderedSame }) else { saveError = "No note called “\(q)”."; return }
                            edit { Vault.editList($0, "related") { if !$0.contains(where: { Vault.plain($0) == n.title }) { $0.append("\"[[\(n.title)]]\"") } } }
                        }
        }
    }
    /// The Links tab: the notes this one links to, and the notes that link here.
    @ViewBuilder var linksTab: some View {
        if let note {
            VStack(spacing: 12) {
                LinksToCard(note: note)
                linkedFrom(note)
            }
        }
    }
    func linkedFrom(_ note: Note) -> some View {
        let from = store.backlinks(to: note)
        return Card(title: "Linked from", trailing: from.isEmpty ? "" : "\(from.count)") {
            if from.isEmpty { Text("No other notes link here.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 16).padding(.bottom, 12) }
            else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(from) { n in
                            Button { store.page = .note(n.id) } label: { HStack(spacing: 8) { Circle().fill(Color.course(n.course)).frame(width: 7, height: 7); Text(n.display).lineLimit(1); Spacer(); Text(n.kind).font(.system(size: 10)).foregroundStyle(Color.ink2) }
                                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6).contentShape(.rect) }.buttonStyle(.glassRow)
                        }
                    }.padding(.horizontal, 6).padding(.bottom, 8)
                }.frame(maxHeight: 200)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder var agentTab: some View {
        if let note {
                        Card {
                            VStack(spacing: 0) {
                                AgentStage(id: note.course ?? Agent.manager.id, says: store.noteSays(note), chat: false).frame(height: 340)
                                if let w = AgentWork.forNote(note) {
                                    Button { work = w } label: {
                                        HStack(spacing: 8) { AgentPortrait(id: w.role, size: 20); Text(w.label).fontWeight(.medium); Spacer() }
                                            .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6)
                                    }.buttonStyle(.glassRow).padding(.horizontal, 6).padding(.bottom, 8)
                                }
                            }
                        }.fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Agents work on notes in your vault. This one isn’t in it yet.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(6)
        }
    }

    /// Study notes read as what they are (a quiz, a deck, a player…); everything else as Markdown.
    @ViewBuilder var readView: some View {
        if let k = note.flatMap({ Study.kind($0.folder) }) { StudyPreview(kind: k, text: Vault.body(saved)) }
        else { MarkdownView(text: Vault.body(saved)).padding(.vertical, 8) }
    }
    func openInObsidian() {
        var c = URLComponents(string: "obsidian://open")!
        c.queryItems = [.init(name: "vault", value: Vault.name), .init(name: "file", value: url.path.replacingOccurrences(of: Vault.root.path + "/", with: "").replacingOccurrences(of: ".md", with: ""))]
        NSWorkspace.shared.open(c.url!)
    }
    func load() { saved = (try? String(contentsOf: url, encoding: .utf8)) ?? ""; text = saved; if saved.isEmpty { editing = true } }   // a blank new note opens ready to type
    func save() {
        do { try Vault.write(text, to: url); saved = text; saveError = nil }
        catch { saveError = "Couldn’t save: \(error.localizedDescription)" }
    }
    /// Applies a frontmatter change to the saved note straight away (history keeps the old text). Disabled while the editor has unsaved changes.
    func edit(_ change: (String) -> String) {
        guard text == saved else { return }
        let new = change(saved)
        guard new != saved else { return }
        do { try Vault.write(new, to: url); saved = new; text = new; saveError = nil; store.reload() }
        catch { saveError = "Couldn’t save: \(error.localizedDescription)" }
    }
    @ViewBuilder func dateControl(_ fm: [String: String]) -> some View {
        let key = fm["due"] != nil ? "due" : "date", raw = fm[key] ?? "", withTime = raw.contains("T")
        if let when = note?.when {
            DatePicker("", selection: Binding(get: { when }, set: { d in
                let f = DateFormatter(); f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = withTime ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
                edit { Vault.setField($0, key, to: f.string(from: d)) }
            }), displayedComponents: withTime ? [.date, .hourAndMinute] : .date).labelsHidden().datePickerStyle(.compact)
                .padding(.horizontal, 4).glassEffect(.regular.tint(Color.ink.opacity(0.06)), in: .capsule)
        } else { GlassChip { Text("—") } }
    }
    var history: some View {
        let versions = Vault.history(url)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Version history").font(.system(size: 13, weight: .semibold)).padding(.bottom, 4)
            if versions.isEmpty { Text("No earlier versions yet. One is kept each time the app saves a change.").font(.system(size: 12)).foregroundStyle(Color.ink2).frame(width: 240, alignment: .leading) }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(versions) { v in
                        Button {
                            if let old = try? String(contentsOf: v.url, encoding: .utf8) { text = old; editing = true; showHistory = false }
                        } label: {
                            HStack { Text(v.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())); Spacer(); Text("Restore").foregroundStyle(Color.ink2) }
                                .font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 5).contentShape(.rect)
                        }.buttonStyle(.glassRow)
                    }
                }
            }.frame(maxHeight: 260)
            if !versions.isEmpty { Text("Restore puts it in the editor. Save to keep it; your current text is kept in history too.").font(.caption).foregroundStyle(Color.ink2).frame(width: 240, alignment: .leading) }
        }.padding(14).frame(width: 268)
    }
    func open(_ value: String, isFile: Bool) {
        if isFile || value.contains(".") && !value.hasSuffix(".md") {
            let file = Vault.root.appending(path: value)
            if FileManager.default.fileExists(atPath: file.path) { store.openFile(file) }
            return
        }
        if let n = store.notes.first(where: { $0.title == value }) { store.page = .note(n.id) }
    }
}

struct Prop: View {
    let key: String; let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(Color.ink2).frame(width: 64, alignment: .leading)
            Text(value).lineLimit(2)
        }.font(.system(size: 12))
    }
}

/// Apple Notes–style quick note: a big title line, then plain body text. Saved as `# Title` + body, shortly after typing stops.
struct QuickNote: View {
    let url: URL
    @Binding var text: String
    @Binding var saved: String
    @State private var pending: Task<Void, Never>?
    @FocusState private var focus: Field?
    @Binding var selection: TextSelection?
    enum Field { case title, body }

    // Any YAML frontmatter is kept as-is and hidden. Then the first line is the title (a `# ` heading in the file);
    // the rest is the body, kept byte-for-byte.
    var front: Substring {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return "" }
        var i = end.upperBound
        while i < text.endIndex, text[i] == "\n" { i = text.index(after: i) }
        return text[..<i]
    }
    var main: Substring { text.dropFirst(front.count) }
    var first: Substring { main.prefix { $0 != "\n" } }
    var heading: Bool { first.isEmpty || first.hasPrefix("# ") }
    var title: String { String(first.hasPrefix("# ") ? first.dropFirst(2) : first) }
    var bodyText: String { String(main.dropFirst(first.count).dropFirst()) }
    /// When the note was made: from its name (`Note 2026-10-01 0925`), since every save replaces the file and resets its creation date.
    var created: Date {
        let name = url.deletingPathExtension().lastPathComponent
        if let m = name.firstMatch(of: /(\d{4}-\d{2}-\d{2}) (\d{2})(\d{2})/), let d = Vault.parseDate("\(m.1)T\(m.2):\(m.3)") { return d }
        return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
    }
    struct Check: Identifiable { let line: Int; let done: Bool; let text: String; var id: Int { line } }
    var checklist: [Check] {
        bodyText.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { i, l in
            guard let m = l.firstMatch(of: /^\s*- \[( |x|X)\] (.*)$/) else { return nil }
            return Check(line: i, done: m.1 != " ", text: String(m.2))
        }
    }
    func toggleCheck(_ line: Int) {
        var lines = bodyText.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return }
        lines[line] = lines[line].contains("- [ ]") ? lines[line].replacingOccurrences(of: "- [ ]", with: "- [x]") : lines[line].replacingOccurrences(of: "- [x]", with: "- [ ]").replacingOccurrences(of: "- [X]", with: "- [ ]")
        text = compose(title, lines.joined(separator: "\n"))
    }
    func compose(_ t: String, _ b: String) -> String {
        String(front) + (t.isEmpty && b.isEmpty ? "" : (heading && !t.isEmpty ? "# " : "") + t + "\n" + b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(created.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                .font(.system(size: 12)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity)
            TextField("Title", text: Binding(get: { title }, set: { text = compose($0.replacingOccurrences(of: "\n", with: " "), bodyText) }))
                .textFieldStyle(.plain).font(.system(size: 26, weight: .bold))
                .focused($focus, equals: .title).onSubmit { focus = .body }
            TextEditor(text: Binding(get: { bodyText }, set: { text = compose(title, $0) }), selection: $selection)
                .font(.system(size: 15)).lineSpacing(4).scrollContentBackground(.hidden)
                .focused($focus, equals: .body)
                .overlay(alignment: .topLeading) {
                    if bodyText.isEmpty && focus != .body { Text("Start writing…").font(.system(size: 15)).foregroundStyle(Color.ink2.opacity(0.6)).padding(.leading, 5).allowsHitTesting(false) }
                }
            if !checklist.isEmpty {   // tick items without leaving the note; this rewrites only that line's "[ ]" / "[x]"
                VStack(alignment: .leading, spacing: 4) {
                    Text("Checklist · \(checklist.filter(\.done).count)/\(checklist.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(checklist) { c in
                                Button { toggleCheck(c.line) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: c.done ? "checkmark.square.fill" : "square").foregroundStyle(c.done ? Color(light: 0x705DCF, dark: 0xA99BF0) : Color.ink2)
                                        Text(c.text).strikethrough(c.done).foregroundStyle(c.done ? Color.ink2 : Color.ink).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }.font(.system(size: 13)).padding(.vertical, 3).contentShape(.rect)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 110)
                }.padding(10).background(Color.ink.opacity(0.04), in: .rect(cornerRadius: DS.Radius.row))
            }
            Text(text == saved ? "Saved to Unsorted" : "Saving…").font(.caption).foregroundStyle(Color.ink2)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .onAppear { focus = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").isEmpty ? .title : nil }
        .onChange(of: text) {
            guard text != saved else { return }
            pending?.cancel()
            pending = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { save() } }
        }
        .onDisappear { if text != saved { save() } }
    }
    func save() {
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        saved = text
    }
}

// MARK: Formatting bar (writes Markdown, so Obsidian reads it the same). Lives in the page header, next to Open.
extension QuickNote {
    var formatBar: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Heading") { line("## ") }
                Button("Subheading") { line("### ") }
                Button("Body") { line("") }
            } label: { Image(systemName: "textformat").frame(width: 30, height: 30) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Text style")
            bar("bold", "Bold") { wrap("**") }
            bar("italic", "Italic") { wrap("*") }
            bar("strikethrough", "Strikethrough") { wrap("~~") }
            bar("highlighter", "Highlight") { wrap("==") }
            bar("chevron.left.forwardslash.chevron.right", "Code") { wrap("`") }
            Divider().frame(height: 18).padding(.horizontal, 2)
            bar("checklist", "Checklist") { line("- [ ] ") }
            bar("list.bullet", "Bulleted list") { line("- ") }
            bar("list.number", "Numbered list") { line("1. ") }
            bar("text.quote", "Quote") { line("> ") }
            Divider().frame(height: 18).padding(.horizontal, 2)
            bar("link", "Link to a note") { wrap("[[", "]]") }
            bar("tablecells", "Table") { block("| Column | Column |\n| --- | --- |\n|  |  |") }
            bar("minus", "Divider") { block("---") }
            Divider().frame(height: 18).padding(.horizontal, 2)
            bar("waveform.circle", "Dictate: speak and it types into the note") { Dictation.start() }
        }
        .font(.system(size: 14)).foregroundStyle(Color.ink2)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
    }
    func bar(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 28, height: 30).contentShape(.rect) }
            .buttonStyle(.glassCircle).help(label).accessibilityLabel(label)
    }

    /// The selection in the body as UTF-8 offsets (the body string is rebuilt on every edit, so raw indices don't carry over).
    func selected(in b: String) -> Range<Int> {
        guard case .selection(let r)? = selection?.indices else { return b.utf8.count..<b.utf8.count }
        let lo = min(b.utf8.distance(from: b.startIndex, to: r.lowerBound), b.utf8.count)
        return lo..<min(max(lo, b.utf8.distance(from: b.startIndex, to: r.upperBound)), b.utf8.count)
    }
    func idx(_ b: String, _ o: Int) -> String.Index { b.utf8.index(b.startIndex, offsetBy: o) }
    func apply(_ b: String, cursor: Int) {
        text = compose(title, b)
        let nb = bodyText
        selection = TextSelection(insertionPoint: idx(nb, min(max(cursor, 0), nb.utf8.count)))
    }

    /// Sets the current line's prefix (heading or list); choosing the same one again removes it.
    func line(_ prefix: String) {
        var b = bodyText
        let sel = selected(in: b)
        let start = b[..<idx(b, sel.lowerBound)].lastIndex(of: "\n").map { b.index(after: $0) } ?? b.startIndex
        let current = String(b[start...].prefix { $0 != "\n" })
        let old = current.range(of: #"^(#{1,6} |- \[[ xX]\] |[-*+] |\d+[.)] |> )"#, options: .regularExpression).map { String(current[$0]) } ?? ""
        let new = old == prefix ? "" : prefix
        b.replaceSubrange(start..<b.index(start, offsetBy: old.count), with: new)
        apply(b, cursor: sel.lowerBound + new.utf8.count - old.utf8.count)
    }

    /// Wraps the selection in markers, or drops an empty pair at the cursor to type into.
    func wrap(_ open: String, _ close: String? = nil) {
        let close = close ?? open
        var b = bodyText
        let sel = selected(in: b)
        let r = idx(b, sel.lowerBound)..<idx(b, sel.upperBound)
        b.replaceSubrange(r, with: open + b[r] + close)
        apply(b, cursor: sel.upperBound + open.utf8.count + (sel.isEmpty ? 0 : close.utf8.count))
    }

    /// Inserts a block (table, divider) on its own lines at the cursor.
    func block(_ s: String) {
        var b = bodyText
        let at = idx(b, selected(in: b).upperBound)
        let before = at == b.startIndex || b[b.index(before: at)] == "\n" ? "" : "\n"
        let insert = before + s + "\n"
        b.insert(contentsOf: insert, at: at)
        apply(b, cursor: b.utf8.distance(from: b.startIndex, to: at) + insert.utf8.count)
    }
}
