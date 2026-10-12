import Foundation

/// There is one agent, so one instruction file (`Agent.instructions`, shipped with the app and replaced with each new version, with a `## Mode: …` section for each
/// kind of work) and one file of learned rules (`Agent.learned`, which lives in the vault and is never replaced). Before that, each agent had a file of its own.
/// This folds a vault's old files in: the rules they had learned from Oscar's edits move to the learned-rules file, and the old files go to `.trash/`.
enum AgentFiles {
    /// The old files, one per kind of work and one per course, and the heading a file's learned rules go under.
    static var old: [(rel: String, heading: String)] {
        var out: [(rel: String, heading: String)] = []
        for r in Agent.roles { out.append((rel: "Agents/Helper Agents/\(r.name)/\(r.name) agent.md", heading: r.name)) }
        for c in Agent.courses { out.append((rel: "Agents/Course Agents/\(c.name)/\(c.name) course agent.md", heading: c.name)) }
        return out
    }
    static let learnedHeader = """
    # Learned rules

    What the Manager has learned from Oscar's edits to what it wrote: one `## <Mode>` section for each kind of work (Sorter, Scribe, Librarian, Planner, Tutor, Writer, Researcher, Analyst, Manager). The app adds rules here when Oscar consistently changes what it wrote. Read the section for the kind of work you are doing and follow it. This file stays in the vault when the app updates.

    """
    private static let learnedHeading = "## Learned from Oscar's edits"

    /// The rules under `## Learned from Oscar's edits` in an old agent file: its list lines, none of the "Nothing yet" placeholder.
    static func learnedRules(in text: String) -> [String] {
        var inside = false, out: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { inside = line.trimmingCharacters(in: .whitespaces).hasPrefix(learnedHeading); continue }
            guard inside else { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if (t.hasPrefix("- ") || t.hasPrefix("* ") || t.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil), !t.localizedCaseInsensitiveContains("nothing yet") { out.append(t) }
        }
        return out
    }

    /// `rule` as a list line under `## <heading>` (the heading is added at the end if it is missing), replacing the "Nothing yet." placeholder. A rule already there is not added twice.
    static func insertRule(into text: String, rule: String, heading: String) -> String {
        let line = "- " + rule
        var lines = text.components(separatedBy: "\n")
        guard let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## " + heading }) else {
            return text.trimmingCharacters(in: .newlines) + "\n\n## \(heading)\n\n\(line)\n"
        }
        if lines.contains(line) { return text }
        let end = lines[(h + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
        var body = lines[(h + 1)..<end].filter { $0.trimmingCharacters(in: .whitespaces).lowercased() != "nothing yet." }
        while let last = body.last, last.trimmingCharacters(in: .whitespaces).isEmpty { body.removeLast() }
        while let first = body.first, first.trimmingCharacters(in: .whitespaces).isEmpty { body.removeFirst() }
        lines.replaceSubrange((h + 1)..<end, with: [""] + body + [line, ""])
        return lines.joined(separator: "\n")
    }

    /// Adds a rule to the Manager's learned rules (the old text stays in history). False if the file couldn't be written.
    @discardableResult
    static func addRule(_ rule: String, heading: String, root: URL = Vault.root) -> Bool {
        ensureLearnedFile(in: root)
        let url = root.appending(path: Agent.learned)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let new = insertRule(into: text, rule: rule, heading: heading)
        if new == text { return true }
        return (try? Vault.write(new, to: url, root: root)) != nil
    }

    /// Makes the learned-rules file if the vault has none yet (an install normally does, from the copy that ships).
    static func ensureLearnedFile(in root: URL = Vault.root) {
        let url = root.appending(path: Agent.learned), fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? learnedHeader.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Folds the old per-agent files in. Idempotent: once they are gone there is nothing to do. Returns the vault paths it moved to `.trash/`.
    /// Run before the app's own files are installed, because the install replaces the Manager's file, which had learned rules of its own in the old layout.
    @discardableResult
    static func migrate(root: URL = Vault.root) -> [String] {
        let fm = FileManager.default
        var learned: [(heading: String, rules: [String])] = [], moved: [String] = []
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        for (rel, heading) in old {
            let url = root.appending(path: rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let rules = learnedRules(in: text)
                if !rules.isEmpty { learned.append((heading, rules)) }
            }
            var dest = root.appending(path: ".trash/Agents-merged-\(stamp)/" + rel)
            if fm.fileExists(atPath: dest.path) { dest = dest.deletingLastPathComponent().appending(path: UUID().uuidString.prefix(6) + " " + dest.lastPathComponent) }
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: url, to: dest)
                moved.append(rel)
            } catch { learned.removeAll { $0.heading == heading } }   // not moved, so not copied either: the next launch tries again
        }
        // the Manager's own file, while it is still the old one (no `## Mode:` sections yet)
        let mine = root.appending(path: Agent.instructions)
        if let text = try? String(contentsOf: mine, encoding: .utf8), !text.contains("## Mode:") {
            let rules = learnedRules(in: text)
            if !rules.isEmpty { learned.append(("Manager", rules)) }
        }
        guard !learned.isEmpty else { return moved }
        ensureLearnedFile(in: root)
        let url = root.appending(path: Agent.learned)
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? learnedHeader
        for (heading, rules) in learned where !rules.allSatisfy({ text.contains($0) }) {
            if !text.hasSuffix("\n") { text += "\n" }
            text += "\n## \(heading)\n\n" + rules.joined(separator: "\n") + "\n"
        }
        try? Vault.write(text, to: url, root: root)
        return moved
    }

