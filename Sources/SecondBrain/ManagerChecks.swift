import Foundation

extension CalendarSync {
    struct Entry { let title: String; let segs: [String]; let day: Date; let dayStr: String; let time: String? }
    /// The open lines of Calendar Sync from today on.
    static func entries(root: URL = Vault.root, today: Date = Calendar.current.startOfDay(for: .now)) -> [Entry] {
        guard let doc = try? String(contentsOf: root.appending(path: file), encoding: .utf8) else { return [] }
        let section = doc.components(separatedBy: heading).last?.components(separatedBy: completed).first ?? ""
        return section.split(separator: "\n").compactMap { raw in
            guard raw.hasPrefix("- [ ]"), let m = raw.firstMatch(of: /^- \[ \] (?:<span[^>]*>■<\/span> )?(.*) 📅 (\d{4}-\d{2}-\d{2})/), let d = Vault.parseDate(String(m.2)), d >= today else { return nil }
            let text = String(m.1).replacingOccurrences(of: "&amp;", with: "&"), segs = text.components(separatedBy: " - ")
            return Entry(title: text, segs: segs, day: d, dayStr: String(m.2), time: segs.compactMap { $0.firstMatch(of: /^(\d{2}:\d{2})/)?.1 }.first.map(String.init))
        }
    }
}

