import SwiftUI
import AppKit

/// Wraps its children onto new lines, for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 280
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

/// A small tinted glass pill, the building block of the Properties card.
struct GlassChip<Content: View>: View {
    var tint: Color = .ink2
    @ViewBuilder var content: Content
    var body: some View {
        content.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular.tint(tint.opacity(0.28)), in: .capsule)
    }
}

/// One line of the Properties card: an icon and label, then the value as chips.
struct PropRow<Content: View>: View {
    let icon: String; let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label(label, systemImage: icon).labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.ink2)
                .frame(width: 68, alignment: .leading).padding(.top, 6)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum NoteColor {
    static let done = Color(light: 0x1F8A4C, dark: 0x5BD08A)
    static func status(_ s: String) -> Color {
        switch TaskState(rawValue: s) {
        case .done: done
        case .human: IM.blue
        case .agent: Color(light: 0x7A56E0, dark: 0xA68CFF)
        default: .ink2
        }
    }
    /// A steady colour per tag name.
    static func tag(_ t: String) -> Color {
        let h = t.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Color(hue: Double(abs(h) % 360) / 360, saturation: 0.6, brightness: 0.85)
    }
}

/// Something in an Apps or Files folder (Revision, Research, Zotero, Resources, OneDrive) that an Items note relates to.
struct RelationEntry: Identifiable {
    let kind: String; let title: String; let url: URL; let isFile: Bool
    var id: String { kind + url.path }
    static let kinds = Study.folders + ["Research", "Zotero", "Resources", "OneDrive"]
    static let icons = ["Research": "magnifyingglass", "Zotero": "text.book.closed", "Resources": "square.stack.3d.up", "OneDrive": "cloud"].merging(Study.kinds.map { ($0.folder, $0.icon) }) { a, _ in a }
}

extension Store {
    static let itemFolders: Set<String> = ["Lectures", "Tutorials", "Readings", "Essays", "Projects", "Exams", "TaskNotes/Tasks"]

    /// Targets of every [[wikilink]] in a note, as written.
    private func linkTargets(_ text: String) -> [String] {
        text.matches(of: /\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]/).map { String($0.1) }
    }

    /// Everything in the Apps and Files folders that this note links to or that links to it.
    func relations(of note: Note) -> [RelationEntry] {
        let text = (try? String(contentsOf: note.id, encoding: .utf8)) ?? "", fm = FileManager.default
        var out: [RelationEntry] = [], seen = Set<String>()
        func add(_ e: RelationEntry) { if seen.insert(e.id).inserted { out.append(e) } }
        for target in linkTargets(text) {
            let name = (target as NSString).lastPathComponent, ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty, ext != "md", ext.count <= 5 {   // a file
                let rel = Vault.real(target), u = Vault.root.appending(path: rel)
                guard fm.fileExists(atPath: u.path) else { continue }
                if rel.hasPrefix(Vault.dir("OneDrive") + "/") { add(.init(kind: "OneDrive", title: name, url: u, isFile: true)) }
                else if rel.hasPrefix(Vault.dir("Resources") + "/") { add(.init(kind: "Resources", title: name, url: u, isFile: true)) }
            } else if let n = notes.first(where: { $0.title == name }), (Study.isStudy(n.folder) || n.folder == "Research") {
                add(.init(kind: n.folder, title: n.display, url: n.id, isFile: false))
            } else {
                let z = Zotero.dir.appending(path: name + ".md")
                if fm.fileExists(atPath: z.path) { add(.init(kind: "Zotero", title: name, url: z, isFile: false)) }
            }
        }
        for n in backlinks(to: note) where (Study.isStudy(n.folder) || n.folder == "Research") { add(.init(kind: n.folder, title: n.display, url: n.id, isFile: false)) }
        return out.sorted { (RelationEntry.kinds.firstIndex(of: $0.kind) ?? 9) < (RelationEntry.kinds.firstIndex(of: $1.kind) ?? 9) }
    }

    /// Other Items notes this one links to.
    func linksTo(_ note: Note) -> [Note] {
        let text = (try? String(contentsOf: note.id, encoding: .utf8)) ?? ""
        let byTitle = Dictionary(notes.map { ($0.title, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<URL>()
        return linkTargets(text).compactMap { byTitle[($0 as NSString).lastPathComponent] }
            .filter { $0.id != note.id && Self.itemFolders.contains($0.folder) && seen.insert($0.id).inserted }
    }

    /// What the course agent has to say about one note, worked out from the note itself.
    func noteSays(_ n: Note) -> [Say] {
        let text = (try? String(contentsOf: n.id, encoding: .utf8)) ?? "", fm = Vault.frontmatter(text), body = Vault.body(text)
        func tidy(_ s: String, _ cap: Int = 90) -> String {
            var t = s.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
            t = t.replacingOccurrences(of: "[*_`>]", with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " -\"\t"))
            return t.count > cap ? String(t.prefix(cap - 1)) + "…" : t
        }
        var out: [Say] = []
        if let s = fm["summary"].map({ tidy($0, 130) }), !s.isEmpty { out.append(Say(text: s)) }
        // bullets under a "key concepts" / "thesis" style heading
        let lines = body.components(separatedBy: "\n")
        if let h = lines.firstIndex(where: { line in line.hasPrefix("#") && ["key concepts", "thesis", "key ideas", "argument"].contains { line.lowercased().contains($0) } }) {
            let items = lines[(h + 1)...].prefix { !$0.hasPrefix("#") }.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.first?.isNumber == true }.map { tidy($0) }.filter { $0.count > 6 && !$0.lowercased().contains("placeholder") }
            for i in items.prefix(2) { out.append(Say(text: "Key idea: " + i)) }
        }
        if let w = n.when {
            let d = days(w)
            if !n.done { out.append(Say(text: d > 0 ? "This is due in \(d) day\(d == 1 ? "" : "s")." : d == 0 ? "This is today." : "This was \(-d) day\(d == -1 ? "" : "s") ago.")) }
        }
        let open = lines.filter { $0.contains("- [ ]") }.count
        if open > 0 { out.append(Say(text: "\(open) checklist item\(open == 1 ? "" : "s") left on this one.")) }
        let files = (Vault.lists(text)["resources"] ?? []).count
        if files > 0 { out.append(Say(text: "\(files) file\(files == 1 ? "" : "s") linked: slides and documents to read with it.")) }
        if n.unfilled && ["Lectures", "Tutorials", "Readings"].contains(n.folder) { out.append(Say(text: "Not written up yet.")) }
        let words = body.split { $0.isWhitespace }.count
        if words > 150 { out.append(Say(text: "About \(words) words of notes here.")) }
        return out.isEmpty ? [Say(text: "Nothing to flag on this one.")] : Array(out.prefix(6))
    }
}

