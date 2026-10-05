import Foundation
import CryptoKit

/// Two-way sync between the Zotero library and `Zotero/` in the vault, through Zotero's web API (the local API is read-only).
/// Zotero desktop syncs to the same cloud library, so both directions meet there.
/// Zotero → folder: a note per top-level item (metadata, tags, collections, Zotero notes) and its PDFs.
/// Folder → Zotero: a note's `tags:` and its `## My notes` section (one child note tagged `second-brain`), PDFs dropped in,
/// and notes without a `zotero:` key (they become items). Deletes never sync, either way. Every overwrite keeps the old text in `.history/`.
enum Zotero {
    static var dir: URL { Vault.root.appending(path: Vault.dir("Zotero")) }
    static let storage = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Zotero/storage")   // ponytail: Zotero's default data folder; read its pref if you move it
    static let layout = 4   // 2: `collections:` holds full folder paths
    static let marker = "second-brain", mineHeading = "## My notes"

    // MARK: Settings and state
    /// The API key is private, so it lives in the Keychain. The file in Application Support (owner-only) holds only the library's user id,
    /// so its presence says "connected" without reading the Keychain on every tick.
    struct Config {
        var key: String, user: String
        static let file = URL.applicationSupportDirectory.appending(path: "SecondBrain/zotero.json")
        static let account = "zotero-api-key"
        private struct Saved: Codable { var user: String; var key: String? }   // `key` is only in files written before it moved to the Keychain
        struct KeychainRefused: LocalizedError { var errorDescription: String? { "Couldn’t store the key in your Keychain, so Zotero isn’t connected." } }

