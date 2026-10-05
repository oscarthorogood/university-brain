import SwiftUI
import AppKit

/// The shared layout for Resources, OneDrive, Revision and Research: pick a course on the left, see its items grouped by type on the right.
struct Entry: Identifiable { let id: AnyHashable; let row: AnyView }
struct CourseBrowser: View {
    let title: String
    let courses: [String]
    let noun: String                                                // "files" / "notes"
    var finder: URL?                                                // adds a "Show in Finder" button
    var listTitle = "Courses"                                       // heading of the left list
    var seasonal = true                                             // the "This semester / All courses" switch; off when the left list isn't courses
    var actions: AnyView?                                           // extra controls in the header
    var settings: AnyView?                                          // extra rows in the cog popover
    let groups: (_ course: String, _ query: String) -> [(name: String, trailing: String, entries: [Entry])]
    @State private var course: String?
    @State private var showAll = false
    @State private var query = ""

    var body: some View {
        let current = Set(Vault.courses.keys)
        let shown = !seasonal || showAll ? courses : courses.filter { current.contains($0) }
        let sel = course.flatMap { shown.contains($0) ? $0 : nil } ?? shown.first
        let gs = sel.map { groups($0, query) } ?? []
        let count = gs.reduce(0) { $0 + $1.entries.count }
        VStack(spacing: 0) {
            PageHeader(title: SideNav.label(title), subtitle: sel.map { "\($0) · \(count) \(noun)" } ?? "No courses") {
                HStack(spacing: 10) {
                    if let actions { actions }
                    if seasonal { Pills(options: [(false, "This semester"), (true, "All courses")], selection: $showAll) }
                    PageTools(title: title, finder: finder.map { f in sel.map { f.appending(path: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? f }, seasonal: seasonal, extra: settings)
                }
            }
            SplitPane(fixed: .first, width: 260, minFlex: 340, stacked: (200, 560)) {
                Card(title: listTitle) {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(shown, id: \.self) { c in
                                Button { course = c } label: {
                                    HStack { Text(c).lineLimit(1); Spacer() }.font(.system(size: 13, weight: c == sel ? .semibold : .regular))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                }.buttonStyle(.glass(radius: DS.Radius.row, selected: c == sel))
                            }
                        }.padding(.horizontal, 6).padding(.bottom, 8)
                    }
                }
            } second: {
                Card {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                        TextField("Filter \(noun)", text: $query).textFieldStyle(.plain)
                    }.font(.system(size: 13)).glassField().padding(.horizontal, 12).padding(.vertical, 10)
                    if count == 0 { Text("No \(noun)").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(gs, id: \.name) { g in
                                    Heading(g.name, trailing: g.trailing)
                                    ForEach(g.entries) { $0.row }
                                }
                            }
                        }
                    }
                }
            }.padding([.horizontal, .bottom], 12)
        }
        .onAppear { showAll = UserDefaults.standard.bool(forKey: "allDefault.\(title)") }
    }
}

/// The last two buttons in every Items, Files and Apps page's header: the folder in Finder, and a cog with that page's settings.
struct PageTools: View {
    let title: String; var finder: URL?; var seasonal = false; var extra: AnyView?
    @State private var open = false
    var body: some View {
        HStack(spacing: 10) {
            if let finder { RoundButton(icon: "folder", label: "Show in Finder") { NSWorkspace.shared.open(finder) } }
            RoundButton(icon: "gearshape", label: "Page settings") { open = true }
                .popover(isPresented: $open, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(SideNav.label(title)) settings").font(.headline)
                        if seasonal { AllDefaultToggle(title: title) }
                        if let extra { extra }
                        if SideNav.folders.contains(where: { $0.name == title }) { NavToggle(name: title, label: "Show in sidebar") }
                    }.padding(16).frame(width: 240, alignment: .leading)
                }
        }
    }
}

struct AllDefaultToggle: View {
    @AppStorage private var on: Bool
    init(title: String) { _on = AppStorage(wrappedValue: false, "allDefault.\(title)") }
    var body: some View { Toggle("Open on All courses", isOn: $on) }
}

/// Shows or hides one page in the sidebar (also listed in Settings, so a hidden page can be brought back).
struct NavToggle: View {
    let name: String; let label: String
    @AppStorage("dockHidden") private var raw = ""
    var body: some View {
        Toggle(label, isOn: Binding(
            get: { !SideNav.isHidden(name, raw) },
            set: { on in
                var s = Set(raw.split(separator: ",").map(String.init))
                if on { s.remove(name) } else { s.insert(name) }
                raw = s.sorted().joined(separator: ",")
            }))
    }
}

/// An in-app browser for Resources/ or OneDrive/: a course's files grouped by type.
struct FileBrowserPage: View {
    let root: String
    struct Item: Identifiable { let url: URL; let type: String; let size: Int; var id: URL { url } }

