import SwiftUI

extension Store {
    struct Hit: Identifiable { let note: Note; let snippet: String?; var id: URL { note.id } }

    /// Note bodies (no frontmatter) and who links to whom, read once per vault reload.
    func index() -> (bodies: [URL: String], backlinks: [String: [Note]]) {
        if let c = bodyCache, c.rev == revision { return (c.bodies, c.backlinks) }
        var bodies: [URL: String] = [:], back: [String: Set<URL>] = [:]
        let titles = Set(notes.map(\.title))
        for n in notes {
            let text = (try? String(contentsOf: n.id, encoding: .utf8)) ?? ""
            bodies[n.id] = Vault.body(text)
            for m in text.matches(of: /\[\[([^\]|#]+)/) {
                let t = (String(m.1) as NSString).lastPathComponent
                if t != n.title, titles.contains(t) { back[t, default: []].insert(n.id) }
            }
        }
        let byURL = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let links = back.mapValues { $0.compactMap { byURL[$0] }.sorted { $0.title < $1.title } }
        bodyCache = (revision, bodies, links)
        return (bodies, links)
    }
    func backlinks(to note: Note) -> [Note] { index().backlinks[note.title] ?? [] }

    /// Titles first, then bodies; every word must match. Body hits carry a snippet around the first word.
    func search(_ q: String, limit: Int = 100) -> [Hit] {
        let words = q.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let byDate = { (a: Note, b: Note) in (a.when ?? .distantPast) > (b.when ?? .distantPast) }
        let titled = notes.filter { n in words.allSatisfy { n.title.range(of: $0, options: opts) != nil || n.display.range(of: $0, options: opts) != nil } }.sorted(by: byDate)
        let seen = Set(titled.map(\.id)), text = index().bodies
        let bodied = notes.filter { !seen.contains($0.id) }.compactMap { n -> Hit? in
            guard let b = text[n.id], words.allSatisfy({ b.range(of: $0, options: opts) != nil }), let r = b.range(of: words[0], options: opts) else { return nil }
            let from = b.index(r.lowerBound, offsetBy: -40, limitedBy: b.startIndex) ?? b.startIndex
            let to = b.index(r.upperBound, offsetBy: 90, limitedBy: b.endIndex) ?? b.endIndex
            let s = String(b[from..<to].map { ">*|#\n".contains($0) ? " " : $0 }).replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
            return Hit(note: n, snippet: (from > b.startIndex ? "…" : "") + s + (to < b.endIndex ? "…" : ""))
        }.sorted { byDate($0.note, $1.note) }
        return Array((titled.map { Hit(note: $0, snippet: nil) } + bodied).prefix(limit))
    }
}

/// ⌘P: type part of a title, ↑↓ to pick, ⏎ to open.
struct QuickOpen: View {
    @Environment(Store.self) private var store
    @State private var q = ""
    @State private var sel = 0
    @FocusState private var focused: Bool
    var hits: [Store.Hit] {
        let words = q.split(separator: " ")
        let m = store.notes.filter { n in words.allSatisfy { n.title.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil || n.display.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
        // prefix matches first, then newest
        return m.sorted { (a, b) in
            let pa = a.display.lowercased().hasPrefix(q.lowercased()), pb = b.display.lowercased().hasPrefix(q.lowercased())
            return pa != pb ? pa : (a.when ?? .distantPast) > (b.when ?? .distantPast)
        }.prefix(8).map { Store.Hit(note: $0, snippet: nil) }
    }
    var body: some View {
        let h = hits
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                TextField("Open note…", text: $q).textFieldStyle(.plain).font(.system(size: 17)).focused($focused)
                    .onSubmit { open(h) }
                    .onChange(of: q) { sel = 0 }
            }.padding(16)
            Divider()
            ForEach(Array(h.enumerated()), id: \.1.id) { i, hit in
                Button { sel = i; open(h) } label: {
                    HStack {
                        Circle().fill(Color.course(hit.note.course)).frame(width: 8, height: 8)
                        Text(hit.note.display).lineLimit(1)
                        Spacer()
                        Text(hit.note.kind).font(.system(size: 11)).foregroundStyle(Color.ink2)
                    }.padding(.horizontal, 16).frame(height: 34).contentShape(.rect)
                }
                .buttonStyle(.glass(radius: DS.Radius.row, selected: i == sel))
            }
            if h.isEmpty { Text(q.isEmpty ? "Start typing a note title" : "No matches").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(20) }
        }
        .font(.system(size: 14)).frame(width: 520).padding(.bottom, 6)
        .onKeyPress(.downArrow) { sel = min(sel + 1, max(h.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { sel = max(sel - 1, 0); return .handled }
        .onAppear { focused = true }
    }
    func open(_ h: [Store.Hit]) {
        guard sel < h.count else { return }
        store.page = .note(h[sel].note.id); store.quickOpen = false
    }
}
