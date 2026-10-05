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
    private static func isEmpty(_ block: String) -> Bool {
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

    /// A chat message asking for it, in any agent's chat: the app does it itself (agents never edit existing notes from chat) and the answer comes back in that chat.
    func applyTemplates(_ folder: String, asked text: String, in code: String) {
        chats[code, default: []].append(Message(fromAgent: false, text: text))
        thinking.insert(code)
        Task { [weak self] in
            guard let self else { return }
            let reply = await bringToTemplate(folder)
            chats[code, default: []].append(Message(fromAgent: true, text: reply))
            thinking.remove(code)
        }
    }

    /// Brings every note in the folder to its template (see `TemplateApply`), logs it with an Undo, and says what happened.
    func bringToTemplate(_ folder: String) async -> String {
        let root = Vault.root, template = Sections.template(forFolder: folder, root: root)
        guard !template.isEmpty else { return "I couldn’t find a template for \(folder) in your vault, so nothing was changed." }
        let urls = notes.filter { $0.folder == folder }.map(\.id)
        guard !urls.isEmpty else { return "There are no \(folder) notes yet." }
        let outcome = await Task.detached(priority: .utility) { TemplateApply.run(urls, template: template, root: root) }.value
        var line = "Done on your Mac, without Claude: \(outcome.changed.count) of \(urls.count) \(folder) notes brought to their template (frontmatter in the template’s order, any missing sections added at the end). Nothing you wrote was changed or removed."
        if outcome.current > 0 { line += " \(outcome.current) already matched." }
        if !outcome.skipped.isEmpty { line += " \(outcome.skipped.count) skipped (changed in the last two minutes, or couldn’t be written): ask again in a moment." }
        guard !outcome.changed.isEmpty else { return line }
        let undo = InboxItem.Undo(restore: outcome.changed, snapshots: Dictionary(outcome.changed.compactMap { rel in
            Vault.history(root.appending(path: rel)).first.map { (rel, $0.url.lastPathComponent) }
        }, uniquingKeysWith: { a, _ in a }))
        var item = InboxItem(kind: .work, agent: Agent.manager.id, title: "Applied the \(folder) template to \(outcome.changed.count) notes", state: .done, key: "template:\(folder):\(UUID().uuidString)")
        item.undo = undo; item.verdict = "Automated change"
        inbox.append(item); saveInbox()
        log(Agent.manager.id, "Applied the \(folder) template to \(outcome.changed.count) notes.", undo: item.id)
        reload()
        return line + " Undo is in the Activity Log."
    }
}