    var base: URL { Vault.root.appending(path: Vault.dir(root)) }
    var courses: [String] {
        ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !$0.lastPathComponent.hasPrefix(".") }
            .map(\.lastPathComponent).sorted()
    }
    func files(_ course: String) -> [Item] {
        let dir = base.appending(path: course)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let all = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []
        return all.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, !u.lastPathComponent.hasPrefix("Icon") else { return nil }
            let rel = u.resolvingSymlinksInPath().path.replacingOccurrences(of: dir.resolvingSymlinksInPath().path + "/", with: "").components(separatedBy: "/")
            return Item(url: u, type: rel.count > 1 ? rel[0] : "Files", size: v.fileSize ?? 0)
        }
    }

    var body: some View {
        CourseBrowser(title: root, courses: courses, noun: "files", finder: base) { course, query in
            let items = files(course).filter { query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
            return Dictionary(grouping: items, by: \.type).sorted { $0.key < $1.key }.map { type, group in
                (type, "\(group.count)", group.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }.map { Entry(id: $0.url, row: AnyView(FileRow(item: $0))) })
            }
        }
    }
}

/// A study folder's or Research/ notes in the same layout as Resources: by course, then by status.
struct NoteBrowserPage: View {
    @Environment(Store.self) private var store
    let title: String
    let folders: [String]

    /// The note's `course` property; failing that the longest Resources folder that starts the title, else General.
    static func course(_ n: Note, known: [String]) -> String {
        if !n.courseName.isEmpty { return n.courseName }
        if let k = known.filter({ n.title.hasPrefix($0) }).max(by: { $0.count < $1.count }) { return k }
        return Vault.courses.first { $0.value == n.course }?.key ?? "General"
    }
    static func kind(_ n: Note) -> String { n.status.isEmpty ? "Notes" : n.done ? "Done" : "To do" }
    static let kinds = ["To do", "Done", "Notes"]

    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses
        let all = store.notes.filter { folders.contains($0.folder) }
        CourseBrowser(title: title, courses: Set(all.map { Self.course($0, known: known) }).sorted(), noun: "notes", finder: Vault.root.appending(path: Vault.dir(folders[0]))) { course, query in
            let items = all.filter { Self.course($0, known: known) == course && (query.isEmpty || $0.display.localizedCaseInsensitiveContains(query)) }
            let groups = Dictionary(grouping: items, by: Self.kind)
            return Self.kinds.filter { groups[$0] != nil }.map { k in
                (k, "\(groups[k]!.count)",
                 groups[k]!.sorted { $0.title < $1.title }.map { Entry(id: $0.id, row: AnyView(NoteFileRow(note: $0))) })
            }
        }
    }
}

/// A note shown like a file in the course browser: same row as FileRow, opens the note.
struct NoteFileRow: View {
    @Environment(Store.self) private var store
    let note: Note
    var body: some View {
        Button { store.page = .note(note.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: note.done ? "checkmark.circle" : "doc.text").foregroundStyle(Color.ink2).frame(width: 20, height: 20)
                Text(note.display).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(note.status).font(.system(size: 11)).foregroundStyle(Color.ink2)
            }.font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6).contentShape(.rect)
        }.buttonStyle(.glassRow)
        .contextMenu { NoteMenu(note: note) }
    }
}

struct FileRow: View {
    @Environment(Store.self) private var store
    let item: FileBrowserPage.Item
    var body: some View {
        Button { store.openFile(item.url) } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 20, height: 20)
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.system(size: 11)).foregroundStyle(Color.ink2)
            }.font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6).contentShape(.rect)
        }.buttonStyle(.glassRow)
        .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
    }
}

/// Everything waiting in Unsorted, with the ways to add to it. Pressing an item opens it to file.
struct InboxPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        let items = store.unsorted
        VStack(spacing: 0) {
            PageHeader(title: "Unsorted", subtitle: items.isEmpty ? "All sorted" : "\(items.count) waiting") {
                HStack(spacing: 10) {
                    if !items.isEmpty { Button { store.page = .sortNow } label: { Label("Sort Now", systemImage: "sparkles") }.buttonStyle(.glassAction(.header)) }
                    RoundButton(icon: "square.and.pencil", label: "New note") { store.newNote() }
                    RoundButton(icon: "arrow.up.doc", label: "Add file") { store.addFile() }
                    RoundButton(icon: "link", label: "Add link") { store.addLink() }
                    RoundButton(icon: "mic", label: "Voice memo") { store.voiceMemo = true }
                    PageTools(title: "Unsorted", finder: Vault.root.appending(path: "Unsorted"))
                }
            }
            Card {
                if items.isEmpty { Label("All sorted", systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(items, id: \.self) { url in
                                let ext = url.pathExtension
                                Button { store.page = .unsorted(url) } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                                        Text(Vault.label(url)).lineLimit(1).truncationMode(.middle).foregroundStyle(ext == "txt" ? Color.redFG : Color.ink)
                                        Spacer()
                                        Text(ext == "md" ? "Note" : ext.uppercased()).font(.system(size: 11)).foregroundStyle(Color.ink2)
                                    }.font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6).contentShape(.rect)
                                }.buttonStyle(.glassRow).contextMenu { UnsortedMenu(url: url) }
                            }
                        }
                    }
                }
            }.padding([.horizontal, .bottom], 12)
        }
    }
}