    static func check() {
        let fm = FileManager.default, box = fm.temporaryDirectory.appending(path: "sb-agentfiles-check")
        try? fm.removeItem(at: box)
        func put(_ rel: String, _ text: String) {
            try! fm.createDirectory(at: box.appending(path: rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try! text.write(to: box.appending(path: rel), atomically: true, encoding: .utf8)
        }
        let rules = learnedRules(in: "# Scribe agent\n\n## Open items\n\n- keep me out\n\n## Learned from Oscar's edits\n\n- Keep the notes short.\n2. Quote the slide number.\nNot a rule.\n\n## Next\n\n- not this either\n")
        precondition(rules == ["- Keep the notes short.", "2. Quote the slide number."], "learned rules are the list lines under their heading: \(rules)")
        precondition(learnedRules(in: "## Learned from Oscar's edits\n\nNothing yet (`AGENTS.md` §14).\n").isEmpty && learnedRules(in: "## Learned from Oscar's edits\n\n- Nothing yet.\n").isEmpty, "the placeholder is not a rule")
        put("Agents/Helper Agents/Scribe/Scribe agent.md", "# Scribe agent\n\n## Learned from Oscar's edits\n\n- Keep the notes short.\n")
        put("Agents/Helper Agents/Tutor/Tutor agent.md", "# Tutor agent\n\n## Learned from Oscar's edits\n\nNothing yet.\n")
        put("Agents/Helper Agents/Planner/Calendar Sync.md", "data that stays")
        put(Agent.instructions, "# Manager agent\n\n## Learned from Oscar's edits\n\n- Answer in two lines.\n")
        let moved = migrate(root: box)
        precondition(Set(moved) == ["Agents/Helper Agents/Scribe/Scribe agent.md", "Agents/Helper Agents/Tutor/Tutor agent.md"], "the old files are moved: \(moved)")
        precondition(!fm.fileExists(atPath: box.appending(path: "Agents/Helper Agents/Scribe/Scribe agent.md").path) && fm.fileExists(atPath: box.appending(path: "Agents/Helper Agents/Planner/Calendar Sync.md").path), "only the agent files go; the data beside them stays")
        let kept = (try? String(contentsOf: box.appending(path: Agent.learned), encoding: .utf8)) ?? ""
        precondition(kept.contains("## Scribe") && kept.contains("- Keep the notes short.") && kept.contains("## Manager") && kept.contains("- Answer in two lines.") && !kept.contains("## Tutor"), "learned rules are kept under their kind of work: \(kept)")
        precondition(migrate(root: box).isEmpty && ((try? String(contentsOf: box.appending(path: Agent.learned), encoding: .utf8)) ?? "") == kept, "a second run changes nothing")
        print("agent files ok: old per-agent files folded into one, learned rules kept")
    }
}
