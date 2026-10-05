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
    @Environment(Store.self) private var store
    let root: String
    /// Also list notes and files that sit directly in the folder (not in a course folder), under the course they belong to.
    /// Summaries, Past Papers, Mind Maps and Research are filled with notes like that.
    var loose = false
    struct Item: Identifiable { let url: URL; let type: String; let size: Int; var id: URL { url } }

    var base: URL { Vault.root.appending(path: Vault.dir(root)) }
    /// The course folders inside this folder.
    var folders: [String] {
        ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !$0.lastPathComponent.hasPrefix(".") }
            .map(\.lastPathComponent).sorted()
    }
    var looseFiles: [URL] {
        guard loose else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isRegularFileKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasPrefix("Icon") }
    }
    /// A loose note belongs to the course in its `course` property, or whose name starts its title; anything else goes under General.
    func course(of url: URL) -> String {
        guard let n = store.notes.first(where: { $0.id == url }) else { return "General" }
        return NoteBrowserPage.course(n, known: FileBrowserPage(root: "Resources").courses)
    }
    var courses: [String] { Array(Set(folders).union(looseFiles.map { course(of: $0) })).sorted() }

    func files(_ course: String) -> [Item] {
        let dir = base.appending(path: course)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let all = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []
        let inFolder: [Item] = all.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, !u.lastPathComponent.hasPrefix("Icon") else { return nil }
            let rel = u.resolvingSymlinksInPath().path.replacingOccurrences(of: dir.resolvingSymlinksInPath().path + "/", with: "").components(separatedBy: "/")
            return Item(url: u, type: rel.count > 1 ? rel[0] : "Files", size: v.fileSize ?? 0)
        }
        let strays: [Item] = looseFiles.filter { self.course(of: $0) == course }.map {
            Item(url: $0, type: $0.pathExtension.lowercased() == "md" ? "Notes" : "Files", size: (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return inFolder + strays
    }

    var body: some View {
        let _ = store.revision          // look again when files change on disk
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
        let note = store.notes.first { $0.id == item.url }
        Button { store.openFile(item.url) } label: {
            HStack(spacing: 10) {
                Group {
                    if let note { Image(systemName: note.done ? "checkmark.circle" : "doc.text").foregroundStyle(Color.ink2) }
                    else { Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable() }
                }.frame(width: 20, height: 20)
                Text(note?.display ?? item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(note.map(\.status) ?? ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.system(size: 11)).foregroundStyle(Color.ink2)
            }.font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6).contentShape(.rect)
        }.buttonStyle(.glassRow)
        .contextMenu {
            if let note { NoteMenu(note: note) }
            else { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
        }
    }
}

extension Store {
    /// Everything in Unsorted as items, so Unsorted can be an Items page like Lectures. A file is an item whose course is what the Sorter
    /// would read from its name, whose date is when it was added, and whose status is its kind (Note, PDF…).
    var unsortedItems: [Note] {
        unsorted.map { url in
            let ext = url.pathExtension
            let code = Detect.fromName(url)
            return Note(id: url, folder: "Unsorted", title: Vault.label(url),
                        status: ext == "md" ? "Note" : (ext.isEmpty ? "File" : ext.uppercased()),
                        course: code, when: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                        path: Vault.rel(url).replacingOccurrences(of: ".md", with: ""),
                        courseName: code.flatMap { c in Vault.courses.first { $0.value == c }?.key } ?? "")
        }
    }
}

/// Items pages (Lectures, Readings, Essays…): every note as a card (gallery or grid) or one sortable table.
struct ItemsPage: View {
    @Environment(Store.self) private var store
    let title: String; let folders: [String]
    /// Unsorted is an Items page too, listing everything in the intake folder; it sits at the top of the sidebar instead of under Items.
    var inbox = false
    @AppStorage("viewMode") private var viewMode = ViewMode.gallery
    @State private var showAll = false
    @State private var course: String?   // nil = every course
    @State private var query = ""
    @State private var key = "Date"
    @State private var up = true
    static let columns = ["Title", "Course", "Date", "Status"]
    var columns: [String] { inbox ? ["Title", "Course", "Date", "Type"] : Self.columns }
    static func width(_ c: String) -> CGFloat { ["Title": .infinity, "Course": 230, "Date": 110, "Status": 100, "Type": 100][c]! }

    func value(_ r: (note: Note, course: String)) -> String {
        switch key {
        case "Title": r.note.display.lowercased()
        case "Course": r.course.lowercased()
        case "Status", "Type": r.note.status
        default: r.note.when.map { String(format: "%015.0f", $0.timeIntervalSince1970) } ?? "~"
        }
    }

    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses, current = Set(Vault.courses.keys)
        let source: [Note] = inbox ? store.unsortedItems : store.notes.filter { folders.contains($0.folder) }
        let every = source.map { (note: $0, course: NoteBrowserPage.course($0, known: known)) }
        let rows = every
            .filter { (showAll || inbox || current.contains($0.course)) && (course == nil || $0.course == course) && (query.isEmpty || $0.note.display.localizedCaseInsensitiveContains(query) || $0.course.localizedCaseInsensitiveContains(query)) }
            .sorted { up ? value($0) < value($1) : value($0) > value($1) }
        // The course filter: every course the notes belong to, or this semester's three (as on Home).
        let courseOptions: [(String, String)] = showAll || inbox
            ? Set(every.map(\.course)).sorted().map { ($0, $0) }
            : ["MSOA", "SM", "TEM"].compactMap { code in Vault.courses.first { $0.value == code }.map { ($0.key, code) } }
        VStack(spacing: 0) {
            PageHeader(title: SideNav.label(title), subtitle: "\(rows.count) notes · \(rows.filter { !$0.note.done && !$0.note.status.isEmpty }.count) not done", compact: true) {
                HStack(spacing: 10) {
                    if inbox, !every.isEmpty { Button { store.page = .sortNow } label: { Label("Sort Now", systemImage: "sparkles") }.buttonStyle(.glassAction(.header)) }
                    PageToolbar(title: title, finder: Vault.root.appending(path: Vault.dir(folders[0])), seasonal: !inbox, mode: $viewMode, query: $query,
                                sortKeys: columns, sortKey: $key, ascending: $up) {
                        if inbox {
                            Button("Add File…") { store.addFile() }
                            Button("Add Link…") { store.addLink() }
                            Button("Voice Memo…") { store.voiceMemo = true }
                            Divider()
                        } else {
                            Picker("Courses", selection: Binding(get: { showAll }, set: { showAll = $0; course = nil })) {
                                Text("This semester").tag(false); Text("All courses").tag(true)
                            }.pickerStyle(.inline)
                        }
                        Picker("Course", selection: $course) {
                            Text("All").tag(String?.none)
                            ForEach(courseOptions, id: \.0) { Text($0.1).tag(String?.some($0.0)) }
                        }.pickerStyle(.inline)
                    }
                }
            }
            if rows.isEmpty { Text(!inbox ? "No notes" : every.isEmpty ? "All sorted" : "No matches").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if viewMode != .list {
                NoteGallery(items: rows.map { r in
                    GalleryItem(id: r.note.id, title: r.note.display,
                                subtitle: inbox ? [r.note.status, r.course].joined(separator: " · ") : (r.note.when.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ""),
                                code: r.note.course, done: r.note.done,
                                open: { store.page = inbox ? .unsorted(r.note.id) : .note(r.note.id) },
                                menu: inbox ? AnyView(UnsortedMenu(url: r.note.id)) : AnyView(NoteMenu(note: r.note)))
                }, compact: viewMode == .grid)
            } else {
                Card {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 22, height: 1)
                        ForEach(columns, id: \.self) { c in
                            Button { if key == c { up.toggle() } else { key = c; up = true } } label: {
                                HStack(spacing: 3) { Text(c); if key == c { Image(systemName: up ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) } }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).frame(maxWidth: Self.width(c), alignment: .leading)
                        }
                    }.font(.caption.weight(.semibold)).foregroundStyle(Color.ink2).padding(.horizontal, 14).padding(.vertical, 8)
                    Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1)
                    ScrollView { LazyVStack(spacing: 0) { ForEach(rows, id: \.note.id) { ItemRow(note: $0.note, course: $0.course, inbox: inbox) } } }
                }.padding([.horizontal, .bottom], 12)
            }
        }
        .onAppear { showAll = UserDefaults.standard.bool(forKey: "allDefault.\(title)") }
    }
}

