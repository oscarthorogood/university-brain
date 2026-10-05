import Foundation

/// Turns what the calendar sync wrote into the notes the app actually shows: a Lecture or Tutorial note for every class from today on
/// (numbered after the ones already there) and a Task for each assignment deadline that no Essay or Project already covers.
/// Plain file work, no agent, so it happens on every sync. Anything made is remembered in `.calendar-notes.txt`
/// (Obsidian ignores dot-files), so a note you delete or rename is never made again.
extension CalendarSync {
    static let classTypes = ["Lecture": NoteKind.lecture, "Tutorial": .tutorial, "Seminar": .tutorial, "Workshop": .tutorial, "Computer Workshop": .tutorial, "Q&A Session": .tutorial]
    static let deadlineWords = ["submission", "hand in", "deadline", "turnitin", "oral presentation", "peer review"]
    static let notDeadlines = ["extension", "extra-time", "learn submission", "start of", "register", "welcome"]
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Creates the missing notes and returns their vault paths.
    @discardableResult
    static func makeNotes(root: URL = Vault.root, today: Date = Calendar.current.startOfDay(for: .now)) -> [String] {
        guard let doc = try? String(contentsOf: root.appending(path: file), encoding: .utf8) else { return [] }
        let fm = FileManager.default
        func files(_ folder: String) -> [(name: String, f: [String: String])] {
            ((try? fm.contentsOfDirectory(at: root.appending(path: Vault.dir(folder, root: root)), includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "md" }
                .map { ($0.deletingPathExtension().lastPathComponent, Vault.frontmatter((try? String(contentsOf: $0, encoding: .utf8)) ?? "")) }
        }
        func course(_ f: [String: String]) -> String { Vault.unlink(f["course"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        func day(_ f: [String: String]) -> String { String((f["date"] ?? f["due"] ?? "").prefix(10)) }
        var sessions = ["Lectures": files("Lectures"), "Tutorials": files("Tutorials")]
        let handIns = (files("Essays") + files("Projects")).map { day($0.f) }, tasks = files("TaskNotes/Tasks")
        func words(_ t: String) -> Set<String> { Set(t.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 4 && !["submission", "group", "individual", "entrepreneurial", "manager", "strategic", "management", "science", "operations", "analytics"].contains($0) }) }
        let ledgerURL = root.appending(path: ".calendar-notes.txt")
        var made = Set((try? String(contentsOf: ledgerURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? [])
        var created: [String] = [], newKeys: [String] = []

        let section = doc.components(separatedBy: heading).last?.components(separatedBy: completed).first ?? ""
        for raw in section.split(separator: "\n") where raw.hasPrefix("- [ ]") {
            guard let m = raw.firstMatch(of: /^- \[ \] (?:<span[^>]*>■<\/span> )?(.*) 📅 (\d{4}-\d{2}-\d{2})/), let date = Vault.parseDate(String(m.2)), date >= today else { continue }
            let text = String(m.1).replacingOccurrences(of: "&amp;", with: "&"), dayStr = String(m.2)
            let segs = text.components(separatedBy: " - ")
            let time = segs.compactMap { $0.firstMatch(of: /^(\d{2}:\d{2})/)?.1 }.first.map(String.init)
            let start = Vault.parseDate(time.map { "\(dayStr)T\($0)" } ?? dayStr)

            if let name = Vault.courses.keys.first(where: { segs[0] == $0 }), segs.count > 1,
               let type = segs[1].split(separator: "/").first.map(String.init), let kind = classTypes[type] {
                let key = [name, dayStr, type, time ?? ""].joined(separator: "|"), folder = kind.folder
                guard !made.contains(key), !(sessions[folder] ?? []).contains(where: { course($0.f) == name && day($0.f) == dayStr }) else { continue }
                let mine = (sessions[folder] ?? []).filter { $0.name.hasPrefix(name + " ") }
                let letter = kind == .lecture ? "L" : "T"
                let number = (mine.compactMap { n -> Int? in n.name.hasPrefix(name + " " + letter) ? Int(n.name.dropFirst(name.count + 2).prefix { $0.isNumber }) : nil }.max() ?? 0) + 1
                let seen = mine.filter { $0.name.contains(type) }.count
                let topic = kind == .lecture ? "Lecture \(number)" : (seen > 0 || ["Seminar", "Tutorial"].contains(type) ? "\(type) \(seen + 1)" : type)
                guard (try? Vault.create(kind, course: name, number: number, topic: topic, date: start, root: root)) != nil else { continue }
                sessions[folder, default: []].append((kind.title(course: name, number: number, topic: topic), ["course": "\"[[\(name)]]\"", "date": String(dayStr)]))
                created.append("\(Vault.dir(folder, root: root))/\(kind.title(course: name, number: number, topic: topic)).md"); newKeys.append(key)
                continue
            }

            let lower = text.lowercased()
            guard deadlineWords.contains(where: lower.contains), !notDeadlines.contains(where: lower.contains), !handIns.contains(dayStr) else { continue }
            let head = segs.prefix { !weekdays.contains($0) }.joined(separator: " - ")
            let title = head.replacingOccurrences(of: #"\s*-?\s*(Turnitin|TURNITIN|LEARN)?\s*Submission [Ll]ink\s*"#, with: " submission", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
            let key = "task|\(title)|\(dayStr)"
            guard !title.isEmpty, !tasks.contains(where: { words($0.name).intersection(words(title)).count >= 2 })   // already a task for this, under its own wording
                , !made.contains(key), (try? Vault.create(.task, course: "", number: 0, topic: title, date: start, root: root)) != nil else { continue }
            created.append("\(Vault.dir("TaskNotes/Tasks", root: root))/\(NoteKind.task.title(course: "", number: 0, topic: title)).md"); newKeys.append(key)
        }
        if !newKeys.isEmpty {
            made.formUnion(newKeys)
            try? made.sorted().joined(separator: "\n").appending("\n").write(to: ledgerURL, atomically: true, encoding: .utf8)
        }
        return created
    }

    static func checkNotes() {
        let box = FileManager.default.temporaryDirectory.appending(path: "sb-cal-notes-check")
        try? FileManager.default.removeItem(at: box)
        let fm = FileManager.default
        for d in ["Templates/Claude", "Lectures", "Tutorials", "Essays", "Projects", "TaskNotes/Tasks", (file as NSString).deletingLastPathComponent] { try! fm.createDirectory(at: box.appending(path: d), withIntermediateDirectories: true) }
        for (n, k) in [("Lecture", "Lecture No."), ("Tutorial", "Tutorial No.")] {
            try! "---\ncourse: \"[[]]\"\n\(k):\nstatus: Not started\ndue:\ndate:\n---\n\n## Body\n".write(to: box.appending(path: "Templates/Claude/\(n) Template.md"), atomically: true, encoding: .utf8)
        }
        try! "---\ncourse: \"[[Strategic Management]]\"\nLecture No.: 5\ndate: 2026-10-12T15:10\n---\n".write(to: box.appending(path: "Lectures/Strategic Management L05 - Lecture 5.md"), atomically: true, encoding: .utf8)
        try! "---\ncourse: \"[[Strategic Management]]\"\ndue: 2026-12-18\n---\n".write(to: box.appending(path: "Essays/Strategic Management - Essay - Individual Report.md"), atomically: true, encoding: .utf8)
        let sw = #"<span class="calendar-importer-swatch" style="color:#64748b">■</span> "#
        let lines = [
            "Strategic Management - Lecture/01 - Monday - 15:10-16:00 - Business School 📅 2026-10-12",   // already has a note
            "Strategic Management - Lecture/01 - Monday - 15:10-16:00 - Business School 📅 2026-10-19",
            "Strategic Management - Seminar/01 - Monday - 16:10-17:00 - Business School 📅 2026-10-19",
            "Management Science and Operations Analytics - Q&amp;A Session - Friday - 14:10-15:00 📅 2026-10-23",
            "Management Science and Operations Analytics - Lecture - Monday - 09:00-09:50 📅 2026-09-21",   // in the past
            "Individual Assignment - Turnitin Submission Link - Tuesday - 14:00 📅 2026-12-08",
            "Individual Report - TURNITIN Submission Link  - Friday - 14:00 📅 2026-12-18",                  // the essay covers it
            "Individual Assignment - 4-day extension Turnitin submission link - Saturday - 14:00 📅 2026-12-12",
            "Please register to attend - Intro to the Award - Wednesday - 13:30-15:00 📅 2026-10-07"]
        try! (heading + "\n\n" + lines.map { "- [ ] " + sw + $0 }.joined(separator: "\n") + "\n\n" + completed + "\n").write(to: box.appending(path: file), atomically: true, encoding: .utf8)
        let today = Vault.parseDate("2026-10-01")!
        let made = makeNotes(root: box, today: today).sorted()
        precondition(made == ["Lectures/Strategic Management L06 - Lecture 6.md", "TaskNotes/Tasks/Individual Assignment submission.md",
                              "Tutorials/Management Science and Operations Analytics T01 - Q&A Session.md", "Tutorials/Strategic Management T01 - Seminar 1.md"], "made \(made)")
        precondition(try! String(contentsOf: box.appending(path: made[0]), encoding: .utf8).contains("date: 2026-10-19T15:10"), "lecture date")
        try! fm.removeItem(at: box.appending(path: made[0]))
        precondition(makeNotes(root: box, today: today).isEmpty, "a deleted note is not made again")
        print("calendar notes ok: classes numbered on, deadlines become tasks, no duplicates")
    }
}
