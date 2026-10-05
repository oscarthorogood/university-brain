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

    func runChecks() async {
        if jobOn("vaulthealth"), due("vaulthealth", every: 86400) { vaultHealth() }
        if jobOn("links"), due("links", every: 86400) { brokenLinks() }
        if jobOn("calendardrift"), due("calendardrift", every: 3600) { calendarDrift() }
        if jobOn("deadlines"), due("deadlines", every: 3600) { deadlineConsistency() }
        if jobOn("atrisk"), due("atrisk", every: 6 * 3600) { atRisk() }
        if jobOn("slides"), due("slides", every: 3600) { missingSlides() }
        if jobOn("quality"), due("quality", every: 86400) { qualitySweep() }
        if jobOn("status"), due("status", every: 86400) { statusHygiene() }
    }

    static let expectedBase: [String: String] = ["Courses": "Courses.base", "Lectures": "Lectures.base", "Tutorials": "Tutorials.base", "Readings": "Readings.base", "Essays": "Essays.base",
                                                 "Projects": "Projects.base", "Research": "Research.base"].merging(Study.folders.map { ($0, $0 + ".base") }) { a, _ in a }

    /// 15. Frontmatter against the templates, `base` links, naming, duplicates. Fixes an empty or wrong `base` (mechanical and safe); reports the rest.
    func vaultHealth() {
        var fixed = 0, issues: [String] = [], titles: [String: Int] = [:], fixedRels: [String] = []
        let statuses: Set<String> = Set(TaskState.allCases.map(\.rawValue)).union(["To Find"])
        for n in notes {
            titles[n.title.lowercased(), default: 0] += 1
            guard let base = Self.expectedBase[n.folder], let text = try? String(contentsOf: n.id, encoding: .utf8) else { continue }
            let fm = Vault.frontmatter(text)
            if Vault.unlink(fm["base"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) != base {
                if (try? Vault.write(Vault.setField(text, "base", to: "\"[[\(base)]]\""), to: n.id)) != nil { fixed += 1; fixedRels.append(Vault.rel(n.id)) } else { issues.append("\(n.title): `base`") }
            }
            if let s = fm["status"], !statuses.contains(s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))) { issues.append("\(n.title): status “\(s)”") }
            if n.course == nil, n.folder != "Courses", n.folder != "Readings", fm["course"] != nil || fm["Course"] != nil, Vault.courses.isEmpty == false, (fm["course"] ?? fm["Course"] ?? "").isEmpty { issues.append("\(n.title): no course") }
        }
        for (t, c) in titles where c > 1 { issues.append("duplicate title “\(t)”") }
        if fixed > 0 || !issues.isEmpty, once("health:\(dayStamp)") {
            let msg = "Vault health: " + (fixed > 0 ? "fixed \(fixed) `base` field\(fixed == 1 ? "" : "s"); " : "") + (issues.isEmpty ? "nothing else to report." : "\(issues.count) thing\(issues.count == 1 ? "" : "s") to look at (\(issues.prefix(3).joined(separator: "; "))).")
            if fixed > 0 {
                let undo = InboxItem.Undo(restore: fixedRels, snapshots: Dictionary(uniqueKeysWithValues: fixedRels.compactMap { rel in
                    Vault.history(Vault.root.appending(path: rel)).first.map { (rel, $0.url.lastPathComponent) }
                }))
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

    /// 16. Wikilinks and `resources` files that point at nothing.
    func brokenLinks() {
        let have = Set(notes.map { $0.title.lowercased() })
        let fileExt: Set<String> = ["pdf", "ppt", "pptx", "png", "jpg", "jpeg", "xlsx", "xls", "docx", "doc", "csv", "zip", "mp4", "mp3", "base", "txt", "json", "html"]
        var dead: [String] = [], missingFiles: [String] = []
        for n in notes {
            guard let text = try? String(contentsOf: n.id, encoding: .utf8) else { continue }
            for m in text.matches(of: /\[\[([^\]|#]+)/) {
                let t = String(m.1).trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.contains("/") || fileExt.contains((t as NSString).pathExtension.lowercased()) || have.contains(t.lowercased()) { continue }
                dead.append("\(n.title) → [[\(t)]]")
            }
            for raw in Vault.rawItems(text, "resources") {
                let path = Vault.unlink(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))).components(separatedBy: "|")[0]
                if fileExt.contains((path as NSString).pathExtension.lowercased()), !FileManager.default.fileExists(atPath: Vault.root.appending(path: Vault.real(path)).path) { missingFiles.append("\(n.title): \(path)") }
            }
        }
        if (!dead.isEmpty || !missingFiles.isEmpty), once("links:\(dayStamp)") {
            log(Agent.manager.id, "Links check: \(dead.count) link\(dead.count == 1 ? "" : "s") to notes that don't exist" + (dead.isEmpty ? "" : " (e.g. \(dead[0]))") + "; \(missingFiles.count) attached file\(missingFiles.count == 1 ? "" : "s") missing" + (missingFiles.isEmpty ? "" : " (e.g. \(missingFiles[0]))") + ".")
        }
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
            let undo = InboxItem.Undo(restore: driftRels, snapshots: Dictionary(uniqueKeysWithValues: driftRels.compactMap { rel in
                Vault.history(Vault.root.appending(path: rel)).first.map { (rel, $0.url.lastPathComponent) }
            }))
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
        let start = today, end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        for (code, name) in Vault.courses.map({ ($0.value, Agent.role($0.value).name) }).sorted(by: { $0.0 < $1.0 }) {
            let mine = notes.filter { $0.course == code && !$0.done && ($0.when.map { $0 >= start && $0 < end } ?? false) }
            func list(_ folders: Set<String>) -> String { mine.filter { folders.contains($0.folder) }.sorted { $0.when! < $1.when! }.map { "\($0.display) (\($0.when!.formatted(.dateTime.weekday(.abbreviated).hour().minute())))" }.joined(separator: ", ") }
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
        guard budgetLeft(deep: false) else { return }
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
