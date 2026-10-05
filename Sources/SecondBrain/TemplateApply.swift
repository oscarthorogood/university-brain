import Foundation

/// Brings existing notes to the structure of their template: the frontmatter keys in the template's order and spelling (`course` becomes `Course` where the template says so,
/// an empty `type` or `base` gets the template's value) and any section the template has that the note lacks, added at the end. Plain code on this Mac, no Claude:
/// nothing in the body is rewritten or removed, a key the template doesn't know is kept, and every note's old version goes to `.history/` first.
enum TemplateApply {
    struct Outcome: Sendable { var changed: [String] = [], skipped: [String] = [], current = 0 }   // vault paths; `current`: already matched

    /// The note brought to the template's structure, or nil when it already matches (or the template has no frontmatter to follow).
    static func apply(_ note: String, template: String) -> String? {
        let t = Sections.parse(template), n = Sections.parse(note)
        guard !t.front.isEmpty else { return nil }
        var used = Set<String>(), head: [String] = []
        for (key, block) in t.front {
            if let mine = n.front.first(where: { $0.key.lowercased() == key.lowercased() && !used.contains($0.key) }) {
                used.insert(mine.key)
                let ours = key + String(mine.block.dropFirst(mine.key.count))   // the note's lines, with the key spelled as the template spells it
                head += (isEmpty(ours) && !isEmpty(block) ? block : ours).components(separatedBy: "\n")
            } else {
                head += block.components(separatedBy: "\n")
            }
        }
        for (key, block) in n.front where !used.contains(key) { head += block.components(separatedBy: "\n") }   // keys the template doesn't know stay
        var out: String
        if let parts = Vault.split(note) { out = Vault.join(head, parts.rest) } else { out = "---\n" + head.joined(separator: "\n") + "\n---\n\n" + note }
        let have = Set(n.sections.map { Sections.normal($0.title) })
        let missing = t.sections.filter { !$0.title.isEmpty && !have.contains(Sections.normal($0.title)) }
        if !missing.isEmpty {
            out = out.trimmingCharacters(in: .newlines) + "\n"
            for s in missing {
                let body = s.body.trimmingCharacters(in: .newlines)
                out += "\n## \(s.title)\n" + (body.isEmpty ? "" : "\n" + body + "\n")
            }
        }
        return out == note ? nil : out
    }

    /// A key with nothing after it: no value on its line and no list item with anything in it.
    static func isEmpty(_ block: String) -> Bool {
        let lines = block.components(separatedBy: "\n")
        let value = lines[0].drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
        let items = lines.dropFirst().map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t-")) }
        return value.isEmpty && items.allSatisfy(\.isEmpty)
    }

