import SwiftUI

// The other kinds of note that open as what they are rather than as text, the way the four apps do: a past paper you work through, a mind map you fold,
// and summaries, research briefs and exams as cards, one per section. "Edit note" is the only way to see the Markdown.

enum SheetKind: String {
    case pastPaper = "Past Papers", summary = "Summaries", mindMap = "Mind Maps", research = "Research", exam = "Exams"
    var noun: String {
        switch self { case .pastPaper: "Past Paper"; case .summary: "Summary"; case .mindMap: "Mind Map"; case .research: "Research brief"; case .exam: "Exam" }
    }
    var icon: String {
        switch self {
        case .pastPaper: "doc.text.magnifyingglass"; case .summary: "list.bullet.rectangle"; case .mindMap: "point.3.connected.trianglepath.dotted"
        case .research: "magnifyingglass.circle"; case .exam: "pencil.and.list.clipboard"
        }
    }
}

extension Store {
    /// The page style a note opens in, unless it is being edited (then it is an ordinary note page).
    func sheetKind(for p: Page) -> SheetKind? {
        guard case .note(let u) = p, !editingApps.contains(u), let n = notes.first(where: { $0.id == u }) else { return nil }
        return SheetKind(rawValue: n.folder)
    }
}

private func rich(_ s: String) -> Text { Text(MD.inline(s)) }

/// What a note shows when it has nothing the page can use yet: what is missing, and the way to add it. The Markdown stays behind "Edit note".
struct EmptyAppNote: View {
    @Environment(Store.self) private var store
    let url: URL
    let icon: String, title: String, hint: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Color.ink2.opacity(0.7))
            Text(title).font(.system(size: 18, weight: .semibold, design: .serif))
            Text(hint).font(.system(size: 13)).foregroundStyle(Color.ink2).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button { store.editingApps.insert(url) } label: { Label("Edit note", systemImage: "square.and.pencil") }.buttonStyle(.glassAction(.header, prominent: true))
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One note of one of the other kinds, shown the way that kind works.
struct SheetPage: View {
    @Environment(Store.self) private var store
    let url: URL
    let kind: SheetKind
    var body: some View {
        let _ = store.revision
        let text = StudyCache.text(url)
        VStack(spacing: 0) {
            AppNoteHeader(url: url, kindLabel: kind.noun)
            Group {
                switch kind {
                case .pastPaper:
                    let items = StudyParse.paper(text)
                    if items.isEmpty { empty("No questions yet", "Add the paper’s questions with their marks, each followed by its answer or mark scheme.") } else { PaperRunner(url: url, items: items) }
                case .mindMap:
                    let nodes = StudyParse.tree(text)
                    if nodes.count < 2 { empty("No map yet", "Add a nested list: the first item is the centre and each indent is a branch.") } else { MindMapExplorer(nodes: nodes) }
                case .summary, .research, .exam:
                    SectionCards(url: url, kind: kind)
                }
            }
        }
    }
    func empty(_ title: String, _ hint: String) -> some View { EmptyAppNote(url: url, icon: kind.icon, title: title, hint: hint) }
}

/// Past paper: one question at a time, the answer when you ask for it, and a tally of what you got right.
struct PaperRunner: View {
    let url: URL
    let items: [(question: String, answer: String)]
    @State private var index = 0
    @State private var shown = false
    @State private var marks: [Int: Bool] = [:]

    var body: some View {
        let right = marks.values.filter { $0 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Question \(index + 1) of \(items.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink2)
                    Spacer()
                    if !marks.isEmpty { Text("\(right) of \(marks.count) right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NoteColor.done).monospacedDigit() }
                    Menu {
                        Button("Start again", role: .destructive) { marks = [:]; index = 0; shown = false }
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24).contentShape(.rect) }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                MeterBar(value: Double(marks.count) / Double(max(items.count, 1)), tint: IM.blue)
                if items.indices.contains(index) {
                    let item = items[index]
                    rich(item.question).font(.system(size: 19, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(IM.blue.opacity(0.12)), in: .rect(cornerRadius: DS.Radius.card))
                    if item.answer.isEmpty {
                        Text("This question has no answer written down.").font(.system(size: 12)).foregroundStyle(Color.ink2)
                    } else if shown {
                        rich(item.answer).font(.system(size: 14)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.tint(NoteColor.done.opacity(0.16)), in: .rect(cornerRadius: DS.Radius.row))
                    } else {
                        Button { withAnimation(.smooth) { shown = true } } label: { Label("Show answer", systemImage: "eye").frame(maxWidth: .infinity) }.buttonStyle(.glassAction(.header)).keyboardShortcut(.space, modifiers: [])
                    }
                    if shown || item.answer.isEmpty {
                        HStack(spacing: 12) {
                            Button { mark(false) } label: { Label("Missed it", systemImage: "xmark").frame(maxWidth: .infinity) }.buttonStyle(.glassAction(.header)).keyboardShortcut("1", modifiers: [])
                            Button { mark(true) } label: { Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity) }.buttonStyle(.glassAction(.header, prominent: true)).keyboardShortcut("2", modifiers: [])
                        }
                    }
                    HStack {
                        RoundButton(icon: "chevron.left", label: "Previous question") { go(index - 1) }.disabled(index == 0).opacity(index == 0 ? 0.4 : 1)
                        Spacer()
                        RoundButton(icon: "chevron.right", label: "Next question") { go(index + 1) }.disabled(index >= items.count - 1).opacity(index >= items.count - 1 ? 0.4 : 1)
                    }
                }
            }.frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
        }
    }
    func mark(_ right: Bool) { marks[index] = right; if index < items.count - 1 { go(index + 1) } }
    func go(_ i: Int) { withAnimation(.smooth) { index = min(max(i, 0), items.count - 1); shown = false } }
}

