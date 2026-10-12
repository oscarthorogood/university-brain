import SwiftUI
import AppKit

/// Right-click (two-finger click) menus, like Finder and Notes.
struct NoteMenu: View {
    @Environment(Store.self) private var store
    let note: Note
    var body: some View {
        Button("Open") { store.page = .note(note.id) }
        Button("Open in New Tab") { store.newTab(.note(note.id)) }
        Button("Open in Obsidian") { NSWorkspace.shared.open(Vault.obsidianURL(note)) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.id]) }
        Divider()
        Menu("Status") { ForEach(TaskState.allCases, id: \.self) { s in Button { store.set(note, s) } label: { Label(s.label, systemImage: note.state == s ? "checkmark" : s.icon) } } }
        Button("Ask the Manager About It") {
            store.page = .agent(Agent.manager.id)
            store.ask("Tell me what matters in “\(note.display)” (\(note.id.lastPathComponent)) and what I should do next.")
        }
    }
}

struct UnsortedMenu: View {
    @Environment(Store.self) private var store
    let url: URL
    var body: some View {
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Divider()
        Button("Rename…") { store.rename(url) }
        Button("Move to Trash") { store.trash(url) }
    }
}

struct CourseMenu: View {
    @Environment(Store.self) private var store
    let code: String
    var body: some View {
        Button("Open") { store.page = .course(code) }
        Button("New Note…") { store.newCourse = Vault.courses.first { $0.value == code }?.key; store.newStructured = true }
        Button("Ask What’s Due") { store.page = .agent(Agent.manager.id); store.ask("What’s due for \(code) in the next two weeks?") }
    }
}

struct FolderMenu: View {
    @Environment(Store.self) private var store
    let name: String
    var body: some View {
        Button("Open") { store.page = .folder(name) }
        if let kind = NoteKind.allCases.first(where: { $0.folder == (name == "Tasks" ? "TaskNotes/Tasks" : name) }) {
            Button("New \(kind.rawValue)…") { store.newKind = kind; store.newStructured = true }
        }
        Button("Show in Finder") { NSWorkspace.shared.open(Vault.root.appending(path: Vault.dir(name == "Tasks" ? "TaskNotes/Tasks" : name))) }
    }
}

extension Store {
    func rename(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let dest = url.deletingLastPathComponent().appending(path: name)
        guard !name.isEmpty, name != url.lastPathComponent else { return }
        if FileManager.default.fileExists(atPath: dest.path) { error = "“\(name)” already exists."; return }
        do { try FileManager.default.moveItem(at: url, to: dest); if page == .unsorted(url) { page = .unsorted(dest) }; reload() }
        catch { self.error = error.localizedDescription }
    }
    /// Agents and the app never delete: "trash" is a move into the vault's .trash/.
    func trash(_ url: URL) {
        let fm = FileManager.default
        let dir = Vault.root.appending(path: ".trash/Unsorted-removed-" + Date.now.formatted(.iso8601.year().month().day()))
        var dest = dir.appending(path: url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { dest = dir.appending(path: UUID().uuidString.prefix(6) + " " + url.lastPathComponent) }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.moveItem(at: url, to: dest)
            if case .unsorted = page { page = .inbox }
            reload()
        } catch { self.error = error.localizedDescription }
    }
}
