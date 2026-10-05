import Foundation

/// The jobs the Manager can hand out beyond the first few: the Analyst's, reading notes, and an exam plan.
extension AgentWork {
    /// Analyst: worked solutions for a tutorial or workshop sheet, written under "Solutions check" (the section for solutions, not Oscar's own work).
    static let analystSolutions = AgentWork(role: "analyst", label: "Work through this sheet", task: "This is a formative tutorial or workshop. Read its task section and the sheet linked in `resources`, and write full worked solutions under the “Solutions check” section: every step, formulas stated, units kept, and one line `**Answer:** …` ending each question. Never touch “My work”: that is Oscar's own. Don't run code or invent data; if a figure can't be derived from the files, say so under that question. Double-check every calculation.", heading: "Worked solutions", sections: ["Solutions check"], verify: true)
    /// Analyst: Oscar's own answers against its own independent solution.
    static let analystCheck = AgentWork(role: "analyst", label: "Check my answers", task: "Oscar has written his own answers under “My work”. Solve each question yourself first from the task, then compare his answers with yours, and write the comparison under “Solutions check” in a subsection titled `### Check of your answers`: for each question say right, or what is wrong and where, with the correct working. Put your own final answers in lines `**Answer:** …`. Never change “My work”.", heading: "Check your answers", sections: ["Solutions check"], verify: true)
    /// Librarian: reading notes a lecture links to that don't exist yet.
    static func readingNotes(missing: [String]) -> AgentWork {
        AgentWork(role: "librarian", label: "Create reading notes", task: "This lecture links these readings, but no note exists for them yet: \(missing.map { "“\($0)”" }.joined(separator: ", ")). For each one you can verify with web search, create a Reading note in Items/Readings/ from Templates/Claude/Readings Template.md, named `{Author} ({Year}) - {Title}`, filling the citation fields only from what you verified and linking the course. If you can't verify one, skip it and say so. Never invent a citation.", creates: "Readings", heading: "Create reading notes")
    }
    /// Planner: a revision plan when a written exam has a date.
    static func examPlan(course: String, day: String) -> AgentWork {
        AgentWork(role: "planner", label: "Plan the exam revision", task: "A written exam for \(course) is on \(day). Create one new note in Files/Summaries/ named `\(course) - Summary - Exam Plan`, from Templates/Claude/Summary Template.md, with `type: Summary` and `date: \(day)`. Fill the assessment details from Calendar Sync, the course note and the Learn snapshot (cite each), and the topic checklist with one row per examinable topic, listing the course's lectures and tutorials as the source notes and leaving confidence blank. Never invent the exam's format or length: leave blank what the files don't say.", creates: "Summaries", heading: "Exam revision plan")
    }
}

extension Store {
    /// A tutorial or workshop about numbers: MSOA's, or one whose task section talks about calculating. (The template's own "formulas" heading is not a sign.)
    func quantitative(_ n: Note, _ text: String) -> Bool {
        if n.course == "MSOA" { return true }
        let task = (Sections.body("The task", in: text) ?? "").lowercased()
        return ["calculate", "compute", "solve", "probability", "optimal", "forecast", "regression", "queue", "break-even", "npv", "expected value"].contains { task.contains($0) }
    }
    /// Names in a lecture's `readings` that have no note.
    func missingReadings(_ text: String) -> [String] {
        let have = Set(notes.filter { $0.folder == "Readings" }.map { $0.title.lowercased() })
        return (Vault.lists(text)["readings"] ?? []).filter { !$0.isEmpty && !have.contains($0.lowercased()) }
    }
    /// An exam in Calendar Sync (course, day) with no exam plan note yet.
    func examsWithoutPlan() -> [(course: String, code: String, day: String)] {
        guard let text = try? String(contentsOf: Vault.root.appending(path: CalendarSync.file), encoding: .utf8) else { return [] }
        var out: [(String, String, String)] = []
        for raw in text.split(separator: "\n") where raw.hasPrefix("- [ ]") && raw.localizedCaseInsensitiveContains("exam") {
            let line = String(raw)
            guard let m = line.firstMatch(of: /📅 (\d{4}-\d{2}-\d{2})/), let d = Vault.parseDate(String(m.1)), d >= today, days(d) <= 120,
                  let (full, code) = Vault.courses.first(where: { line.contains($0.key) }) else { continue }
            if notes.contains(where: { Study.isStudy($0.folder) && $0.course == code && $0.title.localizedCaseInsensitiveContains("exam") }) { continue }
            out.append((full, code, String(m.1)))
        }
        return out
    }
}
