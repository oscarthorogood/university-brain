import SwiftUI

// The right-hand inspector of a note: a header, a row of icon tabs, and one panel.
// Contents, Tasks, Attachments and Find read the note's own text; Properties and Agent hold what the old side column did.

enum InspectorTab: String, CaseIterable {
    case contents, tasks, attachments, find, properties, files, links, agent
    var icon: String {
        switch self {
        case .contents: "list.bullet"
        case .tasks: "checkmark.circle"
        case .attachments: "paperclip"
        case .find: "doc.text.magnifyingglass"
        case .properties: "slider.horizontal.3"
        case .files: "folder"
        case .links: "link"
        case .agent: "sparkles"
        }
    }
    var label: String {
        switch self {
        case .contents: "Contents"
        case .tasks: "Tasks"
        case .attachments: "Attachments"
        case .find: "Find"
        case .properties: "Properties"
        case .files: "Files"
        case .links: "Links"
        case .agent: "Agent"
        }
    }
}

/// What can be read out of a note's text.
enum NoteParts {
    struct Heading: Identifiable { let id: Int; let level: Int; let title: String }   // id: the heading's line in the body
    struct TaskItem: Identifiable { let id: Int; let heading: String; let text: String; let done: Bool }   // id: line number in the whole file
    struct Attachment: Identifiable { let id: String; let title: String; let target: String; let icon: String; let web: Bool }

    /// Headings of the note body, each with its line number (what the editor scrolls to).
    static func headings(_ text: String) -> [Heading] {
        var out: [Heading] = [], fenced = false
        for (i, raw) in NoteText.body(text).components(separatedBy: "\n").enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
            if !fenced, let m = raw.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                out.append(Heading(id: i, level: m.1.count, title: String(m.2).replacingOccurrences(of: "*", with: "")))
            }
        }
        return out
    }

    /// Checklist lines (`- [ ] …`), each with the heading it sits under.
    static func tasks(_ text: String) -> [TaskItem] {
        let lines = text.components(separatedBy: "\n")
        var start = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        var out: [TaskItem] = [], heading = ""
        for i in start..<lines.count {
            let line = lines[i]
            if let m = line.wholeMatch(of: /\s{0,3}(#{1,6})\s+(.*)/) { heading = String(m.2).replacingOccurrences(of: "*", with: "") }
            else if let m = line.wholeMatch(of: /\s*[-*+]\s\[([ xX])\]\s?(.*)/) { out.append(TaskItem(id: i, heading: heading, text: String(m.2), done: m.1 != " ")) }
        }
        return out
    }

    static let fileTypes: Set<String> = ["pdf", "png", "jpg", "jpeg", "gif", "heic", "webp", "pptx", "ppt", "docx", "doc", "xlsx", "csv", "mp3", "m4a", "wav", "mp4", "mov", "zip"]

    /// Embedded images and files, links to files, and web links.
    static func attachments(_ text: String) -> [Attachment] {
        let body = NoteText.body(text)
        var out: [Attachment] = [], seen = Set<String>()
        func add(_ title: String, _ target: String, web: Bool) {
            guard seen.insert(target).inserted else { return }
            let ext = (target as NSString).pathExtension.lowercased()
            let icon = web ? "link" : ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) ? "photo" : ext == "pdf" ? "doc.richtext" : "doc"
            out.append(Attachment(id: target, title: title, target: target, icon: icon, web: web))
        }
        for m in body.matches(of: /(!?)\[\[([^\]|#]+)[^\]]*\]\]/) {
            let target = String(m.2).trimmingCharacters(in: .whitespaces)
            if m.1 == "!" || fileTypes.contains((target as NSString).pathExtension.lowercased()) { add((target as NSString).lastPathComponent, target, web: false) }
        }
        for m in body.matches(of: /(!?)\[([^\]]*)\]\(([^)\s]+)[^)]*\)/) {
            let target = String(m.3)
            add(m.2.isEmpty ? target : String(m.2), target, web: target.hasPrefix("http"))
        }
        return out
    }
}