/// The Related card: grouped by folder, each row opens the note or file.
struct RelationsCard: View {
    @Environment(Store.self) private var store
    let note: Note
    @Binding var newLink: String
    let onLink: (String) -> Void
    var body: some View {
        let all = store.relations(of: note)
        Card(title: "Files", trailing: all.isEmpty ? "" : "\(all.count)") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if all.isEmpty { Text("Nothing in your study folders, Research, Zotero, Resources or OneDrive relates to this yet.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(10) }
                    ForEach(RelationEntry.kinds, id: \.self) { kind in
                        let group = all.filter { $0.kind == kind }
                        if !group.isEmpty {
                            Label("\(kind) · \(group.count)", systemImage: RelationEntry.icons[kind] ?? "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2)
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
                            ForEach(group) { e in
                                Button { e.isFile ? store.openFile(e.url) : (store.page = .note(e.url)) } label: {
                                    HStack(spacing: 8) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: e.url.path)).resizable().frame(width: 16, height: 16)
                                        Text(e.title).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6).contentShape(.rect)
                                }.buttonStyle(.glassRow)
                            }
                        }
                    }
                }.padding(.horizontal, 6)
            }.frame(maxHeight: 240)
            TextField("Relate a note…", text: $newLink).textFieldStyle(.plain).font(.system(size: 12)).glassField(height: 28).padding(.horizontal, 12).padding(.vertical, 10)
                .onSubmit { onLink(newLink) }
        }
    }
}

/// The Links to card: the other Items notes this one links to.
struct LinksToCard: View {
    @Environment(Store.self) private var store
    let note: Note
    var body: some View {
        let to = store.linksTo(note)
        Card(title: "Links to", trailing: to.isEmpty ? "" : "\(to.count)") {
            if to.isEmpty { Text("Doesn’t link to any other notes.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 16).padding(.bottom, 12) }
            else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(to) { n in
                            Button { store.page = .note(n.id) } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Color.course(n.course)).frame(width: 7, height: 7)
                                    Text(n.display).lineLimit(1); Spacer()
                                    Text(n.kind).font(.system(size: 10)).foregroundStyle(Color.ink2)
                                }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6).contentShape(.rect)
                            }.buttonStyle(.glassRow)
                        }
                    }.padding(.horizontal, 6).padding(.bottom, 8)
                }.frame(maxHeight: 150)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