        static var testing: Bool { ProcessInfo.processInfo.environment["ZOTERO_API_BASE"] != nil }   // Zotero's local API (read-only)
        static var connected: Bool { testing || FileManager.default.fileExists(atPath: file.path) }
        static func load() -> Config? {
            if testing { return Config(key: "local", user: "0") }
            guard let d = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: d) else { return nil }
            if let old = saved.key, !old.isEmpty {   // saved by an older version: move the key into the Keychain and out of the file
                let c = Config(key: old, user: saved.user)
                try? c.save()
                return c
            }
            return Keychain.read(account).map { Config(key: $0, user: saved.user) }
        }
        func save() throws {
            guard Keychain.save(key, for: Self.account) else { throw KeychainRefused() }
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(user: user, key: nil)).write(to: Self.file, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
        }
        static func forget() { try? FileManager.default.removeItem(at: file); Keychain.delete(account) }
    }

    /// What was last in sync, so a change on either side can be told apart. Lives beside the notes it describes; no secrets in it.
    struct State: Codable {
        struct Entry: Codable { var version: Int, tags: [String], mine: String, noteKey: String?, noteVersion: Int? }
        var version = 0
        var folders: [String]?   // every Zotero folder path, empty ones included (the page lists them)
        var layout: Int?   // which note layout was last written; a newer app rewrites the notes even if Zotero hasn't changed
        var items: [String: Entry] = [:]   // item key → what the note held when last synced
        var pdfs: [String: String] = [:]   // attachment key → PDF file in the folder
        static var file: URL { dir.appending(path: ".zotero-sync.json") }
        static func load() -> State { (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State() }
        func save() {
            guard let d = try? JSONEncoder().encode(self), (try? Data(contentsOf: Self.file)) != d else { return }
            try? d.write(to: Self.file, options: [.atomic])
        }
    }

    // MARK: Zotero's data
    struct Item: Decodable {
        let key: String, version: Int, data: Fields
        struct Fields: Decodable {
            var itemType: String
            var title: String?, date: String?, DOI: String?, url: String?, abstractNote: String?
            var publicationTitle: String?, bookTitle: String?, websiteTitle: String?
            var creators: [Creator]?, tags: [Tag]?, collections: [String]?
            var parentItem: String?, note: String?, filename: String?, contentType: String?, linkMode: String?
        }
        struct Creator: Decodable {
            var firstName: String?, lastName: String?, name: String?
            var full: String { name ?? [firstName, lastName].compactMap { $0 }.joined(separator: " ") }
        }
        struct Tag: Decodable { var tag: String }
    }
    struct Coll: Decodable {
        let key: String, data: Named
        struct Named: Decodable {
            let name: String, parent: String?, deleted: Bool   // folders in Zotero's Bin still come down, flagged
            enum Keys: String, CodingKey { case name, parentCollection, deleted }
            init(from d: Decoder) throws {   // parentCollection is a key, or `false` at the top
                let c = try d.container(keyedBy: Keys.self)
                name = try c.decode(String.self, forKey: .name); parent = try? c.decode(String.self, forKey: .parentCollection)
                deleted = (try? c.decode(Bool.self, forKey: .deleted)) ?? false
            }
        }
    }
    static let pathSeparator = " / "
    /// "Year 2 Essays / Busines Economics: Essay One / Part One" for each collection key. Folders in the Bin, and everything under them, are left out.
    static func collectionPaths(_ colls: [Coll]) -> [String: String] {
        let by = Dictionary(colls.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func binned(_ c: Coll, _ depth: Int) -> Bool { c.data.deleted || (depth < 12 && c.data.parent.flatMap { by[$0] }.map { binned($0, depth + 1) } == true) }
        func path(_ c: Coll, _ depth: Int) -> String {
            guard depth < 12, let p = c.data.parent, let up = by[p] else { return c.data.name }
            return path(up, depth + 1) + pathSeparator + c.data.name
        }
        return by.filter { !binned($0.value, 0) }.mapValues { path($0, 0) }
    }

    // MARK: Web API
    /// One element of a listing that may fail to decode on its own (an odd field in a single item) without taking the other 99 with it.
    struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    struct Failure: LocalizedError {
        let code: Int, message: String
        var errorDescription: String? {
            switch code {
            case 403: "Zotero refused it (the key can’t write, or storage is full)."
            case 413: "Zotero storage is full."
            case 429: "Zotero asked to slow down."
            default: "Zotero answered \(code)" + (message.isEmpty ? "" : ": \(message)")
            }
        }
    }

    struct API {
        let cfg: Config
        static var base: String { ProcessInfo.processInfo.environment["ZOTERO_API_BASE"] ?? "https://api.zotero.org" }

        /// A call on the user's library. 304 and 412 come back for the caller to act on; anything else ≥ 400 throws.
        func call(_ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil,
                  type: String = "application/json", headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
            guard var comps = URLComponents(string: Self.base + "/users/\(cfg.user)" + path) else { throw URLError(.badURL) }
            if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0, value: $1) } }
            guard let url = comps.url else { throw URLError(.badURL) }
            var req = URLRequest(url: url, timeoutInterval: 30); req.httpMethod = method; req.httpBody = body
            req.setValue(cfg.key, forHTTPHeaderField: "Zotero-API-Key"); req.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
            if body != nil { req.setValue(type, forHTTPHeaderField: "Content-Type") }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            for attempt in 0..<2 {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let r = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if r.statusCode == 429, attempt == 0 {
                    try await Task.sleep(for: .seconds(min(Double(r.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5, 30))); continue
                }
                if r.statusCode >= 400 && r.statusCode != 412 { throw Failure(code: r.statusCode, message: String(decoding: data.prefix(200), as: UTF8.self)) }
                return (data, r)
            }
            throw Failure(code: 429, message: "")
        }

        /// Every page of a listing, plus the library version. Nil when nothing changed since `since`.
        func list<T: Decodable>(_ path: String, _ type: T.Type, since: Int? = nil) async throws -> (rows: [T], version: Int)? {
            var out: [T] = [], start = 0, version = 0
            while true {
                let (d, r) = try await call("GET", path, query: [("format", "json"), ("limit", "100"), ("start", "\(start)")],
                                            headers: start == 0 ? since.map { ["If-Modified-Since-Version": "\($0)"] } ?? [:] : [:])
                if r.statusCode == 304 { return nil }
                if start == 0 { version = Int(r.value(forHTTPHeaderField: "Last-Modified-Version") ?? "") ?? 0 }
                let page = try JSONDecoder().decode([Lossy<T>].self, from: d)   // an item that doesn't decode is skipped, not fatal to the whole sync
                out += page.compactMap(\.value); start += page.count
                if page.isEmpty || start >= (Int(r.value(forHTTPHeaderField: "Total-Results") ?? "") ?? 0) { return (out, version) }
            }
        }

        static func json(_ x: Any) -> Data { (try? JSONSerialization.data(withJSONObject: x)) ?? Data() }
        static func form(_ kv: [(String, String)]) -> Data {
            Data(kv.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&").utf8)
        }

        /// Creates one item and returns its key and version.
        func create(_ fields: [String: Any]) async throws -> (key: String, version: Int) {
            struct Made: Decodable { struct Obj: Decodable { let key: String, version: Int }; struct Bad: Decodable { let message: String }; let successful: [String: Obj]; let failed: [String: Bad]? }
            let (d, _) = try await call("POST", "/items", body: Self.json([fields]), headers: ["Zotero-Write-Token": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()])
            let made = try JSONDecoder().decode(Made.self, from: d)
            guard let o = made.successful["0"] else { throw Failure(code: 400, message: made.failed?["0"]?.message ?? "rejected") }
            return (o.key, o.version)
        }

        /// Uploads a file to an existing attachment item (Zotero's authorise, upload, register steps).
        func upload(_ key: String, file: URL) async throws {
            let data = try Data(contentsOf: file)
            let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let mtime = Int(((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now).timeIntervalSince1970 * 1000)
            let urlencoded = "application/x-www-form-urlencoded"
            struct Slot: Decodable { var url: String?, contentType: String?, prefix: String?, suffix: String?, uploadKey: String?, exists: Int? }
            let (d, _) = try await call("POST", "/items/\(key)/file", body: Self.form([("md5", md5), ("filename", file.lastPathComponent), ("filesize", "\(data.count)"), ("mtime", "\(mtime)")]),
                                        type: urlencoded, headers: ["If-None-Match": "*"])
            let slot = try JSONDecoder().decode(Slot.self, from: d)
            if slot.exists == 1 { return }
            guard let u = slot.url.flatMap(URL.init), let ct = slot.contentType, let prefix = slot.prefix, let suffix = slot.suffix, let up = slot.uploadKey else { throw Failure(code: 502, message: "no upload slot") }
            var req = URLRequest(url: u); req.httpMethod = "POST"; req.setValue(ct, forHTTPHeaderField: "Content-Type")   // the file store, not Zotero: no key sent
            let (_, resp) = try await URLSession.shared.upload(for: req, from: Data(prefix.utf8) + data + Data(suffix.utf8))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw Failure(code: code, message: "upload failed") }
            _ = try await call("POST", "/items/\(key)/file", body: Self.form([("upload", up)]), type: urlencoded, headers: ["If-None-Match": "*"])
        }
    }

    /// Checks a pasted key and finds whose library it opens. It must be able to write.
    static func connect(_ key: String) async throws -> Config {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw Failure(code: 400, message: "That doesn’t look like an API key.") }
        guard let keyURL = URL(string: API.base + "/keys/\(key)") else { throw URLError(.badURL) }
        var req = URLRequest(url: keyURL, timeoutInterval: 30); req.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        let (d, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure(code: code, message: "Zotero didn’t accept that key.") }
        struct Info: Decodable { struct Access: Decodable { struct Lib: Decodable { let library: Bool?, write: Bool? }; let user: Lib? }; let userID: Int; let access: Access }
        let info = try JSONDecoder().decode(Info.self, from: d)
        guard info.access.user?.library == true, info.access.user?.write == true else { throw Failure(code: 400, message: "That key can’t edit your library. Make a new one with “Allow library access” and “Allow write access” ticked.") }
        return Config(key: key, user: "\(info.userID)")
    }

    // MARK: The sync
    struct Report {
        var from = 0, to = 0, pdfs = 0, held = 0, conflicts = 0
        var problems: [String] = []
        var changed: Bool { from + to + pdfs + held + conflicts + problems.count > 0 }
        var text: String {
            let parts = [from > 0 ? "\(from) note\(from == 1 ? "" : "s") updated from Zotero" : nil, to > 0 ? "\(to) change\(to == 1 ? "" : "s") sent to Zotero" : nil,
                         pdfs > 0 ? "\(pdfs) PDF\(pdfs == 1 ? "" : "s")" : nil, held > 0 ? "\(held) kept your unsent edits" : nil,
                         conflicts > 0 ? "\(conflicts) conflict\(conflicts == 1 ? "" : "s") (Zotero’s version kept, yours is in history)" : nil].compactMap { $0 }
            let more = problems.isEmpty ? "" : " Problems: " + problems.prefix(2).joined(separator: "; ") + (problems.count > 2 ? " …" : "")
            return "Synced" + (parts.isEmpty ? ", nothing new" : ": " + parts.joined(separator: ", ")) + "." + more
        }
    }

    /// Sends what changed in the folder, then reads what changed in Zotero.
    static func sync() async -> (text: String, changed: Bool) {
        guard let cfg = Config.load() else { return ("Not connected to Zotero.", false) }
        let api = API(cfg: cfg)
        var st = State.load(), r = Report()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let conflicted = try await push(api, &st, &r)
            try await pull(api, &st, &r, conflicted)
        } catch { st.save(); return ("Zotero sync failed: \(error.localizedDescription)", true) }
        st.save()
        return (r.text, r.changed)
    }

    /// A note you're still typing in is left alone for a minute.
    static func settled(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < .now.addingTimeInterval(-60)
    }

    // MARK: Folder → Zotero
    static func push(_ api: API, _ st: inout State, _ r: inout Report) async throws -> Set<String> {
        var conflicted = Set<String>(), texts: [String: String] = [:], keyOf: [String: String] = [:]
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for n in names where n.hasSuffix(".md") {
            guard let t = try? String(contentsOf: dir.appending(path: n), encoding: .utf8) else { continue }
            texts[n] = t; keyOf[n] = Vault.frontmatter(t)["zotero"]
        }
        for name in texts.keys.sorted() {
            guard let text = texts[name] else { continue }
            let url = dir.appending(path: name)
            do {
                if let key = keyOf[name] {
                    guard var e = st.items[key] else { continue }
                    defer { st.items[key] = e }
                    try await sendEdits(api, key, text, &e, &r, &conflicted)
                } else if settled(url) {
                    let (key, first) = try await newItem(api, name, text, &r)
                    var e = first
                    st.items[key] = e; keyOf[name] = key   // recorded before the note goes up, so a failure there is retried, not repeated
                    defer { st.items[key] = e }
                    try await sendEdits(api, key, (try? String(contentsOf: url, encoding: .utf8)) ?? text, &e, &r, &conflicted)
                }
            } catch let e as URLError { throw e } catch { r.problems.append("\(name): \(error.localizedDescription)") }
        }
        for n in names where n.lowercased().hasSuffix(".pdf") && !st.pdfs.values.contains(n) && settled(dir.appending(path: n)) {
            do {
                let base = String(n.dropLast(4))
                var f: [String: Any] = ["itemType": "attachment", "linkMode": "imported_file", "title": base, "contentType": "application/pdf", "filename": n]
                if let parent = keyOf[base + ".md"] { f["parentItem"] = parent }
                let made = try await api.create(f)
                do { try await api.upload(made.key, file: dir.appending(path: n)) }
                catch { _ = try? await api.call("DELETE", "/items/\(made.key)", headers: ["If-Unmodified-Since-Version": "\(made.version)"]); throw error }   // undo our own empty item
                st.pdfs[made.key] = n; r.pdfs += 1
            } catch let e as URLError { throw e } catch { r.problems.append("\(n): \(error.localizedDescription)") }
        }
        return conflicted
    }

    /// Tags and My notes: whatever differs from the last sync goes up.
    static func sendEdits(_ api: API, _ key: String, _ text: String, _ e: inout State.Entry, _ r: inout Report, _ conflicted: inout Set<String>) async throws {
        let tags = parseTags(text)
        if Set(tags) != Set(e.tags) {
            var version = e.version, send = tags
            for attempt in 0..<2 {
                let (_, resp) = try await api.call("PATCH", "/items/\(key)", body: API.json(["tags": send.map { ["tag": $0] }]), headers: ["If-Unmodified-Since-Version": "\(version)"])
                if resp.statusCode != 412 {
                    e.version = Int(resp.value(forHTTPHeaderField: "Last-Modified-Version") ?? "") ?? version; e.tags = tags; r.to += 1; break
                }
                guard attempt == 0 else { conflicted.insert(key); r.conflicts += 1; break }
                // Zotero's tags moved too: keep both sides' additions and removals.
                let (d, _) = try await api.call("GET", "/items/\(key)", query: [("format", "json")])
                let fresh = try JSONDecoder().decode(Item.self, from: d)
                let remote = Set(fresh.data.tags?.map(\.tag) ?? []), base = Set(e.tags), mine = Set(tags)
                send = remote.subtracting(base.subtracting(mine)).union(mine.subtracting(base)).sorted()
                version = fresh.version
            }
        }
        guard let mine = parseMine(text), mine != e.mine else { return }
        if let nk = e.noteKey, let nv = e.noteVersion {
            do {
                let (_, resp) = try await api.call("PATCH", "/items/\(nk)", body: API.json(["note": html(mine)]), headers: ["If-Unmodified-Since-Version": "\(nv)"])
                if resp.statusCode == 412 { conflicted.insert(key); r.conflicts += 1; return }
                e.noteVersion = Int(resp.value(forHTTPHeaderField: "Last-Modified-Version") ?? "") ?? nv; e.mine = mine; r.to += 1
            } catch let f as Failure where f.code == 404 { e.noteKey = nil; e.noteVersion = nil }   // deleted in Zotero: made again next time
        } else if !mine.isEmpty {
            let made = try await api.create(["itemType": "note", "parentItem": key, "note": html(mine), "tags": [["tag": marker]]])
            e.noteKey = made.key; e.noteVersion = made.version; e.mine = mine; r.to += 1
        } else { e.mine = mine }
    }

    /// A note with no `zotero:` key becomes a Zotero item, and the key is written into the note straight away so it can't be made twice.
    static func newItem(_ api: API, _ name: String, _ text: String, _ r: inout Report) async throws -> (String, State.Entry) {
        let fm = Vault.frontmatter(text), tags = parseTags(text), parts = Vault.split(text)
        var fields: [String: Any] = ["itemType": fm["url"] == nil ? "document" : "webpage", "title": fm["title"] ?? String(name.dropLast(3)), "tags": tags.map { ["tag": $0] }]
        if let u = fm["url"] { fields["url"] = u }
        let made = try await api.create(fields)
        var head = parts?.head ?? []
        head.removeAll { $0.hasPrefix("zotero:") }; head.insert("zotero: \(made.key)", at: 0)
        // Free text with no My notes heading is put under one, so it goes up as the item's note.
        let rest = parseMine(text) != nil ? (parts?.rest ?? "---\n\n" + text) : "---\n\n\(mineHeading)\n\n\(Vault.body(text))\n"
        try Vault.write(Vault.join(head, rest), to: dir.appending(path: name))
        r.to += 1
        return (made.key, State.Entry(version: made.version, tags: tags, mine: "", noteKey: nil, noteVersion: nil))
    }

    // MARK: Zotero → folder
    static func pull(_ api: API, _ st: inout State, _ r: inout Report, _ conflicted: Set<String>) async throws {
        guard let (all, version) = try await api.list("/items", Item.self, since: st.version > 0 && st.layout == layout ? st.version : nil) else { return }   // ponytail: refetches everything when the library moved; use ?since= if it grows past a few thousand items
        let collections = try await api.list("/collections", Coll.self)?.rows ?? []
        let collName = collectionPaths(collections)
        var fileOf: [String: String] = [:], taken = Set<String>()
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !n.hasPrefix(".") {
            taken.insert(n)
            if n.hasSuffix(".md"), let t = try? String(contentsOf: dir.appending(path: n), encoding: .utf8), let k = Vault.frontmatter(t)["zotero"] { fileOf[k] = n }
        }
        let kids = Dictionary(grouping: all.compactMap { it in it.data.parentItem.map { (parent: $0, item: it) } }, by: \.parent).mapValues { $0.map(\.item) }
        for it in all where it.data.parentItem == nil && !["attachment", "note", "annotation"].contains(it.data.itemType) {
            let name = fileOf[it.key] ?? fileName(it, taken: taken)
            taken.insert(name)
            let base = String(name.dropLast(3)), children = kids[it.key] ?? [], old = st.items[it.key]
            let mine = children.first { $0.data.itemType == "note" && ($0.key == old?.noteKey || $0.data.tags?.contains { $0.tag == marker } == true) }
            let others = children.filter { $0.data.itemType == "note" && $0.key != mine?.key }
            var pdfNames: [String] = [], links: [Item] = []
            for a in children where a.data.itemType == "attachment" {
                if a.data.contentType == "application/pdf", a.data.linkMode?.hasPrefix("imported") == true {
                    if let n = placePDF(a, base: base, st: &st, taken: &taken, r: &r) { pdfNames.append(n) }
                } else if a.data.linkMode == "linked_url", a.data.url != nil { links.append(a) }
            }
            let text = render(it, collections: collName, pdfs: pdfNames, links: links, others: others, mine: mine.map { md($0.data.note ?? "") } ?? "")
            let url = dir.appending(path: name), current = try? String(contentsOf: url, encoding: .utf8)
            do {
                if current != text {
                    if let c = current, let old, edited(c, since: old), !conflicted.contains(it.key) { r.held += 1; continue }   // yours hasn't gone up yet: don't overwrite it
                    try Vault.write(text, to: url); r.from += 1
                }
                st.items[it.key] = .init(version: it.version, tags: parseTags(text), mine: parseMine(text) ?? "", noteKey: mine?.key, noteVersion: mine?.version)
            } catch { r.problems.append("\(name): \(error.localizedDescription)") }
        }
        st.version = version; st.layout = layout; st.folders = Array(collName.values)
    }

    /// Copies a PDF out of Zotero's storage next to its note. Nil when it isn't on this Mac (yet).
    static func placePDF(_ a: Item, base: String, st: inout State, taken: inout Set<String>, r: inout Report) -> String? {
        var name = st.pdfs[a.key] ?? base + ".pdf", i = 2
        while st.pdfs[a.key] == nil && taken.contains(name) { name = "\(base) (\(i)).pdf"; i += 1 }
        let dest = dir.appending(path: name)
        if !FileManager.default.fileExists(atPath: dest.path) {
            guard let f = a.data.filename, (try? FileManager.default.copyItem(at: storage.appending(path: "\(a.key)/\(f)"), to: dest)) != nil else { return nil }
            r.pdfs += 1
        }
        taken.insert(name); st.pdfs[a.key] = name
        return name
    }

    static func fileName(_ it: Item, taken: Set<String>) -> String {
        let d = it.data, first = d.creators?.first.map { $0.lastName ?? $0.name ?? "" } ?? ""
        let head = [first, year(d.date) ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let raw = [head, (d.title ?? it.key).replacingOccurrences(of: "\n", with: " ")].filter { !$0.isEmpty }.joined(separator: " - ")
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|#^[]")   // not allowed in file names or in Obsidian links
        let clean = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !bad.contains($0) }))
        let base = String(clean.prefix(90)).trimmingCharacters(in: .whitespaces)
        return taken.contains(base + ".md") ? "\(base) (\(it.key)).md" : base + ".md"
    }
    static func year(_ s: String?) -> String? { s?.firstMatch(of: /\b(1[5-9]|20)\d\d\b/).map { String($0.output.0) } }

    // MARK: The note
    static func q(_ s: String) -> String {
        let e = JSONEncoder(); e.outputFormatting = .withoutEscapingSlashes
        return (try? e.encode(s)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }

    static func render(_ it: Item, collections: [String: String], pdfs: [String], links: [Item], others: [Item], mine: String) -> String {
        let d = it.data, title = (d.title ?? "Untitled").replacingOccurrences(of: "\n", with: " ")
        var head = ["zotero: \(it.key)", "type: \(d.itemType)", "title: \(q(title))"]
        func list(_ k: String, _ v: [String]) { if !v.isEmpty { head.append(k + ":"); head += v.map { "  - " + q($0) } } }
        list("authors", (d.creators ?? []).map(\.full).filter { !$0.isEmpty })
        if let y = year(d.date) { head.append("year: \(y)") }
        for (k, v) in [("publication", d.publicationTitle ?? d.bookTitle ?? d.websiteTitle), ("doi", d.DOI), ("url", d.url)] { if let v, !v.isEmpty { head.append("\(k): \(q(v))") } }
        list("collections", (d.collections ?? []).compactMap { collections[$0] }.sorted())
        head.append("tags:"); head += (d.tags ?? []).map(\.tag).sorted().map { "  - " + q($0) }
        var body = ["# \(title)", "", "[Open in Zotero](zotero://select/library/items/\(it.key))" + pdfs.map { " · [[\($0)]]" }.joined()]
        if let a = d.abstractNote, !a.isEmpty { body += ["", "## Abstract", "", a] }
        if !others.isEmpty { body += ["", "## Zotero notes", "", others.map { md($0.data.note ?? "") }.joined(separator: "\n\n---\n\n")] }
        let linked = links.compactMap { l in l.data.url.map { (title: l.data.title ?? $0, url: $0) } }
        if !linked.isEmpty { body += ["", "## Links", ""] + linked.map { "- [\($0.title)](\($0.url))" } }
        body += ["", mineHeading] + (mine.isEmpty ? [] : ["", mine])
        return "---\n" + head.joined(separator: "\n") + "\n---\n" + body.joined(separator: "\n") + "\n"
    }

    /// The tags in the note's frontmatter, sorted.
    static func parseTags(_ text: String) -> [String] {
        Vault.rawItems(text, "tags").map { raw in
            raw.hasPrefix("\"") ? ((try? JSONDecoder().decode(String.self, from: Data(raw.utf8))) ?? raw) : raw
        }.filter { !$0.isEmpty }.sorted()
    }
    /// Everything under `## My notes`. Nil when the heading is gone (then nothing is sent).
    static func parseMine(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        return lines.firstIndex(of: mineHeading).map { lines[($0 + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    static func edited(_ text: String, since e: State.Entry) -> Bool { Set(parseTags(text)) != Set(e.tags) || (parseMine(text) ?? "") != e.mine }

    /// Zotero notes are HTML. Paragraphs, lists, headings, bold and italic survive the trip; the rest is plain text.
    static func md(_ html: String) -> String {
        var s = html.replacing(/<h([1-6])[^>]*>/) { String(repeating: "#", count: Int($0.1) ?? 1) + " " }
        for (pattern, rep) in [("</(p|div|ul|ol|h[1-6]|blockquote)>", "\n\n"), ("</li>", "\n"), ("<br\\s*/?>", "\n"), ("<li[^>]*>", "- "),
                               ("</?(strong|b)>", "**"), ("</?(em|i)>", "*"), ("<[^>]+>", "")] {
            s = s.replacingOccurrences(of: pattern, with: rep, options: [.regularExpression, .caseInsensitive])
        }
        for (entity, ch) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { s = s.replacingOccurrences(of: entity, with: ch) }
        return s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func html(_ md: String) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        func inline(_ s: String) -> String { esc(s).replacing(/\*\*(.+?)\*\*/) { "<strong>\($0.1)</strong>" }.replacing(/\*(.+?)\*/) { "<em>\($0.1)</em>" } }
        var out: [String] = [], para: [String] = [], items: [String] = []
        func flush() {
            if !para.isEmpty { out.append("<p>" + para.map(inline).joined(separator: "<br>") + "</p>"); para = [] }
            if !items.isEmpty { out.append("<ul>" + items.map { "<li>" + inline($0) + "</li>" }.joined() + "</ul>"); items = [] }
        }
        for line in md.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush() }
            else if line.hasPrefix("- ") { if !para.isEmpty { flush() }; items.append(String(line.dropFirst(2))) }
            else if let h = line.wholeMatch(of: /(#{1,6}) (.+)/) { flush(); out.append("<h\(h.1.count)>\(inline(String(h.2)))</h\(h.1.count)>") }
            else { if !items.isEmpty { flush() }; para.append(line) }
        }
        flush()
        return out.joined()
    }

    // MARK: Self-check (called from `--check`; no network, nothing written)
    static func check() {
        for sample in ["# T\n\npara a\nline b\n\n- x\n- y", "one & two <b>\n\n**bold** and *italic*", "just a line"] {
            precondition(md(html(sample)) == sample, "note text survives a trip through Zotero’s HTML: \(sample)")
        }
        precondition(md("<div data-schema-version=\"9\"><p>Hi</p><p>there</p></div>") == "Hi\n\nthere", "Zotero’s own note markup reads as plain text")
        let json = #"{"key":"ABCD1234","version":7,"data":{"itemType":"journalArticle","title":"On \"Value\": a/b","date":"2021-03-04","creators":[{"firstName":"Ada","lastName":"Lovelace"}],"tags":[{"tag":"to: read"},{"tag":"econ"}],"collections":["C1"]}}"#
        let it = try! JSONDecoder().decode(Item.self, from: Data(json.utf8))
        let text = render(it, collections: ["C1": "Year 2"], pdfs: ["x.pdf"], links: [], others: [], mine: "my line")
        precondition(Vault.frontmatter(text)["zotero"] == "ABCD1234" && Vault.lists(text)["collections"] == ["Year 2"], "frontmatter reads back")
        precondition(parseTags(text) == ["econ", "to: read"], "tags with colons and spaces survive")
        precondition(parseMine(text) == "my line", "My notes reads back")
        let entry = State.Entry(version: 7, tags: parseTags(text), mine: "my line", noteKey: nil, noteVersion: nil)
        precondition(!edited(text, since: entry), "a fresh note is not an edit")
        precondition(edited(text.replacingOccurrences(of: "my line", with: "my line\nmore"), since: entry), "a change under My notes is an edit")
        precondition(edited(text.replacingOccurrences(of: "  - \"econ\"\n", with: ""), since: entry), "a removed tag is an edit")
        precondition(!edited(text.replacingOccurrences(of: "# On", with: "# Changed"), since: entry), "managed parts are not edits")
        precondition(fileName(it, taken: []) == "Lovelace 2021 - On Value ab.md" && fileName(it, taken: ["Lovelace 2021 - On Value ab.md"]).hasSuffix("(ABCD1234).md"), "file names are safe and unique")
        let colls = try! JSONDecoder().decode([Coll].self, from: Data(#"[{"key":"A","data":{"name":"Year 2 Essays","parentCollection":false}},{"key":"B","data":{"name":"Essay One","parentCollection":"A"}},{"key":"C","data":{"name":"Part One","parentCollection":"B"}},{"key":"D","data":{"name":"Old","parentCollection":false,"deleted":true}},{"key":"E","data":{"name":"Under old","parentCollection":"D"}}]"#.utf8))
        precondition(collectionPaths(colls)["C"] == "Year 2 Essays / Essay One / Part One" && collectionPaths(colls)["A"] == "Year 2 Essays", "folders keep their place in the tree")
        precondition(collectionPaths(colls)["D"] == nil && collectionPaths(colls)["E"] == nil, "folders in the Bin, and what is under them, are left out")
        print("zotero ok: notes round-trip, tags and My notes parse, edits are detected")
    }
}
