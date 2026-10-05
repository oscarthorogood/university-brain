import SwiftUI

/// Every tag in the vault with how many notes carry it, and the notes for the tag you pick.
struct TagsPage: View {
    @Environment(Store.self) private var store
    @State private var index: [String: [Note]] = [:]
    @State private var picked: String?
    @State private var query = ""
    var body: some View {
        let tags = index.keys.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.sorted { (index[$0]!.count, $1) > (index[$1]!.count, $0) }
        VStack(spacing: 0) {
            PageHeader(title: "Tags", subtitle: "\(index.count) tags across \(Set(index.values.flatMap { $0.map(\.id) }).count) notes") {
                HStack(spacing: 6) { Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2); TextField("Filter tags", text: $query).textFieldStyle(.plain).frame(width: 160) }
                    .font(.system(size: 13)).glassField()
            }
            SplitPane(fixed: .first, width: 300, stacked: (360, 460)) {
                Card(title: "Tags", trailing: "\(tags.count)") {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tags, id: \.self) { t in
                                Button { picked = t } label: {
                                    HStack { Text("#" + t).lineLimit(1); Spacer(); Text("\(index[t]!.count)").foregroundStyle(Color.ink2).monospacedDigit() }
                                        .font(.system(size: 13, weight: picked == t ? .semibold : .regular)).padding(.horizontal, 16).padding(.vertical, 7).contentShape(.rect)
                                }.buttonStyle(.glass(radius: DS.Radius.row, selected: picked == t))
                            }
                        }.padding(.horizontal, 6)
                    }
                }
            } second: {
                Card(title: picked.map { "#" + $0 } ?? "Notes", trailing: picked.map { "\(index[$0]?.count ?? 0)" } ?? "") {
                    if let p = picked, let notes = index[p] { NoteList(notes: notes.sorted { ($0.when ?? .distantPast) > ($1.when ?? .distantPast) }) }
                    else { Text("Pick a tag").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }.padding([.horizontal, .bottom], 12)
        }
        .task(id: store.revision) {
            let notes = store.notes
            index = await Task.detached { Self.build(notes) }.value
        }
    }

    nonisolated static func build(_ notes: [Note]) -> [String: [Note]] {
        var out: [String: [Note]] = [:]
        for n in notes {
            guard let text = try? String(contentsOf: n.id, encoding: .utf8) else { continue }
            for raw in Vault.rawItems(text, "tags") {
                let t = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'#"))
                if !t.isEmpty { out[t, default: []].append(n) }
            }
        }
        return out
    }
}