/// The Manager's checks: they run on this Mac and cost nothing. A check fixes only what is mechanical and safe, and tells you about the rest in the Activity Log.
extension Store {
    private func due(_ id: String, every: TimeInterval) -> Bool {
        let k = "lastCheck-\(id)", last = UserDefaults.standard.double(forKey: k)
        guard Date.now.timeIntervalSince1970 - last > every else { return false }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: k)
        return true
    }
    /// True the first time it is asked about a key (so an alert isn't repeated).
    private func once(_ key: String) -> Bool { if handled.contains(key) { return false }; markHandled(key); return true }
    private var dayStamp: String { Date.now.formatted(.iso8601.year().month().day()) }

    /// Every note's text, read in the background.
    private func readAllNotes() async -> [URL: String] {
        let urls = notes.map(\.id)
        return await Task.detached(priority: .utility) {
            var out: [URL: String] = [:]
            for u in urls { if let t = try? String(contentsOf: u, encoding: .utf8) { out[u] = t } }
            return out
        }.value
    }

    func runChecks() async {
        let health = jobOn("vaulthealth") && due("vaulthealth", every: 86400), links = jobOn("links") && due("links", every: 86400)
        let texts = health || links ? await readAllNotes() : nil   // these two read every note, so they don't do it on the main thread
        if health { vaultHealth(texts: texts) }
        if links { brokenLinks(texts: texts) }
        if jobOn("calendardrift"), due("calendardrift", every: 3600) { calendarDrift() }
        if jobOn("deadlines"), due("deadlines", every: 3600) { deadlineConsistency() }
        if jobOn("atrisk"), due("atrisk", every: 6 * 3600) { atRisk() }
        if jobOn("slides"), due("slides", every: 3600) { missingSlides() }
        if jobOn("quality"), due("quality", every: 86400) { qualitySweep() }
        if jobOn("status"), due("status", every: 86400) { statusHygiene() }
        if jobOn("index"), due("index", every: 6 * 3600) { vaultIndex() }
        if jobOn("docs"), due("docs", every: 86400) { await docsDrift() }
        if jobOn("verifier"), due("verifier", every: 86400) { await runVerifier() }
    }

    static let expectedBase: [String: String] = ["Courses": "Courses.base", "Lectures": "Lectures.base", "Tutorials": "Tutorials.base", "Readings": "Readings.base", "Essays": "Essays.base",
                                                 "Projects": "Projects.base", "Research": "Research.base"].merging(Study.folders.map { ($0, $0 + ".base") }) { a, _ in a }

    /// 15. Frontmatter against the templates, `base` links, naming, duplicates. Fixes an empty or wrong `base` (mechanical and safe); reports the rest.
    func vaultHealth(texts: [URL: String]? = nil) {
        var fixed = 0, issues: [String] = [], titles: [String: Int] = [:], fixedRels: [String] = []
        let statuses: Set<String> = Set(TaskState.allCases.map(\.rawValue)).union(["To Find"])
        for n in notes {
            titles[n.title.lowercased(), default: 0] += 1
            guard let base = Self.expectedBase[n.folder], let text = texts?[n.id] ?? (try? String(contentsOf: n.id, encoding: .utf8)) else { continue }
            let fm = Vault.frontmatter(text)
            if Vault.unlink(fm["base"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) != base {
                let current = (try? String(contentsOf: n.id, encoding: .utf8)) ?? text   // read again just before writing, so an edit made while the check ran isn't overwritten
                if (try? Vault.write(Vault.setField(current, "base", to: "\"[[\(base)]]\""), to: n.id)) != nil { fixed += 1; fixedRels.append(Vault.rel(n.id)) } else { issues.append("\(n.title): `base`") }
            }
            if let s = fm["status"], !statuses.contains(s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))) { issues.append("\(n.title): status “\(s)”") }
            if n.course == nil, n.folder != "Courses", n.folder != "Readings", fm["course"] != nil || fm["Course"] != nil, Vault.courses.isEmpty == false, (fm["course"] ?? fm["Course"] ?? "").isEmpty { issues.append("\(n.title): no course") }
        }
        for (t, c) in titles where c > 1 { issues.append("duplicate title “\(t)”") }
        if fixed > 0 || !issues.isEmpty, once("health:\(dayStamp)") {
            let msg = "Vault health: " + (fixed > 0 ? "fixed \(fixed) `base` field\(fixed == 1 ? "" : "s"); " : "") + (issues.isEmpty ? "nothing else to report." : "\(issues.count) thing\(issues.count == 1 ? "" : "s") to look at (\(issues.prefix(3).joined(separator: "; "))).")
            if fixed > 0 {
                let undo = InboxItem.Undo(restore: fixedRels, snapshots: Dictionary(fixedRels.compactMap { rel in
                    Vault.history(Vault.root.appending(path: rel)).first.map { (rel, $0.url.lastPathComponent) }
                }, uniquingKeysWith: { a, _ in a }))
                var item = InboxItem(kind: .work, agent: Agent.manager.id, title: "Vault health: fixed \(fixed) base field\(fixed == 1 ? "" : "s")", state: .done, key: "health:\(dayStamp)")
                item.undo = undo; item.verdict = "Automated fix"
                inbox.append(item); saveInbox()
                log(Agent.manager.id, msg, undo: item.id)
            } else {
                log(Agent.manager.id, msg)
            }
        }
        if fixed > 0 { reload() }
    }

    /// Puts a fix the Manager made on its own in the Activity Log with an Undo: the notes it changed (as they were) and any it created.
    private func recordFix(title: String, key: String, message: String, changed: [String], created: [String] = []) {
        let undo = InboxItem.Undo(restore: changed, created: created, snapshots: Dictionary(changed.compactMap { rel in
            Vault.history(Vault.root.appending(path: rel)).first.map { (rel, $0.url.lastPathComponent) }
        }, uniquingKeysWith: { a, _ in a }))
        var item = InboxItem(kind: .work, agent: Agent.manager.id, title: title, state: .done, key: key)
        item.undo = undo; item.verdict = "Automated fix"
        inbox.append(item); saveInbox()
        log(Agent.manager.id, message, undo: item.id)
    }
    /// A note you touched in the last five minutes is left alone.
    private static func quiet(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < .now.addingTimeInterval(-300)
    }
    /// A link's name with the differences that don't matter taken out (case, spaces, punctuation, `L3` against `L03`), to find the note a mistyped link meant.
    static func linkKey(_ s: String) -> String {
        let padded = s.replacing(/\b([LT])(\d)\b/) { "\($0.1)0\($0.2)" }
        return String(padded.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    /// "Strategic Management L17 - Topic": the shape of a link to a lecture or tutorial that has no note yet.
    struct ClassLink { let link: String; let course: String; let kind: NoteKind; let number: Int; let topic: String }
    static func classLink(_ t: String) -> ClassLink? {
        guard let m = t.wholeMatch(of: /(.+) ([LT])(\d{1,3}) - (.+)/), Vault.courses.keys.contains(String(m.1)), let n = Int(m.3) else { return nil }
        return ClassLink(link: t, course: String(m.1), kind: m.2 == "L" ? .lecture : .tutorial, number: n, topic: String(m.4))
    }

    /// 16. Wikilinks and `resources` files that point at nothing. A mistyped link that can only mean one note is corrected, and the next lecture or tutorial in a
    /// course that something already links to is created from its template (fifteen a day at most); both can be undone. The rest is reported.
    func brokenLinks(texts: [URL: String]? = nil) {
        let have = Set(notes.map { $0.title.lowercased() })
        let fileExt: Set<String> = ["pdf", "ppt", "pptx", "png", "jpg", "jpeg", "xlsx", "xls", "docx", "doc", "csv", "zip", "mp4", "mp3", "base", "txt", "json", "html"]
        var byKey: [String: [String]] = [:]
        for n in notes { byKey[Self.linkKey(n.title), default: []].append(n.title) }
        var dead: [(note: Note, target: String)] = [], missingFiles: [String] = []
        for n in notes {
            guard let raw = texts?[n.id] ?? (try? String(contentsOf: n.id, encoding: .utf8)) else { continue }
            let text = raw.replacing(/```[\s\S]*?```/, with: "").replacing(/`[^`\n]*`/, with: "")   // a link shown inside code is an example, not a link
            for m in text.matches(of: /\[\[([^\]|#]+)/) {
                let t = String(m.1).trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.lowercased() == "course name" || t.contains("/") || fileExt.contains((t as NSString).pathExtension.lowercased()) || have.contains(t.lowercased()) { continue }
                dead.append((n, t))
            }
            for item in Vault.rawItems(raw, "resources") {
                let path = Vault.unlink(item.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))).components(separatedBy: "|")[0]
                if fileExt.contains((path as NSString).pathExtension.lowercased()), !FileManager.default.fileExists(atPath: Vault.root.appending(path: Vault.real(path)).path) { missingFiles.append("\(n.title): \(path)") }
            }
        }
        var fixes: [URL: [(wrong: String, right: String)]] = [:], future: [ClassLink] = [], left: [String] = [], seen = Set<String>()
        for (n, t) in dead {
            if let hit = byKey[Self.linkKey(t)], hit.count == 1 { fixes[n.id, default: []].append((t, hit[0])); continue }
            if let c = Self.classLink(t) { if seen.insert(t).inserted { future.append(c) }; continue }
            left.append("\(n.title) → [[\(t)]]")
        }
        // a mistyped link goes to the one note it can only mean
        var changed: [String] = [], mended = 0
        for (id, list) in fixes {
            guard Self.quiet(id), var text = try? String(contentsOf: id, encoding: .utf8) else { continue }
            var did = 0
            for (wrong, right) in list {
                for tail in ["]]", "|", "#"] where text.contains("[[" + wrong + tail) {
                    text = text.replacingOccurrences(of: "[[" + wrong + tail, with: "[[" + right + tail); did += 1
                }
            }
            if did > 0, (try? Vault.write(text, to: id)) != nil { changed.append(Vault.rel(id)); mended += did }
        }
        // every lecture or tutorial a link names that has no note (unless that number is already taken in its course): fifteen a day at most
        var made: [String] = [], taken: [String: Set<Int>] = [:]
        for c in future.sorted(by: { $0.number < $1.number }) where made.count < 15 {
            let key = c.course + "|" + c.kind.rawValue
            if taken[key] == nil {
                var numbers = Set<Int>()
                for n in notes where n.folder == c.kind.folder && n.courseName == c.course {
                    if let m = n.title.firstMatch(of: /\b[LT](\d{2,3})\s-\s/), let v = Int(m.1) { numbers.insert(v) }
                }
                taken[key] = numbers
            }
            guard taken[key]?.contains(c.number) == false, Self.linkKey(c.kind.title(course: c.course, number: c.number, topic: c.topic)) == Self.linkKey(c.link),
                  let url = try? Vault.create(c.kind, course: c.course, number: c.number, topic: c.topic, date: nil) else { continue }
            made.append(Vault.rel(url)); taken[key]?.insert(c.number)
        }
        if mended > 0 || !made.isEmpty {
            var parts: [String] = []
            if mended > 0 { parts.append("corrected \(mended) mistyped link\(mended == 1 ? "" : "s")") }
            if let first = made.first { parts.append("created \(made.count) note\(made.count == 1 ? "" : "s") that something already linked to (\((first as NSString).lastPathComponent))") }
            let what = parts.joined(separator: " and ")
            recordFix(title: "Links: " + what, key: "linkfix:\(dayStamp)", message: "Links check: \(what).", changed: changed, created: made)
            reload()
        }
        let waiting = future.count - made.count
        if (!left.isEmpty || waiting > 0 || !missingFiles.isEmpty), once("links:\(dayStamp)") {
            log(Agent.manager.id, "Links check: \(left.count) link\(left.count == 1 ? "" : "s") to notes that don't exist" + (left.isEmpty ? "" : " (e.g. \(left[0]))") + "; \(waiting) to later classes with no note yet; \(missingFiles.count) attached file\(missingFiles.count == 1 ? "" : "s") missing" + (missingFiles.isEmpty ? "" : " (e.g. \(missingFiles[0]))") + ".")
        }
    }

    /// 23. The counts in VAULT-INDEX.md follow the folders: only its Count column and "Counts verified" date are rewritten.
    func vaultIndex() {
        let url = Vault.root.appending(path: "Agents/Shared Agents/VAULT-INDEX.md")
        guard Self.quiet(url), let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var changes = 0
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let m = line.wholeMatch(of: /\| `([^`]+)\/` \| (.*) \| (\d+) \| (.*)/), !m.1.hasPrefix("Templates"),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: Vault.root.appending(path: String(m.1)).path) else { return line }
            let n = names.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.count
            guard String(n) != String(m.3) else { return line }
            changes += 1
            return "| `\(m.1)/` | \(m.2) | \(n) | \(m.4)"
        }
        guard changes > 0 else { return }
        let stamped = lines.joined(separator: "\n").replacing(/Counts verified \d{4}-\d{2}-\d{2}/) { _ in "Counts verified \(dayStamp)" }
        guard (try? Vault.write(stamped, to: url)) != nil else { return }
        recordFix(title: "Vault index: updated \(changes) count\(changes == 1 ? "" : "s")", key: "index:\(dayStamp)", message: "Vault index: updated \(changes) folder count\(changes == 1 ? "" : "s") in VAULT-INDEX.md to match the folders.", changed: [Vault.rel(url)])
    }

    /// 24. Paths the agents' instructions name that aren't in the vault (a folder that was dropped, a guide that was renamed). The Activity Log says so, and a helper corrects the
    /// mentions in the three instruction files (see `fixDocs`).
    func docsDrift() async {
        let root = Vault.root
        let missing: [String] = await Task.detached(priority: .utility) {
            var out: [String] = []
            for rel in ["Agents/Shared Agents/AGENTS.md", "Agents/Shared Agents/CLAUDE.md", "Agents/Shared Agents/VAULT-INDEX.md"] {
                guard let text = try? String(contentsOf: root.appending(path: rel), encoding: .utf8) else { continue }
                for m in text.matches(of: /`((?:Agents|Items|Files|Apps|Courses|Templates|Unsorted|TaskNotes|\.claudian)\/[^`\n{}|*<>]*)`/) {
                    let path = String(m.1)
                    if !FileManager.default.fileExists(atPath: root.appending(path: path).path), !out.contains(path) { out.append(path) }
                }
            }
            return out
        }.value
        if !missing.isEmpty, once("docs:\(dayStamp)") {
            log(Agent.manager.id, "Docs check: AGENTS.md, CLAUDE.md or the index name \(missing.count) path\(missing.count == 1 ? "" : "s") that aren't in the vault (\(missing.prefix(3).joined(separator: ", "))).")
            if jobOn("docsfix"), budgetLeft(deep: false) { await fixDocs(missing) }
        }
    }

    /// The three instruction files a docs fix may edit, and nothing else.
    private static let docFiles = ["Agents/Shared Agents/AGENTS.md", "Agents/Shared Agents/CLAUDE.md", "Agents/Shared Agents/VAULT-INDEX.md"]

    /// A helper (Haiku, once a day) corrects those mentions in the three files. It may write only to them; each is snapshotted first so the log can Undo it,
    /// and an edit that removes more than a fifth of a file is put back.
    private func fixDocs(_ missing: [String]) async {
        let root = Vault.root
        let urls = Self.docFiles.map { root.appending(path: $0) }
        var before: [URL: String] = [:]
        for u in urls { if let t = try? String(contentsOf: u, encoding: .utf8) { before[u] = t; try? Vault.snapshot(u) } }
        guard !before.isEmpty else { return }
        let prompt = """
        The vault's instruction files name paths that are not in the vault: \(missing.prefix(20).joined(separator: ", ")).
        Edit only AGENTS.md, CLAUDE.md and VAULT-INDEX.md in Agents/Shared Agents. For each path, correct the mention to what exists now (look at the folders), or remove that sentence or table row if the thing was dropped (tasks moved from TaskNotes/ to Items/Assignments/ on 2026-10-03). Change nothing else: no rule, no other wording, no counts.
        Reply with one short line per change.
        """
        let reply = await Agent.run(prompt, system: Agent.systemPrompt(Agent.role("planner")), session: nil, canEdit: false, root: root, tier: .quick, writes: Self.docFiles.map { Agent.scope(file: $0) })
        guard reply.session != nil else { return }
        var changed: [String] = []
        for u in urls {
            guard let old = before[u], let new = try? String(contentsOf: u, encoding: .utf8), new != old else { continue }
            if new.count < old.count * 8 / 10 {
                try? old.write(to: u, atomically: true, encoding: .utf8)
                log(Agent.manager.id, "Docs fix: put \(u.lastPathComponent) back, because the edit removed too much of it.")
                continue
            }
            changed.append(Vault.rel(u))
        }
        guard !changed.isEmpty else { return }
        recordFix(title: "Docs fix: corrected \(changed.count) instruction file\(changed.count == 1 ? "" : "s")", key: "docsfix:\(dayStamp)", message: "Docs fix: " + String(reply.text.prefix(240)), changed: changed)
    }

    /// 25. Runs the vault's own verifier (Agents/Shared Agents/verify-vault.py, read-only) and says so when it finds a rule broken.
    func runVerifier() async {
        let root = Vault.root, script = root.appending(path: "Agents/Shared Agents/verify-vault.py")
        // macOS's /usr/bin/python3 opens an install prompt when the developer tools are missing, so only a Python that is really there is used
        guard FileManager.default.fileExists(atPath: script.path),
              let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Developer/CommandLineTools/usr/bin/python3"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let result: (status: Int32, fails: [String])? = await Task.detached(priority: .utility) { () -> (status: Int32, fails: [String])? in
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: python); p.arguments = [script.path, root.path]
            p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()   // read before waiting, so a full pipe can't stall it
            p.waitUntilExit()
            let lines = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init).filter { $0.contains("FAIL") && !$0.contains("0 FAIL") }
            return (p.terminationStatus, lines)
        }.value
        guard let result, result.status != 0, once("verify:\(dayStamp)") else { return }
        log(Agent.manager.id, "Vault verifier: \(max(result.fails.count, 1)) rule\(result.fails.count == 1 ? "" : "s") broken" + (result.fails.isEmpty ? "." : " (e.g. \(result.fails[0].trimmingCharacters(in: .whitespaces).prefix(140))).") + " Run verify-vault.py for the full list.")
    }

    /// 17. A class's time on the calendar differs from its note: the note is corrected.
    func calendarDrift() {
        var changed = 0, driftRels: [String] = []
        for e in CalendarSync.entries() where e.segs.count > 1 && e.time != nil {
            let type = e.segs[1].split(separator: "/").first.map(String.init) ?? ""
            guard let kind = CalendarSync.classTypes[type], let course = Vault.courses.first(where: { e.segs[0] == $0.key })?.value,
                  let n = notes.first(where: { $0.folder == kind.folder && $0.course == course && $0.when.map { Calendar.current.isDate($0, inSameDayAs: e.day) } == true }),
                  let w = n.when, let t = e.time, Calendar.current.component(.hour, from: w) != 0 else { continue }
            let nowTime = w.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            guard nowTime != t, let text = try? String(contentsOf: n.id, encoding: .utf8) else { continue }
            if (try? Vault.write(Vault.setField(text, kind == .lecture ? "date" : "due", to: "\(e.dayStr)T\(t)"), to: n.id)) != nil {
                changed += 1; driftRels.append(Vault.rel(n.id))
                log(Agent.manager.id, "The calendar moved \(n.display) from \(nowTime) to \(t); I updated the note.")
            }
        }
        if changed > 0 {
            let undo = InboxItem.Undo(restore: driftRels, snapshots: Dictionary(driftRels.compactMap { rel in
                Vault.history(Vault.root.appending(path: rel)).first.map { (rel, $0.url.lastPathComponent) }
            }, uniquingKeysWith: { a, _ in a }))
            var item = InboxItem(kind: .work, agent: Agent.manager.id, title: "Calendar drift: corrected \(changed) note\(changed == 1 ? "" : "s")", state: .done, key: "drift:\(dayStamp)")
            item.undo = undo; item.verdict = "Automated fix"
            inbox.append(item); saveInbox()
            reload()
        }
    }

    /// 18. An essay, project or task's due date differs from the calendar's.
    func deadlineConsistency() {
        func words(_ t: String) -> Set<String> { Set(t.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 4 && !["submission", "group", "individual", "turnitin", "learn", "link", "strategic", "management", "entrepreneurial", "manager"].contains($0) }) }
        for e in CalendarSync.entries() where CalendarSync.deadlineWords.contains(where: e.title.lowercased().contains) && !CalendarSync.notDeadlines.contains(where: e.title.lowercased().contains) {
            let ew = words(e.title)
            guard let n = notes.first(where: { ["Essays", "Projects", "TaskNotes/Tasks"].contains($0.folder) && !$0.done && $0.when != nil && words($0.display).intersection(ew).count >= 2 }), let d = n.when,
                  !Calendar.current.isDate(d, inSameDayAs: e.day), abs(days(d) - days(e.day)) <= 14 else { continue }
            if once("deadline:\(n.path):\(e.dayStr)") {
                log("planner", "“\(n.display)” is due \(d.formatted(.dateTime.day().month(.abbreviated))) in its note but \(e.day.formatted(.dateTime.day().month(.abbreviated))) on the calendar (“\(e.title.prefix(60))”). Worth checking which is right.")
            }
        }
    }

    /// 19. Due within three days and not started, or overdue and open.
    func atRisk() {
        for n in notes where ["Essays", "Projects", "TaskNotes/Tasks"].contains(n.folder) && !n.done && n.state != .agent {
            guard let d = n.when else { continue }
            let left = days(d)
            let text: String
            if left < 0 && left >= -14 { text = "At risk: “\(n.display)” was due \(-left) day\(left == -1 ? "" : "s") ago and isn’t done." }
            else if (0...3).contains(left), n.state == .notStarted { text = "At risk: “\(n.display)” is due in \(left == 0 ? "less than a day" : "\(left) day\(left == 1 ? "" : "s")") and hasn’t been started." }
            else { continue }
            if once("risk:\(n.path):\(dayStamp)") { log(Agent.manager.id, text); if left <= 1 { Notify.post("Deadline at risk", text, id: "risk-" + n.path) } }
        }
    }

    /// 20. A class within a day with no slides linked: say where they might be.
    func missingSlides() {
        for n in notes where ["Lectures", "Tutorials"].contains(n.folder) && n.course != nil && !n.done {
            guard let w = n.when, w > .now, w < .now.addingTimeInterval(86400), let text = try? String(contentsOf: n.id, encoding: .utf8),
                  Vault.rawItems(text, "resources").allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }), once("slides:\(n.path)") else { continue }
            let waiting = unsorted.filter { ["pdf", "ppt", "pptx"].contains($0.pathExtension.lowercased()) }
            log(Agent.manager.id, "\(n.display) is \(whenText(w)) and has no slides linked." + (waiting.isEmpty ? " Nothing that looks like slides is waiting in Unsorted either." : " \(waiting.count) slide file\(waiting.count == 1 ? " is" : "s are") in Unsorted: the Sorter will file \(waiting.count == 1 ? "it" : "them")."))
        }
    }

    /// 21. Work a helper finished that still looks unfinished: the helper is allowed back on that note straight away.
    func qualitySweep() {
        for item in inbox where item.state == .done && item.kind == .work && item.created > .now.addingTimeInterval(-7 * 86400) && ["scribe", "librarian"].contains(item.agent) {
            guard let rel = item.paths.first, let n = notes.first(where: { Vault.rel($0.id) == rel }), ["Lectures", "Tutorials", "Readings"].contains(n.folder), n.unfilled, once("sweep:\(item.id)") else { continue }
            UserDefaults.standard.removeObject(forKey: "cool-\(item.agent)|\(n.path)")
            log(Agent.manager.id, "Quality sweep: “\(n.display)” still has no summary after \(Agent.role(item.agent).name)'s work, so it goes back to \(Agent.role(item.agent).name).")
        }
    }

    /// 22. Classes that have happened and are written up, but still say Not started.
    func statusHygiene() {
        var changed = 0
        for n in notes where ["Lectures", "Tutorials"].contains(n.folder) && n.course != nil && !n.unfilled && n.state == .notStarted {
            guard let w = n.when, w < today else { continue }
            if (try? Vault.setStatus(n, to: TaskState.done.rawValue)) != nil { changed += 1 }
        }
        if changed > 0 { log(Agent.manager.id, "Marked \(changed) written-up class\(changed == 1 ? "" : "es") Done."); reload() }
    }

    // MARK: The week ahead and the course briefings

    /// 13. Monday morning: what is on, due and to read, for each course, from plain facts.
    func weekAhead() async {
        guard jobOn("weekahead"), Calendar.current.component(.weekday, from: .now) == 2, Calendar.current.component(.hour, from: .now) >= 7 else { return }
        let key = "week:" + Date.now.formatted(.iso8601.year().weekOfYear())
        guard once(key) else { return }
        let start = today, end = start.addingTimeInterval(7 * 86400)
        for (code, name) in Vault.courses.map({ ($0.value, Agent.role($0.value).name) }).sorted(by: { $0.0 < $1.0 }) {
            let mine = notes.filter { $0.course == code && !$0.done && ($0.when.map { $0 >= start && $0 < end } ?? false) }
            func list(_ folders: Set<String>) -> String { mine.filter { folders.contains($0.folder) }.sorted { $0.whenOrFar < $1.whenOrFar }.map { "\($0.display) (\($0.whenOrFar.formatted(.dateTime.weekday(.abbreviated).hour().minute())))" }.joined(separator: ", ") }
            var parts: [String] = []
            let classes = list(["Lectures", "Tutorials"]), due = list(["Essays", "Projects", "TaskNotes/Tasks"]), reads = mine.filter { $0.folder == "Readings" }.count
            if !classes.isEmpty { parts.append("Classes: \(classes).") }
            if !due.isEmpty { parts.append("Due: \(due).") }
            if reads > 0 { parts.append("\(reads) reading\(reads == 1 ? "" : "s") due.") }
            log(code, "This week in \(name): " + (parts.isEmpty ? "nothing scheduled." : parts.joined(separator: " ")))
        }
    }

    /// Each course agent keeps a short briefing of where its course is, once a day, so a consult can read that instead of the whole course. Haiku; one a tick.
    func maintainBriefings(hasJobs: Bool) async {
        // a manual job may have started while this tick awaited; taking agentBusy here would clear it under that job when the briefing ends
        guard !agentBusy, budgetLeft(deep: false) else { return }
        for code in Agent.courseRoles.map(\.id) where agentOn(code) {
            let key = "briefing-\(code)-\(dayStamp)"
            guard !handled.contains(key) else { continue }
            markHandled(key)
            agentBusy = true; thinking.insert(code)
            defer { agentBusy = false; thinking.remove(code) }
            let r = await Agent.refreshBriefing(code, root: Vault.root)
            if r.limited { pauseForLimit() }
            return
        }
    }
}
