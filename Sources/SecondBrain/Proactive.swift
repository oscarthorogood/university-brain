import Foundation

/// What lets the Manager be proactive in a chat or a job without searching the vault: a few plain facts about where things stand, worked out on this Mac
/// (no model, no cost), and the two conventions a reply can use to hand something back to the app (`NEXT:` suggestions, `ASK:` questions).
extension Store {
    /// "Where things stand right now": what is waiting, behind, soon and at risk. Empty when nothing is, so a quiet vault adds nothing to a prompt.
    func stateDigest() -> String {
        let current = notes.filter { $0.course != nil }
        let classes = current.filter { ["Lectures", "Tutorials"].contains($0.folder) }
        func names(_ ns: [Note], limit: Int = 4) -> String {
            ns.prefix(limit).map(\.display).joined(separator: ", ") + (ns.count > limit ? " and \(ns.count - limit) more" : "")
        }
        var out: [String] = []
        if !unsorted.isEmpty { out.append("\(unsorted.count) item\(unsorted.count == 1 ? "" : "s") waiting in Unsorted.") }
        // a class counts as over two hours after it starts (the note has a start time, not an end)
        let behind = classes.filter { $0.unfilled && ($0.when.map { $0 < Date.now.addingTimeInterval(-7200) } ?? false) }.sorted { $0.whenOrFar > $1.whenOrFar }
        if !behind.isEmpty { out.append("Happened but not written up (\(behind.count)): \(names(behind)).") }
        let next = classes.filter { !$0.done && ($0.when.map { $0 > Date.now && days($0) <= 2 } ?? false) }.sorted { $0.whenOrFar < $1.whenOrFar }
        if !next.isEmpty {
            let noSlides = next.filter { n in
                let text = (try? String(contentsOf: n.id, encoding: .utf8)) ?? ""
                return Vault.rawItems(text, "resources").allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            out.append("Classes in the next two days: \(names(next))." + (noSlides.isEmpty ? "" : " No slides linked yet for \(names(noSlides))."))
        }
        let work = current.filter { ["Essays", "Projects", "TaskNotes/Tasks"].contains($0.folder) && !$0.done && $0.when != nil }
        let overdue = work.filter { days($0.whenOrFar) < 0 }.sorted { $0.whenOrFar < $1.whenOrFar }
        if !overdue.isEmpty { out.append("Overdue and still open: \(names(overdue)).") }
        let week = work.filter { (0...7).contains(days($0.whenOrFar)) }.sorted { $0.whenOrFar < $1.whenOrFar }
        if !week.isEmpty {
            out.append("Due within a week: " + week.prefix(5).map { "\($0.display) (in \(days($0.whenOrFar))d" + ($0.status == "Not started" ? ", not started)" : ")") }.joined(separator: ", ") + (week.count > 5 ? " and \(week.count - 5) more." : "."))
        }
        let sources = current.filter { $0.folder == "Readings" && !$0.done && ($0.status == "To Find" || $0.title.contains("Title To Confirm")) }
        if !sources.isEmpty { out.append("\(sources.count) reading\(sources.count == 1 ? "" : "s") still without a confirmed source.") }
        let paused = Agent.roles.compactMap { r in breakerUntil(r.id).map { _ in r.label } }
        if !paused.isEmpty { out.append("Paused after failing review three times: \(paused.joined(separator: ", ")).") }
        guard !out.isEmpty else { return "" }
        return "Where things stand right now (worked out on this Mac from the vault; trust it over a briefing):\n" + out.map { "- " + $0 }.joined(separator: "\n")
    }
}

extension Agent {
    /// A reply may end with up to three `NEXT: <short label> | <what Oscar could ask next>` lines: what it noticed that is worth doing. The app takes them off the
    /// text and offers each as a quick reply under the answer. Lines that aren't in that form are left in the text, and so is a reply made of nothing else.
    static func splitNext(_ text: String) -> (body: String, chips: [Message.Chip]) {
        var lines = text.components(separatedBy: "\n"), chips: [Message.Chip] = []
        while let last = lines.last {
            let t = last.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { lines.removeLast(); continue }
            guard t.hasPrefix("NEXT:") else { break }
            let parts = t.dropFirst(5).split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { break }
            chips.insert(Message.Chip(label: String(parts[0].prefix(30)), prompt: parts[1]), at: 0)
            lines.removeLast()
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? (body: text, chips: []) : (body: body, chips: Array(chips.prefix(3)))
    }

    /// The `ASK: <file> — <question>` lines of a plan: the items the Sorter could not place without guessing.
    static func askLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("ASK:") else { return nil }
            let rest = t.dropFirst(4).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
    }

    static func checkProactive() {
        let a = splitNext("Done.\n\nNEXT: Write up SM L05 | Write up SM L05 from its slides\nNEXT: Check readings | Which readings still need a source?\n")
        precondition(a.body == "Done." && a.chips.count == 2 && a.chips[0].label == "Write up SM L05" && a.chips[1].prompt == "Which readings still need a source?", "NEXT lines become quick replies: \(a)")
        let b = splitNext("NEXT: only | this")
        precondition(b.body == "NEXT: only | this" && b.chips.isEmpty, "a reply of nothing but a suggestion is kept as text")
        let c = splitNext("It is fine.\nNEXT: broken line with no bar")
        precondition(c.body == "It is fine.\nNEXT: broken line with no bar" && c.chips.isEmpty, "a malformed suggestion stays in the text")
        precondition(splitNext("Plain answer.").chips.isEmpty && splitNext("Plain answer.").body == "Plain answer.", "an ordinary reply is untouched")
        precondition(askLines("Plan.\nASK: notes.pdf — MSOA or SM?\n  ASK: scan.png — what is this?\nASK:\nMOVE: a -> b") == ["notes.pdf — MSOA or SM?", "scan.png — what is this?"], "ASK lines")
        print("proactive ok: next-step chips and sorting questions")
    }
}