extension Store {
    /// [[Note]] → that note; [[Resources/…/file.pdf]] or a bare filename → the file.
    func openTarget(_ target: String) {
        if let n = notes.first(where: { $0.title == target || $0.path == target || target.hasSuffix("/" + $0.title) }) { page = .note(n.id); return }
        let direct = Vault.root.appending(path: Vault.real(target))
        if FileManager.default.fileExists(atPath: direct.path) { openFile(direct); return }
        let name = (target as NSString).lastPathComponent
        let inbox = Vault.root.appending(path: "Unsorted/" + name)
        if FileManager.default.fileExists(atPath: inbox.path) { openFile(inbox); return }
        let found = FileManager.default.enumerator(at: Vault.root.appending(path: Vault.dir("Resources")), includingPropertiesForKeys: nil)?
            .lazy.compactMap { $0 as? URL }.first { $0.lastPathComponent == name }
        if let found { openFile(found) }
    }
}

/// The row of icon tabs: one glass pill that slides between them.
struct InspectorTabs: View {
    @Binding var selection: InspectorTab
    @Namespace private var ns
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(InspectorTab.allCases, id: \.self) { t in
                    let on = selection == t
                    Button { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { selection = t } } label: {
                        Image(systemName: t.icon).font(.system(size: 14)).frame(maxWidth: .infinity).frame(height: 32)
                            .foregroundStyle(on ? Color.ink : Color.ink2)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(Color.ink.opacity(0.1)).interactive() : .identity, in: .capsule)
                    .glassEffectID(on ? "selected" : "option-\(t.rawValue)", in: ns)
                    .help(t.label).accessibilityLabel(t.label)
                }
            }
            .padding(4).glassEffect(.regular, in: .capsule)
        }
    }
}

