import SwiftUI
import AppKit

extension Store {
    /// Runs a Zotero sync and remembers how it went (the Zotero page shows it).
    @discardableResult func syncZotero() async -> (text: String, changed: Bool) {
        guard !zoteroSyncing else { return ("Already syncing.", false) }
        zoteroSyncing = true; defer { zoteroSyncing = false }
        let r = await Zotero.sync()
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastZoteroSync")   // a number, because the page reads it with @AppStorage
        UserDefaults.standard.set(r.text, forKey: "lastZoteroResult")
        reload()
        return r
    }
}

/// The right-hand dock's Zotero page: laid out like Resources (collections on the left, items grouped by type on the right).
struct ZoteroPage: View {
    @Environment(Store.self) private var store
    @AppStorage("lastZoteroSync") private var last: Double = 0
    @AppStorage("lastZoteroResult") private var result = ""
    @State private var connected = Zotero.Config.connected
    @State private var key = ""
    @State private var problem = ""
    @State private var connecting = false
    @State private var rows: [Row] = []
    @State private var paths: [String] = []
    struct Row: Identifiable { let url: URL; let title: String; let year: String; let collections: [String]; let pdf: URL?; var id: URL { url } }
    static let unfiled = "Unfiled"
    static let top = "In the folder itself"

    static func rows() -> [Row] {
        ((try? FileManager.default.contentsOfDirectory(atPath: Zotero.dir.path)) ?? []).filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.compactMap { n in
            let url = Zotero.dir.appending(path: n)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let pdf = url.deletingPathExtension().appendingPathExtension("pdf")
            return Row(url: url, title: String(n.dropLast(3)), year: Vault.frontmatter(text)["year"] ?? "", collections: Vault.lists(text)["collections"] ?? [],
                       pdf: FileManager.default.fileExists(atPath: pdf.path) ? pdf : nil)
        }
    }

    /// The left list is Zotero's top-level folders; subfolders become the groups on the right.
    static func first(_ path: String) -> String { path.components(separatedBy: Zotero.pathSeparator)[0] }
    var folders: [String] { Set((rows.flatMap(\.collections) + paths).map(Self.first)).sorted() + (rows.contains { $0.collections.isEmpty } ? [Self.unfiled] : []) }

    init() { UserDefaults.standard.register(defaults: ["allDefault.Zotero": true]) }   // Zotero's folders are your own, not this semester's courses
    var body: some View {
        Group { if connected { library } else { connect } }
            .task(id: store.revision) { rows = Self.rows(); paths = Zotero.State.load().folders ?? [] }
    }

    var library: some View {
        CourseBrowser(title: "Zotero", courses: folders, noun: "items", finder: Zotero.dir, settings: AnyView(controls)) { folder, query in
            // One group per subfolder path under this folder (an item in several subfolders shows in each).
            var groups: [String: [Row]] = [:]
            for r in rows where query.isEmpty || r.title.localizedCaseInsensitiveContains(query) {
                if folder == Self.unfiled { if r.collections.isEmpty { groups[Self.top, default: []].append(r) }; continue }
                for c in r.collections where Self.first(c) == folder {
                    let sub = c.components(separatedBy: Zotero.pathSeparator).dropFirst().joined(separator: " › ")
                    groups[sub.isEmpty ? Self.top : sub, default: []].append(r)
                }
            }
            return groups.sorted { ($0.key == Self.top ? "" : $0.key) < ($1.key == Self.top ? "" : $1.key) }.map { name, group in
                (name, "\(group.count)", group.sorted { $0.title < $1.title }.map { Entry(id: $0.url, row: AnyView(ZoteroRow(row: $0))) })
            }
        }
    }

    /// Sync lives in the cog popover, so the header is the same as Resources'.
    var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Button { Task { await store.syncZotero() } } label: { Label(store.zoteroSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.glassAction(.compact)).disabled(store.zoteroSyncing)
            Text(last == 0 ? "Not synced yet" : "Synced " + Date(timeIntervalSince1970: last).formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Color.ink2)
            if !result.isEmpty { Text(result).font(.caption).foregroundStyle(Color.ink2) }
            Button("Disconnect Zotero") { Zotero.Config.forget(); connected = false }.buttonStyle(.link)
            Divider()
        }
    }

    var connect: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Zotero", subtitle: "Not connected") { RoundButton(icon: "folder", label: "Show in Finder") { try? FileManager.default.createDirectory(at: Zotero.dir, withIntermediateDirectories: true); NSWorkspace.shared.open(Zotero.dir) } }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect your Zotero library").font(.system(size: 15, weight: .semibold))
                    Text("Your library appears as one note per item in Documents/University/Zotero, with its PDFs beside it. Tags, the “My notes” section, new notes and new PDFs you add there go back to Zotero. Deleting never syncs, in either direction.")
                        .font(.system(size: 13)).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                    Text("Make a key at zotero.org/settings/keys with library access and write access, then paste it here. It stays on this Mac, outside your vault.")
                        .font(.system(size: 13)).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        SecureField("API key", text: $key).textFieldStyle(.plain).glassField().frame(maxWidth: 320)
                        Button(connecting ? "Checking…" : "Connect") { go() }.buttonStyle(.glassAction(.header)).disabled(key.isEmpty || connecting)
                        Button("Open Zotero Settings") { NSWorkspace.shared.open(URL(string: "https://www.zotero.org/settings/keys/new")!) }.buttonStyle(.link)
                    }
                    if !problem.isEmpty { Text(problem).font(.system(size: 12)).foregroundStyle(Color.redFG) }
                    Spacer(minLength: 0)
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding([.horizontal, .bottom], 12)
        }
    }

    func go() {
        connecting = true; problem = ""
        Task {
            do {
                try await Zotero.connect(key).save()
                connected = true; key = ""
                await store.syncZotero()
            } catch { problem = error.localizedDescription }
            connecting = false
        }
    }
}

/// An item shown like a file in the Resources browser: its PDF's icon and size when it has one. Opens its note.
struct ZoteroRow: View {
    @Environment(Store.self) private var store
    let row: ZoteroPage.Row
    var body: some View {
        let size = row.pdf.flatMap { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) }
        Button { store.page = .note(row.url) } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: (row.pdf ?? row.url).path)).resizable().frame(width: 20, height: 20)
                Text(row.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? row.year).font(.system(size: 11)).foregroundStyle(Color.ink2)
            }.font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6).contentShape(.rect)
        }.buttonStyle(.glassRow)
        .contextMenu {
            Button("Open Note") { store.page = .note(row.url) }
            if let pdf = row.pdf { Button("Open PDF") { store.openFile(pdf) } }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.pdf ?? row.url]) }
        }
    }
}