    /// Applies it to each note, skipping any changed in the last two minutes (you may be typing in it). Reads and writes files, so it runs off the main thread.
    nonisolated static func run(_ urls: [URL], template: String, root: URL) -> Outcome {
        var out = Outcome()
        for url in urls {
            let rel = Vault.rel(url)
            if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d > .now.addingTimeInterval(-120) { out.skipped.append(rel); continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { out.skipped.append(rel); continue }
            guard let new = apply(text, template: template) else { out.current += 1; continue }
            if (try? Vault.write(new, to: url, root: root)) != nil { out.changed.append(rel) } else { out.skipped.append(rel) }
        }
        return out
    }

    static func check() {
        let template = "---\ntags:\nbase: \"[[MCQ.base]]\"\nCourse:\ndate:\ntype: MCQ Test\nstatus:\nrelated:\n  - \n---\n\n## 🎯 Focus\n\n> [!abstract] Focus\n\n## ❓ Questions\n\n## 📊 Results\n\n> [!note] Attempts\n> | Date | Score |\n"
        let note = "---\ntags:\n  - mcq\ncourse: \"[[X]]\"\ntype:\nextra: keep\nstatus: Done\n---\n\n## ❓ Questions\n\n1. Q?\n   - A. a\n"
        guard let done = apply(note, template: template) else { fatalError("template apply: a note out of shape changes") }
        precondition(done.contains("Course: \"[[X]]\"") && !done.contains("\ncourse:"), "a key takes the template's spelling and keeps its value")
        precondition(done.contains("type: MCQ Test") && done.contains("base: \"[[MCQ.base]]\"") && done.contains("status: Done") && done.contains("extra: keep"), "empty keys get the template's value, others and unknown keys stay")
        precondition(done.contains("## 🎯 Focus") && done.contains("## 📊 Results") && done.contains("1. Q?\n   - A. a"), "missing sections are added and the body is untouched")
        precondition(done.range(of: "tags:")!.lowerBound < done.range(of: "base:")!.lowerBound && done.range(of: "base:")!.lowerBound < done.range(of: "Course:")!.lowerBound, "keys follow the template's order")
        precondition(apply(done, template: template) == nil, "applying twice changes nothing")
        print("template apply ok: keys in the template's order, missing sections added, text untouched, idempotent")
    }
}

extension Store {
    /// "apply the MCQ template to the existing MCQ files": the folder it names, or nil when the message isn't such a request.
    nonisolated static func templateRequest(_ text: String) -> String? {
        let t = text.lowercased()
        guard t.contains("template"), ["apply", "update", "bring", "convert", "migrate", "match", "reformat"].contains(where: t.contains) else { return nil }
        let kinds: [(String, String)] = [(#"\bmcqs?\b"#, "MCQ"), (#"\bflash ?cards?\b"#, "Flashcards"), (#"\bglossar(y|ies)\b"#, "Glossary"), (#"\bpodcasts?\b"#, "Podcast"),
                                         (#"\bpast papers?\b"#, "Past Papers"), (#"\bsummar(y|ies)\b"#, "Summaries"), (#"\bmind ?maps?\b"#, "Mind Maps"), (#"\blectures?\b"#, "Lectures"),
                                         (#"\btutorials?\b"#, "Tutorials"), (#"\bessays?\b"#, "Essays"), (#"\bprojects?\b"#, "Projects"), (#"\breadings?\b"#, "Readings"),
                                         (#"\bresearch\b"#, "Research"), (#"\bexams?\b"#, "Exams")]
        return kinds.first { t.range(of: $0.0, options: .regularExpression) != nil }?.1
    }

    /// Which helper owns a kind of note (its template is the one it fills), when the chat that asked isn't with one.
    nonisolated static func templateOwner(_ folder: String) -> String {
        ["Lectures": "scribe", "Tutorials": "scribe", "Readings": "librarian", "Research": "researcher", "Essays": "writer", "Projects": "writer", "Exams": "planner"][folder] ?? "tutor"
    }

    /// A chat message asking for it, in any agent's chat. The agent does the editing, a few notes at a time, with write access to just those notes (chat agents otherwise never edit
    /// an existing note). The Manager then checks every note against what it was, puts back any that lost text or changed a value, and tidies what is still off the template.
    func applyTemplates(_ folder: String, asked text: String, in code: String) {
        chats[code, default: []].append(Message(fromAgent: false, text: text))
        thinking.insert(code)
        chatTasks[code] = Task { [weak self] in
            guard let self else { return }
            defer { chatTasks[code] = nil }
            let helper = Agent.role(code).course == nil && code != Agent.manager.id ? code : Self.templateOwner(folder)
            let reply = await agentApplyTemplates(folder, by: helper, shownIn: code)
            streaming[code] = nil
            chats[code, default: []].append(Message(fromAgent: true, text: reply))
            thinking.remove(code)
        }
    }

    func agentApplyTemplates(_ folder: String, by helper: String, shownIn code: String) async -> String {
        let root = Vault.root, template = Sections.template(forFolder: folder, root: root)
        let name = Sections.templateName(forFolder: folder) + " Template"
        guard !template.isEmpty else { return "I couldn’t find the \(name) in your vault, so nothing was changed." }
        let templateRel = Vault.rel(Vault.template(name, root: root))
        let urls = notes.filter { $0.folder == folder && $0.state != .agent }.map(\.id)
        guard !urls.isEmpty else { return "There are no \(folder) notes to change." }
        // what each note is now, and a snapshot of it first, so every one can be checked and put back
        let start = await Task.detached(priority: .utility) { () -> (texts: [String: String], snaps: [String: String]) in
            var texts: [String: String] = [:], snaps: [String: String] = [:]
            for u in urls {
                let rel = Vault.rel(u)
                guard let t = try? String(contentsOf: u, encoding: .utf8) else { continue }
                texts[rel] = t
                try? Vault.snapshot(u, root: root)
                if let s = Vault.history(u, root: root).first { snaps[rel] = s.url.lastPathComponent }
            }
            return (texts, snaps)
        }.value
        let rels = urls.map { Vault.rel($0) }.filter { start.texts[$0] != nil }
        var failures: [String] = [], stopped = false
        let size = 4
        for from in stride(from: 0, to: rels.count, by: size) {
            let batch = Array(rels[from..<min(from + size, rels.count)])
            streaming[code] = "Notes \(from + 1)–\(from + batch.count) of \(rels.count)…"
            let prompt = """
            Bring these \(batch.count) existing \(folder) notes to their template. Read the template first: `\(templateRel)`. For each note:
            - Frontmatter: the same keys in the template's order and spelling (where the template writes `Course` and the note has `course`, rename the key and keep the value). Keep every value. If `type`, `base` or `status` is empty and the template gives a value, use the template's. A key the template doesn't have stays, after the template's keys.
            - Body: keep every existing line exactly as it is, in its place. Add any section (`## heading`) the template has and the note lacks, at the end, with the template's own scaffolding. Never rewrite, move, merge or delete existing text, and never edit any file except the notes listed.
            Notes:
            \(batch.map { "- `\($0)`" }.joined(separator: "\n"))
            Reply with one short line per note: changed, or already matched.
            """
            let r = await Agent.run(prompt, system: Agent.templatePrompt(helper), session: nil, canEdit: false, root: root, tier: Manager.workTier(helper), writes: batch.map { Agent.scope(file: $0) },
                                    onText: { [weak self] text in Task { @MainActor in if let self, self.thinking.contains(code) { self.streaming[code] = "Notes \(from + 1)–\(from + batch.count) of \(rels.count)\n\n" + text } } })
            if r.stopped { stopped = true; break }
            if r.session == nil { failures.append(r.text); if r.limited { pauseForLimit(); break } }
        }
        // the Manager's check of what the agent did, and the tidy-up of whatever is still off the template
        let wasStopped = stopped   // a copy: the checking below runs off the main thread
        let result = await Task.detached(priority: .utility) { () -> (kept: [String], reverted: [String], tidied: Int, matched: Int) in
            var kept: [String] = [], reverted: [String] = [], tidied = 0, matched = 0
            for rel in rels {
                let url = root.appending(path: rel)
                guard let old = start.texts[rel], var now = try? String(contentsOf: url, encoding: .utf8) else { continue }
                var touched = false
                if now != old {
                    let v = Review.checkEdit(rel: rel, before: old, after: now, sections: nil, template: template, restructure: true)
                    if v.ok { touched = true } else { try? Vault.write(old, to: url, root: root); now = old; reverted.append((rel as NSString).lastPathComponent + ": " + (v.problems.first ?? "changed text")) }
                }
                if !wasStopped, let fixed = TemplateApply.apply(now, template: template), (try? Vault.write(fixed, to: url, root: root)) != nil { touched = true; tidied += 1 }
                if touched { kept.append(rel) } else if now == old { matched += 1 }
            }
            return (kept, reverted, tidied, matched)
        }.value
        var line = "\(stopped ? "Stopped. " : "")\(helper == "tutor" ? "" : Agent.role(helper).name + " ")Brought \(result.kept.count) of \(rels.count) \(folder) notes to their template (frontmatter in the template’s order, missing sections added at the end)."
        if result.matched > 0 { line += " \(result.matched) already matched." }
        if result.tidied > 0 { line += " The Manager finished \(result.tidied) the agent had left." }
        if !result.reverted.isEmpty { line += " \(result.reverted.count) put back because the check found a problem: " + result.reverted.prefix(3).joined(separator: "; ") + "." }
        if !failures.isEmpty { line += " Some notes weren’t reached: \(failures[0].prefix(120))" }
        guard !result.kept.isEmpty else { return line }
        let undo = InboxItem.Undo(restore: result.kept, snapshots: Dictionary(result.kept.compactMap { rel in start.snaps[rel].map { (rel, $0) } }, uniquingKeysWith: { a, _ in a }))
        var item = InboxItem(kind: .work, agent: helper, title: "Applied the \(folder) template to \(result.kept.count) notes", state: .done, key: "template:\(folder):\(UUID().uuidString)")
        item.undo = undo; item.verdict = "Checked: no text lost"
        inbox.append(item); saveInbox()
        log(helper, "Applied the \(folder) template to \(result.kept.count) notes.", undo: item.id)
        reload()
        return line + " Undo is in the Activity Log."
    }
}