struct NoteInspector<Props: View, FilesView: View, LinksView: View, AgentView: View>: View {
    @Environment(Store.self) private var store
    @AppStorage("inspectorTab") private var tab = InspectorTab.properties
    let title: String
    let subtitle: String
    var tint: Color? = nil
    let text: String                                  // the note as saved, frontmatter included
    let jump: (Int) -> Void                           // scroll the editor to a line of the body
    let edit: ((String) -> String) -> Void            // apply a change to the note's text and save it
    @ViewBuilder var properties: Props
    @ViewBuilder var files: FilesView
    @ViewBuilder var links: LinksView
    @ViewBuilder var agent: AgentView
    @State private var current: Int?
    @State private var hideDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 18)).foregroundStyle(Color.ink2)
                    .frame(width: 38, height: 38).background(Color.card.opacity(0.8), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            InspectorTabs(selection: $tab)
            content
        }
        .padding(.horizontal, 4).padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder var content: some View {
        switch tab {
        case .contents: contents
        case .tasks: tasks
        case .attachments: attachments
        case .find: FindPane(text: text, jump: jump)
        case .properties: properties.scrollsWhenShort()
        case .files: files.scrollsWhenShort()
        case .links: links.scrollsWhenShort()
        case .agent: agent.scrollsWhenShort()
        }
    }

    func heading(_ s: String) -> some View { Text(s).font(.system(size: 15, weight: .semibold)).padding(.horizontal, 6) }

    // MARK: Contents
    @ViewBuilder var contents: some View {
        let hs = NoteParts.headings(text)
        VStack(alignment: .leading, spacing: 8) {
            heading("Table of Contents")
            if hs.isEmpty { Text("No headings yet. Start a line with # to add one.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 6) }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(hs) { h in
                        Button { current = h.id; jump(h.id) } label: {
                            Text(h.title).font(.system(size: 13, weight: h.level <= 2 ? .semibold : .regular)).lineLimit(1)
                                .padding(.leading, CGFloat(max(0, h.level - 1)) * 12)
                                .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }.buttonStyle(SideRowStyle(selected: current == h.id))
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    // MARK: Tasks
    func toggle(_ t: NoteParts.TaskItem) {
        edit { whole in
            var lines = whole.components(separatedBy: "\n")
            guard t.id < lines.count else { return whole }
            lines[t.id] = t.done ? lines[t.id].replacing(/\[[xX]\]/, with: "[ ]", maxReplacements: 1) : lines[t.id].replacing(/\[ \]/, with: "[x]", maxReplacements: 1)
            return lines.joined(separator: "\n")
        }
    }
    @ViewBuilder var tasks: some View {
        let all = NoteParts.tasks(text)
        let shown = hideDone ? all.filter { !$0.done } : all
        // Keep the note's order: a new group starts whenever the heading changes.
        let groups: [(heading: String, items: [NoteParts.TaskItem])] = shown.reduce(into: []) { acc, t in
            if let last = acc.last, last.heading == t.heading { acc[acc.count - 1].items.append(t) } else { acc.append((t.heading, [t])) }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                heading("Tasks")
                Spacer()
                Menu {
                    Toggle("Hide completed", isOn: $hideDone)
                } label: { Image(systemName: "ellipsis").foregroundStyle(Color.ink2).frame(width: 28, height: 24).contentShape(.rect) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            if all.isEmpty { Text("No tasks in this note. Add a line like “- [ ] Do the reading”.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 6) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        VStack(alignment: .leading, spacing: 4) {
                            if !g.heading.isEmpty {
                                Text(g.heading).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 6).padding(.bottom, 2)
                                Rectangle().fill(Color.line.opacity(0.7)).frame(height: 1).padding(.horizontal, 6)
                            }
                            ForEach(g.items) { t in
                                Button { toggle(t) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                                        Image(systemName: t.done ? "checkmark.square.fill" : "square").foregroundStyle(t.done ? Color.ink2 : Color.ink2.opacity(0.8))
                                        Text(t.text).font(.system(size: 13)).strikethrough(t.done).foregroundStyle(t.done ? Color.ink2 : Color.ink)
                                            .multilineTextAlignment(.leading).lineLimit(3)
                                        Spacer(minLength: 0)
                                    }.padding(.horizontal, 6).padding(.vertical, 4).contentShape(.rect)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    // MARK: Attachments
    @ViewBuilder var attachments: some View {
        let items = NoteParts.attachments(text)
        VStack(alignment: .leading, spacing: 8) {
            heading("Attachments")
            if items.isEmpty {
                Text("Images, links and files added to this note will appear here.").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.horizontal, 6)
            }
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(items) { a in
                        Button {
                            if a.web, let u = URL(string: a.target) { NSWorkspace.shared.open(u) } else { store.openTarget(a.target) }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: a.icon).foregroundStyle(Color.ink2).frame(width: 18)
                                Text(a.title).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(.rect)
                        }.buttonStyle(.glassRow)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }
}

/// Find in this note: a field, the number of matches, arrows to step through them, and the matching lines.
private struct FindPane: View {
    let text: String
    let jump: (Int) -> Void
    @State private var query = ""
    @State private var matchCase = false
    @State private var index = 0

    struct Hit: Identifiable { let id: Int; let snippet: String }   // id: the line in the body

    /// Matching lines of the note's body.
    var hits: [Hit] {
        guard !query.isEmpty else { return [] }
        var out: [Hit] = []
        for (i, raw) in NoteText.body(text).components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if matchCase ? line.contains(query) : line.localizedCaseInsensitiveContains(query) { out.append(Hit(id: i, snippet: String(line.prefix(90)))) }
        }
        return out
    }

    func step(_ delta: Int, _ list: [Hit]) {
        guard !list.isEmpty else { return }
        index = (index + delta + list.count) % list.count
        jump(list[index].id)
    }

    var body: some View {
        let list = hits
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    Toggle("Match case", isOn: $matchCase)
                } label: { HStack(spacing: 4) { Text("Find").font(.system(size: 15, weight: .semibold)); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) } }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Spacer()
            }.padding(.horizontal, 6)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                TextField("Text in note…", text: $query).textFieldStyle(.plain).onSubmit { step(1, list) }
            }.font(.system(size: 13)).glassField()
            HStack {
                Text(query.isEmpty ? "" : list.isEmpty ? "No results in this note" : "\(index + 1) of \(list.count)").font(.system(size: 12)).foregroundStyle(Color.ink2)
                Spacer()
                Button { step(-1, list) } label: { Image(systemName: "arrow.up") }.buttonStyle(.plain).disabled(list.isEmpty).help("Previous")
                Button { step(1, list) } label: { Image(systemName: "arrow.down") }.buttonStyle(.plain).disabled(list.isEmpty).help("Next")
            }.foregroundStyle(Color.ink2).padding(.horizontal, 6)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { n, h in
                        Button { index = n; jump(h.id) } label: {
                            Text(h.snippet).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }.buttonStyle(SideRowStyle(selected: n == index))
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .onChange(of: query) { index = 0; if let first = hits.first { jump(first.id) } }
    }
}
