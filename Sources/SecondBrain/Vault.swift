import Foundation
import CryptoKit

struct Note: Identifiable, Hashable {
    let id: URL
    let folder: String
    let title: String
    let status: String
    let course: String?   // short code for current courses, nil otherwise
    let when: Date?       // `due` if set, else `date`
    let path: String      // vault-relative, without .md (for obsidian:// links)
    var unfilled = false  // still the template: no `summary`, or a course note with empty Key dates
    var courseName = ""   // the `course` property as written, e.g. "Globalisation and Trade" (any course, not just the current three)

    var done: Bool { status == "Done" }
}

enum Vault {
    /// Env var (for testing on a copy) → folder chosen in Settings → ~/Documents/University.
    static var root: URL {
        if let p = ProcessInfo.processInfo.environment["SECOND_BRAIN_VAULT"] { return URL(fileURLWithPath: p) }
        if let p = UserDefaults.standard.string(forKey: "vaultPath") { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents/University")
    }
    static var name: String { root.lastPathComponent }
    /// Vault-relative path (works whether or not the folder is reached through a symlink such as /tmp).
    static func rel(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path.replacingOccurrences(of: root.resolvingSymlinksInPath().path + "/", with: "")
    }
    static var exists: Bool { FileManager.default.fileExists(atPath: root.appending(path: "Lectures").path) }
    /// The vault groups its folders under Items/ (what you do), Files/ (documents and references) and Apps/ (study tools and research).
    /// The app still calls them by their short names ("Lectures", "Zotero"…); `dir` is where one really is.
    /// A vault laid out the old way (everything loose, Relations/ instead of Files/ and Apps/, or Summaries, Past Papers, Mind Maps and Research still in Apps/) keeps working, which the self-checks rely on.
    static let places: [String: String] = ["Lectures": "Items/Lectures", "Tutorials": "Items/Tutorials", "Readings": "Items/Readings", "Essays": "Items/Essays",
                         "Projects": "Items/Projects", "Exams": "Items/Exams", "TaskNotes/Tasks": "Items/Assignments",
                         "Research": "Files/Research", "Zotero": "Files/Zotero",
                         "Resources": "Files/Resources", "OneDrive": "Files/OneDrive"]
        .merging(Study.folders.map { ($0, (Study.inFiles.contains($0) ? "Files/" : "Apps/") + $0) }) { a, _ in a }
    static func dir(_ folder: String, root: URL = Vault.root) -> String {
        guard let p = places[folder] else { return folder }
        for candidate in [p, "Apps/" + folder, "Relations/" + folder] where FileManager.default.fileExists(atPath: root.appending(path: candidate).path) { return candidate }
        return folder
    }
    /// A vault path written with the short folder name ("Resources/TEM/x.pdf", as in note links) → the real one.
    static func real(_ rel: String, root: URL = Vault.root) -> String {
        for k in places.keys.sorted(by: { $0.count > $1.count }) where rel == k || rel.hasPrefix(k + "/") { return dir(k, root: root) + rel.dropFirst(k.count) }
        return rel
    }
    /// The short folder name for a real folder path ("Items/Lectures" → "Lectures").
    static func logical(_ folder: String) -> String {
        places.first { $0.value == folder }?.key
            ?? (folder.hasPrefix("Relations/") ? String(folder.dropFirst(10)) : folder.hasPrefix("Apps/") ? String(folder.dropFirst(5)) : folder)
    }
    static let folders = ["Courses", "Lectures", "Tutorials", "Readings", "Essays", "Projects"] + Study.folders + ["Research", "Exams", "TaskNotes/Tasks"]
    static let courses = ["Management Science and Operations Analytics": "MSOA",
                          "Strategic Management": "SM",
                          "The Entrepreneurial Manager": "TEM"]

    /// Names of every course we know of: the current three plus each folder in Resources/.
    static func courseNames() -> [String] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root.appending(path: dir("Resources")), includingPropertiesForKeys: nil)) ?? []
        return Array(Set(courses.keys).union(dirs.filter(\.hasDirectoryPath).map(\.lastPathComponent).filter { !$0.hasPrefix(".") }))
    }
    /// The longest course name that appears in `text` ("The Entrepreneurial Manager" also matches "Entrepreneurial Manager").
    static func inferCourse(_ text: String, in names: [String]) -> String? {
        names.filter { n in
            text.localizedCaseInsensitiveContains(n) || (n.hasPrefix("The ") && text.localizedCaseInsensitiveContains(String(n.dropFirst(4))))
        }.max { $0.count < $1.count }
    }

    static func load() -> [Note] {
        let fm = FileManager.default
        let names = courseNames()
        return folders.flatMap { folder -> [Note] in
            let dir = root.appending(path: Self.dir(folder, root: root))
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "md" }.compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let fm = frontmatter(text)
                let course = (fm["course"] ?? fm["Course"]).map(unlink).flatMap { courses[$0] }
                let title = url.deletingPathExtension().lastPathComponent
                return Note(id: url, folder: folder, title: title, status: fm["status"] ?? "",
                            course: course, when: parseDate(fm["due"]) ?? parseDate(fm["date"]),
                            path: "\(Self.dir(folder, root: root))/\(title)",
                            unfilled: folder == "Courses" ? text.contains("Add exam, essay, and project deadlines here")
                                                          : (fm["summary"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).isEmpty,
                            courseName: { let c = unlink(fm["course"] ?? fm["Course"] ?? "").trimmingCharacters(in: .whitespaces)
                                // Tasks carry no course property: take it from the title, then the body.
                                return c.isEmpty && folder == "TaskNotes/Tasks" ? (inferCourse(title, in: names) ?? inferCourse(text, in: names) ?? "") : c }())
            }
        }
    }

    /// Flat `key: value` pairs from the YAML block at the top. Lists and nested values are ignored.
    static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var out: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { out[key] = value }
        }
        return out
    }

    static func unlink(_ s: String) -> String {
        s.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }

    /// Called for every note on every load, so the formatters are made once. A configured DateFormatter is safe to read from any thread;
    /// these are never changed after they are made.
    private static let dateFormatters: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"].map { format in
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = format; return f
    }
    /// Week 1 of Semester 1, which the week numbers count from (the app's one hard-coded term date; see PLAN.md).
    /// Where each semester starts. Semester 2's start is a guess (mid-January); correct it here.
    static let semesters = [(name: "Semester 1", start: "2026-09-21"), (name: "Semester 2", start: "2027-01-18")]
    /// The semester it is now: the last one that has begun.
    static var currentSemesterIndex: Int { semesters.lastIndex { (parseDate($0.start) ?? .distantFuture) <= Calendar.current.startOfDay(for: .now) } ?? 0 }
    /// Week numbers count from here.
    static var currentSemesterStart: Date { parseDate(semesters[currentSemesterIndex].start) ?? .now }
    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        for f in dateFormatters { if let d = f.date(from: s) { return d } }
        return nil
    }

    /// How an Unsorted item is listed: a note by its first line (like Apple Notes), a file by its name.
    // ponytail: reads the file on each render; fine for a handful of tiny notes, cache in Store if Unsorted grows large
    static func label(_ url: URL) -> String {
        if url.pathExtension == "txt" { return "1 file needs review" }
        guard url.pathExtension == "md" else { return url.deletingPathExtension().lastPathComponent }
        let lines = body((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n")
            .map { $0.replacing(/^[>#\s]+/, with: "").replacing(/^\[!\w+\][+-]?\s*/, with: "").trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty } ?? "New Note"
    }

    static func unsorted() -> [URL] {
        let dir = root.appending(path: "Unsorted")
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "Icon\r" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func obsidianURL(_ note: Note) -> URL { obsidianURL(file: note.path) }
    /// `file` is vault-relative, without `.md`.
    static func obsidianURL(file: String) -> URL {
        var c = URLComponents()
        c.scheme = "obsidian"; c.host = "open"
        c.queryItems = [URLQueryItem(name: "vault", value: name), URLQueryItem(name: "file", value: file)]
        return c.url ?? URL(fileURLWithPath: root.path)   // a scheme, host and query always make a URL; the fallback only keeps this total
    }
}

extension Vault {
    /// Rewrites only the `status:` line inside the note's frontmatter.
    static func setStatus(_ note: Note, to status: String) throws {
        var text = try String(contentsOf: note.id, encoding: .utf8)
        guard text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return }
        let head = text[..<end.lowerBound]
        if let line = head.range(of: #"(?m)^status:.*$"#, options: .regularExpression) {
            text.replaceSubrange(line, with: "status: \(status)")
        } else {
            text.insert(contentsOf: "\nstatus: \(status)", at: end.lowerBound)
        }
        try write(text, to: note.id)
    }
}

extension Vault {
    struct Move: Hashable { let from: String; let to: String }

    /// `MOVE: a -> b` lines from an agent's plan.
    static func moves(in plan: String) -> [Move] {
        plan.split(separator: "\n").compactMap { line in
            guard let r = line.range(of: "MOVE:") else { return nil }
            let parts = line[r.upperBound...].components(separatedBy: "->").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " `*")) }
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty ? Move(from: parts[0], to: parts[1]) : nil
        }
    }

    /// SHA-256 of a file, read in 1 MB pieces so a large PDF or recording is never held in memory whole (and never twice). Nil when it can't be read.
    static func digest(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var sha = SHA256()
        do {
            while let piece = try handle.read(upToCount: 1 << 20), !piece.isEmpty { sha.update(data: piece) }
        } catch { return nil }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Files that are byte-for-byte copies of something already under Resources/ (size first, then SHA-256): [vault path: the Resources path it matches].
    static func duplicates(of files: [URL], in root: URL = Vault.root) -> [String: String] {
        let size = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        let sha = { (u: URL) in Vault.digest(u) }
        let wanted = Dictionary(grouping: files, by: size)
        var out: [String: String] = [:], cache: [URL: String] = [:]
        let base = root.appending(path: dir("Resources", root: root))
        for sub in (try? FileManager.default.subpathsOfDirectory(atPath: base.path)) ?? [] {
            let u = base.appending(path: sub)
            guard let same = wanted[size(u)], let h = sha(u) else { continue }
            for f in same where out[rel(f)] == nil {
                if cache[f] == nil { cache[f] = sha(f) }
                if cache[f] == h { out[rel(f)] = "Resources/" + sub }
            }
        }
        return out
    }

    /// An exact duplicate goes to .trash, never deleted. Returns where it went, so the move can be undone.
    static func trashDuplicate(_ from: String, in root: URL = Vault.root) throws -> String {
        let fm = FileManager.default, src = root.appending(path: from).standardizedFileURL
        guard src.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw MoveError.outside(from) }
        let trash = root.appending(path: ".trash/Unsorted-duplicate-" + Date.now.formatted(.iso8601.year().month().day()))
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        var bin = trash.appending(path: src.lastPathComponent)
        if fm.fileExists(atPath: bin.path) { bin = trash.appending(path: UUID().uuidString.prefix(6) + " " + src.lastPathComponent) }
        try fm.moveItem(at: src, to: bin)
        return rel(bin)
    }

    enum MoveError: LocalizedError {
        case outside(String), exists(String), mismatch(String)
        var errorDescription: String? {
            switch self {
            case .outside(let p): "“\(p)” is outside the vault, so it wasn’t moved."
            case .exists(let p): "“\(p)” already exists, so nothing was overwritten."
            case .mismatch(let p): "The copy of “\(p)” didn’t match the original, so the original was kept."
            }
        }
    }

    /// Copies, checks the copy is identical, then moves the original into .trash/. Never overwrites, never deletes.
    static func perform(_ m: Move, in root: URL = Vault.root) throws {
        let fm = FileManager.default
        let src = root.appending(path: real(m.from, root: root)).standardizedFileURL, dst = root.appending(path: real(m.to, root: root)).standardizedFileURL
        for u in [src, dst] where !u.path.hasPrefix(root.standardizedFileURL.path + "/") { throw MoveError.outside(u.path) }
        guard !fm.fileExists(atPath: dst.path) else { throw MoveError.exists(m.to) }
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
        guard let a = digest(src), a == digest(dst) else { try? fm.removeItem(at: dst); throw MoveError.mismatch(m.from) }
        let trash = root.appending(path: ".trash/Unsorted-filed-" + Date.now.formatted(.iso8601.year().month().day()))
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        var bin = trash.appending(path: src.lastPathComponent)
        if fm.fileExists(atPath: bin.path) { bin = trash.appending(path: UUID().uuidString.prefix(6) + " " + src.lastPathComponent) }
        try fm.moveItem(at: src, to: bin)
    }
}

extension Vault {
    /// List values in the frontmatter (`key:` followed by `  - item` lines), wikilinks unwrapped.
    static func lists(_ text: String) -> [String: [String]] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var out: [String: [String]] = [:]; var key: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if !line.hasPrefix(" "), let c = line.firstIndex(of: ":") { key = String(line[..<c]); continue }
            if let key, let dash = line.range(of: "- ") {
                var v = line[dash.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                v = unlink(v)
                if let bar = v.firstIndex(of: "|") { v = String(v[v.index(after: bar)...]) }
                if !v.isEmpty { out[key, default: []].append(v) }
            }
        }
        return out
    }

    /// The note text without its frontmatter.
    static func body(_ text: String) -> String {
        guard text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return text }
        return String(text[end.upperBound...]).trimmingCharacters(in: .newlines)
    }
}