private struct ItemRow: View {
    @Environment(Store.self) private var store
    let note: Note; let course: String
    var inbox = false
    var body: some View {
        HStack(spacing: 8) {
            if inbox { Image(nsImage: NSWorkspace.shared.icon(forFile: note.id.path)).resizable().frame(width: 16, height: 16).frame(width: 22) }
            else { StatusButton(note: note).frame(width: 22) }
            Button { store.page = inbox ? .unsorted(note.id) : .note(note.id) } label: {
                HStack(spacing: 8) {
                    Text(note.display).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(inbox && note.id.pathExtension == "txt" ? Color.redFG : note.done ? Color.ink2 : Color.ink).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) { Circle().fill(Color.course(note.course)).frame(width: 7, height: 7); Text(course).lineLimit(1) }.frame(maxWidth: ItemsPage.width("Course"), alignment: .leading)
                    Text(note.when.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "—").monospacedDigit().frame(maxWidth: ItemsPage.width("Date"), alignment: .leading)
                    Text(note.status.isEmpty ? "—" : note.status).frame(maxWidth: ItemsPage.width(inbox ? "Type" : "Status"), alignment: .leading)
                }.font(.system(size: 12)).contentShape(.rect)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 14).padding(.vertical, 7).modifier(GlassRowHover())
        .contextMenu { if inbox { UnsortedMenu(url: note.id) } else { NoteMenu(note: note) } }
    }
}
