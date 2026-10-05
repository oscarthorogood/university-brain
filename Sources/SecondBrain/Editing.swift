import Foundation

/// Frontmatter edits and version history. Every write the app makes to an existing note goes through `Vault.write`,
/// which first keeps the old text in `.history/` so any edit can be undone.
extension Vault {
    // MARK: Frontmatter
    /// Splits a note into (frontmatter lines without the `---` fences, rest). Nil when there is no frontmatter.
    static func split(_ text: String) -> (head: [String], rest: String)? {
        guard text.hasPrefix("---\n") else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return nil }
        return (Array(lines[1..<end]), lines[end...].joined(separator: "\n"))
    }
    static func join(_ head: [String], _ rest: String) -> String { "---\n" + head.joined(separator: "\n") + "\n" + rest }

    /// Sets `key: value`, replacing the existing line (and any list under it) or adding one.
    static func setField(_ text: String, _ key: String, to value: String) -> String {
        guard var (head, rest) = split(text) else { return text }
        if let i = head.firstIndex(where: { $0.hasPrefix(key + ":") }) {
            var j = i + 1
            while j < head.count, head[j].hasPrefix(" ") || head[j].hasPrefix("\t") { j += 1 }
            head.replaceSubrange(i..<j, with: ["\(key): \(value)"])
        } else { head.append("\(key): \(value)") }
        return join(head, rest)
    }

    /// Raw list items under `key:` (as written, e.g. `"[[Note]]"`), changed by `edit`.
    static func editList(_ text: String, _ key: String, _ edit: (inout [String]) -> Void) -> String {
        guard var (head, rest) = split(text) else { return text }
        var items: [String] = [], at = head.count, end = head.count
        if let i = head.firstIndex(where: { $0.hasPrefix(key + ":") }) {
            var j = i + 1
            while j < head.count, head[j].hasPrefix(" ") || head[j].hasPrefix("\t") {
                if let d = head[j].range(of: "- ") { items.append(String(head[j][d.upperBound...])) }
                j += 1
            }
            at = i; end = j
        }
        edit(&items)
        head.replaceSubrange(at..<end, with: [key + ":"] + items.map { "  - " + $0 })
        return join(head, rest)
    }

    /// A list item as the app shows it: quotes and `[[ ]]` removed, alias kept.
    static func plain(_ raw: String) -> String {
        let v = unlink(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")))
        return v.firstIndex(of: "|").map { String(v[v.index(after: $0)...]) } ?? v
    }

    // MARK: History
    struct Version: Identifiable { let url: URL; let date: Date; var id: URL { url } }
    static func historyDir(_ note: URL, root: URL = Vault.root) -> URL {
        let rel = note.standardizedFileURL.path.replacingOccurrences(of: root.standardizedFileURL.path + "/", with: "")
        return root.appending(path: ".history/" + rel.replacingOccurrences(of: "/", with: "›"))
    }
    static func history(_ note: URL, root: URL = Vault.root) -> [Version] {
        let dir = historyDir(note, root: root)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.compactMap { u in (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate).map { Version(url: u, date: $0) } }
            .sorted { $0.date > $1.date }
    }

    /// Snapshot file names; made once because a job snapshots every note. Never changed after it is made, so safe on any thread.
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; return f
    }()
    /// Keeps the note's current text in `.history/` (unless it equals the newest snapshot), then prunes to the last 50.
    static func snapshot(_ note: URL, root: URL = Vault.root) throws {
        guard note.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),   // never snapshot outside the vault
              let old = try? String(contentsOf: note, encoding: .utf8) else { return }
        let fm = FileManager.default, dir = historyDir(note, root: root), last = history(note, root: root).first
        guard last.flatMap({ try? String(contentsOf: $0.url, encoding: .utf8) }) != old else { return }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try old.write(to: dir.appending(path: stampFormatter.string(from: .now) + ".md"), atomically: true, encoding: .utf8)
        for v in history(note, root: root).dropFirst(50) { try? fm.removeItem(at: v.url) }
    }

    /// Writes `text` to the note, keeping what was there before.
    static func write(_ text: String, to note: URL, root: URL = Vault.root) throws {
        if (try? String(contentsOf: note, encoding: .utf8)) != text { try snapshot(note, root: root) }
        try text.write(to: note, atomically: true, encoding: .utf8)
    }

    /// Raw list items under `key:` as written (for finding linked files).
    static func rawItems(_ text: String, _ key: String) -> [String] {
        var out: [String] = []
        _ = editList(text, key) { out = $0 }
        return out
    }

    static func checkEditing() {
        let t = "---\ntags:\n  - a\nstatus: Done\ndate: 2026-09-21T09:00\n---\nbody\n"
        precondition(setField(t, "status", to: "In Progress").contains("status: In Progress\ndate:"), "setField replaces")
        precondition(setField(t, "due", to: "2026-10-01").contains("date: 2026-09-21T09:00\ndue: 2026-10-01\n---\nbody"), "setField adds")
        precondition(editList(t, "tags") { $0.append("b") } == t.replacingOccurrences(of: "  - a\n", with: "  - a\n  - b\n"), "tag added")
        precondition(editList(t, "related") { $0 = ["\"[[X]]\""] }.contains("related:\n  - \"[[X]]\"\n---"), "list created")
        precondition(editList(t, "tags") { $0.removeAll() }.hasPrefix("---\ntags:\nstatus"), "list emptied")
        let box = FileManager.default.temporaryDirectory.appending(path: "sb-history-check")
        try? FileManager.default.removeItem(at: box)
        try! FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        let n = box.appending(path: "n.md")
        try! "one".write(to: n, atomically: true, encoding: .utf8)
        try! write("two", to: n, root: box); try! write("two", to: n, root: box); try! write("three", to: n, root: box)
        let h = history(n, root: box)
        precondition(h.count == 2 && (try! String(contentsOf: h[0].url, encoding: .utf8)) == "two" && (try! String(contentsOf: n, encoding: .utf8)) == "three", "history keeps previous text")
        print("editing ok: frontmatter setters touch only their key, history snapshots before writes")
    }
}