/// Items pages (Lectures, Readings, Essays…): every note in one sortable table.
struct ItemsPage: View {
    @Environment(Store.self) private var store
    let title: String; let folders: [String]
    @State private var showAll = false
    @State private var course: String?   // nil = every course
    @State private var query = ""
    @State private var key = "Date"
    @State private var up = true
    static let columns = ["Title", "Course", "Date", "Status"]
    static func width(_ c: String) -> CGFloat { ["Title": .infinity, "Course": 230, "Date": 110, "Status": 100][c]! }

    func value(_ r: (note: Note, course: String)) -> String {
        switch key {
        case "Title": r.note.display.lowercased()
        case "Course": r.course.lowercased()
        case "Status": r.note.status
        default: r.note.when.map { String(format: "%015.0f", $0.timeIntervalSince1970) } ?? "~"
        }
    }

    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses, current = Set(Vault.courses.keys)
        let every = store.notes.filter { folders.contains($0.folder) }.map { (note: $0, course: NoteBrowserPage.course($0, known: known)) }
        let rows = every
            .filter { (showAll || current.contains($0.course)) && (course == nil || $0.course == course) && (query.isEmpty || $0.note.display.localizedCaseInsensitiveContains(query) || $0.course.localizedCaseInsensitiveContains(query)) }
            .sorted { up ? value($0) < value($1) : value($0) > value($1) }
        VStack(spacing: 0) {
            PageHeader(title: SideNav.label(title), subtitle: "\(rows.count) notes · \(rows.filter { !$0.note.done && !$0.note.status.isEmpty }.count) not done") {
                HStack(spacing: 10) {
                    Pills(options: [(false, "This semester"), (true, "All courses")], selection: Binding(get: { showAll }, set: { showAll = $0; course = nil }))
                    if showAll {   // every course the notes belong to, as a menu with All as the default
                        Menu {
                            Picker("Course", selection: $course) {
                                Text("All").tag(String?.none)
                                ForEach(Set(every.map(\.course)).sorted(), id: \.self) { Text($0).tag(String?.some($0)) }
                            }.pickerStyle(.inline)
                        } label: { Text(course ?? "All") }.menuStyle(.button).buttonStyle(.glassAction(.header)).fixedSize().help("Filter by course")
                    } else {   // this semester's three courses, as on Home
                        Pills(options: [(nil, "All")] + ["MSOA", "SM", "TEM"].compactMap { code in Vault.courses.first { $0.value == code }.map { (String?.some($0.key), code) } } as [(String?, String)], selection: $course)
                    }
                    PageTools(title: title, finder: Vault.root.appending(path: Vault.dir(folders[0])), seasonal: true)
                }
            }
            Card {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                    TextField("Filter notes", text: $query).textFieldStyle(.plain)
                }.font(.system(size: 13)).glassField().padding(.horizontal, 12).padding(.vertical, 10)
                if rows.isEmpty { Text("No notes").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 22, height: 1)
                        ForEach(Self.columns, id: \.self) { c in
                            Button { if key == c { up.toggle() } else { key = c; up = true } } label: {
                                HStack(spacing: 3) { Text(c); if key == c { Image(systemName: up ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) } }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).frame(maxWidth: Self.width(c), alignment: .leading)
                        }
                    }.font(.caption.weight(.semibold)).foregroundStyle(Color.ink2).padding(.horizontal, 14).padding(.vertical, 8)
                    Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1)
                    ScrollView { LazyVStack(spacing: 0) { ForEach(rows, id: \.note.id) { ItemRow(note: $0.note, course: $0.course) } } }
                }
            }.padding([.horizontal, .bottom], 12)
        }
        .onAppear { showAll = UserDefaults.standard.bool(forKey: "allDefault.\(title)") }
    }
}

private struct ItemRow: View {
    @Environment(Store.self) private var store
    let note: Note; let course: String
    var body: some View {
        HStack(spacing: 8) {
            StatusButton(note: note).frame(width: 22)
            Button { store.page = .note(note.id) } label: {
                HStack(spacing: 8) {
                    Text(note.display).lineLimit(1).truncationMode(.middle).foregroundStyle(note.done ? Color.ink2 : Color.ink).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) { Circle().fill(Color.course(note.course)).frame(width: 7, height: 7); Text(course).lineLimit(1) }.frame(maxWidth: ItemsPage.width("Course"), alignment: .leading)
                    Text(note.when.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "—").monospacedDigit().frame(maxWidth: ItemsPage.width("Date"), alignment: .leading)
                    Text(note.status.isEmpty ? "—" : note.status).frame(maxWidth: ItemsPage.width("Status"), alignment: .leading)
                }.font(.system(size: 12)).contentShape(.rect)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 14).padding(.vertical, 7).modifier(GlassRowHover())
        .contextMenu { NoteMenu(note: note) }
    }
}