/// Mind map: the branches fold and unfold, so you can see the shape first and open one idea at a time.
struct MindMapExplorer: View {
    let nodes: [(level: Int, text: String)]
    @State private var folded: Set<Int> = []
    private let hues: [Color] = [IM.blue, NoteColor.done, Color(light: 0xC77A00, dark: 0xF0B366), Color(light: 0x7A56E0, dark: 0xA68CFF), Color(light: 0xB42318, dark: 0xFF8A7A)]

    /// Which nodes show: everything under a folded node is hidden until it is opened.
    private var visible: [Int] {
        var out: [Int] = [], hideBelow: Int?
        for (i, n) in nodes.enumerated() {
            if let h = hideBelow { if n.level > h { continue } else { hideBelow = nil } }
            out.append(i)
            if folded.contains(i) { hideBelow = n.level }
        }
        return out
    }
    private func hasChildren(_ i: Int) -> Bool { i + 1 < nodes.count && nodes[i + 1].level > nodes[i].level }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button { withAnimation(.smooth) { folded = Set(nodes.indices.filter { hasChildren($0) && nodes[$0].level > 0 }) } } label: { Label("Fold branches", systemImage: "arrow.down.right.and.arrow.up.left") }
                        .buttonStyle(.glassAction(.control))
                    Button { withAnimation(.smooth) { folded = [] } } label: { Label("Open all", systemImage: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.glassAction(.control))
                }.padding(.bottom, 6)
                ForEach(visible, id: \.self) { i in
                    let n = nodes[i]
                    HStack(spacing: 0) {
                        ForEach(0..<n.level, id: \.self) { _ in Rectangle().fill(Color.line).frame(width: 1, height: 28).padding(.horizontal, 13) }
                        if n.level > 0 { Rectangle().fill(Color.line).frame(width: 14, height: 1) }
                        Button { if hasChildren(i) { withAnimation(.smooth) { if folded.contains(i) { folded.remove(i) } else { folded.insert(i) } } } } label: {
                            HStack(spacing: 6) {
                                if hasChildren(i) { Image(systemName: folded.contains(i) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.ink2) }
                                rich(n.text).font(.system(size: n.level == 0 ? 15 : 13, weight: n.level == 0 ? .semibold : .regular))
                            }.padding(.horizontal, 12).padding(.vertical, 6).contentShape(.capsule)
                        }.buttonStyle(.plain).glassEffect(.regular.tint(hues[n.level % hues.count].opacity(n.level == 0 ? 0.35 : 0.2)), in: .capsule)
                    }
                }
            }.padding(24)
        }
    }
}

/// Summaries, research briefs and exams: each section of the note as a card of its own, with the Markdown's marks (quote bars, callout lines, `##`) gone.
/// A section that is still only the template's scaffolding is left out, and named at the bottom so you know what is waiting to be filled in.
struct SectionCards: View {
    let url: URL
    let kind: SheetKind
    var body: some View {
        let full = StudyCache.text(url)
        let template = Sections.template(forFolder: kind.rawValue)
        let sections = Sections.parse(full).sections.filter { !$0.title.isEmpty }
        let filled = sections.filter { Sections.hasContent($0.title, in: full, template: template) }
        let empty = sections.filter { s in !filled.contains { $0.title == s.title } }
        if filled.isEmpty {
            EmptyAppNote(url: url, icon: kind.icon, title: "Nothing written yet", hint: "Press Edit note to fill in this \(kind.noun.lowercased()). What you add shows here as cards.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(filled.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Self.plainTitle(s.title).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.ink2)
                            MarkdownBlocks(blocks: MD.parse(Self.unwrap(s.body).components(separatedBy: "\n")))
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).appCard()
                    }
                    if !empty.isEmpty {
                        Text("Not filled in yet: " + empty.map { Self.plainTitle($0.title) }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 4)
                    }
                }.frame(maxWidth: 720).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
        }
    }

    /// A heading without its emoji.
    static func plainTitle(_ t: String) -> String {
        String(String.UnicodeScalarView(t.unicodeScalars.filter { !($0.properties.isEmoji && $0.value > 0x7F) && $0.value != 0xFE0F && $0.value != 0x200D })).trimmingCharacters(in: .whitespaces)
    }
    /// A callout's lines without the quote marks, and without its `[!type] Title` line (the card's own heading says it).
    static func unwrap(_ body: String) -> String {
        body.components(separatedBy: "\n").compactMap { line -> String? in
            var t = Substring(line), quoted = false
            while t.hasPrefix(">") { t = t.dropFirst(); if t.hasPrefix(" ") { t = t.dropFirst() }; quoted = true }
            if quoted, t.hasPrefix("[!") { return nil }
            return String(t)
        }.joined(separator: "\n")
    }
}
