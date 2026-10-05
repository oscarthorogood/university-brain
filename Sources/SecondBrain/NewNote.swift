import SwiftUI

/// New notes built from the vault's own templates (Templates/Claude), named by Templates/Guides/Naming Conventions.md.
enum NoteKind: String, CaseIterable, Identifiable {
    case lecture = "Lecture", tutorial = "Tutorial", essay = "Essay", project = "Project", reading = "Reading", mcq = "MCQ", flashcards = "Flashcards", pastPaper = "Past Paper", summary = "Summary", mindMap = "Mind Map", glossary = "Glossary", podcast = "Podcast", research = "Research", task = "Task"
    var id: Self { self }
    /// The study type this is, when it is one of the seven that came out of Revision.
    var study: Study.Kind? { Study.kinds.first { $0.noun == rawValue } }
    var folder: String {
        if let study { return study.folder }
        return switch self { case .lecture: "Lectures"; case .tutorial: "Tutorials"; case .essay: "Essays"; case .project: "Projects"
                      case .reading: "Readings"; case .research: "Research"; case .task: "TaskNotes/Tasks"; default: "" }
    }
    /// The Bases view that lists this kind of note: the `base` field has to point at it or the note is invisible in Obsidian.
    var base: String? { self == .task ? nil : folder + ".base" }
    var numbered: Bool { self == .lecture || self == .tutorial }
    var needsCourse: Bool { self != .task }
    /// `date` for sessions, `due` for work that is handed in.
    var dateKey: String { self == .lecture || study != nil || self == .research ? "date" : "due" }
    var topicLabel: String { self == .reading ? "Author (Year) - Short title" : self == .task ? "What needs doing" : self == .lecture || self == .tutorial || study != nil ? "Topic" : "Title" }

    func title(course: String, number: Int, topic: String) -> String {
        let t = String(topic.map { "/:\\".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespacesAndNewlines)   // no path characters in a filename
        let nn = String(format: "%02d", number)
        switch self {
        case .lecture: return "\(course) L\(nn) - \(t)"
        case .tutorial: return "\(course) T\(nn) - \(t)"
        case .essay: return "\(course) - Essay - \(t)"
        case .project: return "\(course) - Project - \(t)"
        case .mcq, .flashcards, .pastPaper, .summary, .mindMap, .glossary, .podcast: return "\(course) - \(rawValue) - \(t)"
        case .research: return "\(course) - Research - \(t)"
        case .reading, .task: return t
        }
    }
}

extension Vault {
    /// Creates the note from its template and returns its URL. Never overwrites.
    static func create(_ kind: NoteKind, course: String, number: Int, topic: String, date: Date?, root: URL = Vault.root) throws -> URL {
        let title = kind.title(course: course, number: number, topic: topic)
        let rel = "\(dir(kind.folder, root: root))/\(title).md", url = root.appending(path: rel)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw MoveError.exists(rel) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB_POSIX")
        let day = { (d: Date) -> String in f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
        let time = { (d: Date) -> String in f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f.string(from: d) }
        var text: String
        if kind == .task {
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000xxx"
            text = "---\nstatus: Not started\npriority: normal\n" + (date.map { "due: \(time($0))\n" } ?? "") + "dateCreated: \(f.string(from: .now))\ntags:\n  - task\n---\n\n"
        } else {
            let name = "\(kind.rawValue == "Reading" ? "Readings" : kind.rawValue) Template"
            text = try String(contentsOf: template(name, root: root), encoding: .utf8)
            text = setField(text, kind.study != nil ? "Course" : "course", to: "\"[[\(course)]]\"")
            if let base = kind.base { text = setField(text, "base", to: "\"[[\(base)]]\"") }
            if kind.numbered { text = setField(text, kind == .lecture ? "Lecture No." : "Tutorial No.", to: String(number)) }
            if let date { text = setField(text, kind.dateKey, to: kind == .lecture || kind == .tutorial ? time(date) : day(date)) }
            if kind.study != nil { text = setField(text, "status", to: "Not started") }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func checkNewNote() {
        precondition(NoteKind.lecture.title(course: "Strategic Management", number: 3, topic: " Search/Algorithms ") == "Strategic Management L03 - Search-Algorithms", "lecture title")
        precondition(NoteKind.essay.title(course: "Strategic Management", number: 0, topic: "Report") == "Strategic Management - Essay - Report", "essay title")
        let box = FileManager.default.temporaryDirectory.appending(path: "sb-new-check")
        try? FileManager.default.removeItem(at: box)
        try! FileManager.default.createDirectory(at: box.appending(path: "Templates/Claude"), withIntermediateDirectories: true)
        try! "---\ntags:\n  - task\ncourse: \"[[]]\"\nLecture No.:\nstatus: Not started\ndate:\n---\n\n## Body\n".write(to: box.appending(path: "Templates/Claude/Lecture Template.md"), atomically: true, encoding: .utf8)
        let u = try! create(.lecture, course: "Strategic Management", number: 4, topic: "Porter", date: Vault.parseDate("2026-10-05T15:10"), root: box)
        let t = try! String(contentsOf: u, encoding: .utf8)
        precondition(u.lastPathComponent == "Strategic Management L04 - Porter.md" && t.contains("course: \"[[Strategic Management]]\"") && t.contains("Lecture No.: 4") && t.contains("date: 2026-10-05T15:10") && t.hasSuffix("## Body\n"), "template fill: \(t)")
        precondition((try? create(.lecture, course: "Strategic Management", number: 4, topic: "Porter", date: nil, root: box)) == nil, "never overwrites")
        print("new note ok: filled from template, vault naming, no overwrite")
    }
}

struct NewNoteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind = NoteKind.lecture
    @State private var course = "Strategic Management"
    @State private var number = 1
    @State private var topic = ""
    @State private var hasDate = false
    @State private var date = Date.now
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New note").font(.system(size: 17, weight: .semibold))
            Picker("Type", selection: $kind) { ForEach(NoteKind.allCases) { Text($0.rawValue).tag($0) } }
            if kind.needsCourse {
                Picker("Course", selection: $course) { ForEach(Vault.courses.keys.sorted(), id: \.self) { Text($0).tag($0) } }
            }
            if kind.numbered { Stepper("\(kind.rawValue) number: \(number)", value: $number, in: 1...30) }
            TextField(kind.topicLabel, text: $topic)
            Toggle(kind.dateKey == "due" ? "Has a due date" : "Has a date", isOn: $hasDate)
            if hasDate { DatePicker("", selection: $date).labelsHidden() }
            if let error { Text(error).font(.caption).foregroundStyle(Color.redFG) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }.keyboardShortcut(.defaultAction).disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(20).frame(width: 380).onAppear {
            kind = store.newKind; store.newKind = .lecture
            if let c = store.newCourse { course = c; store.newCourse = nil }
        }
    }
    func create() {
        do {
            let url = try Vault.create(kind, course: course, number: number, topic: topic, date: hasDate ? date : nil)
            store.reload()
            store.page = kind == .task ? .folder("Tasks") : .note(url)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Scribe write-ups, Librarian citation checks and Writer essay plans: the agent plans read-only, you approve, then it edits that one note.
struct AgentWork: Identifiable {
    let role: String, label: String, task: String
    var creates: String? = nil     // a folder the job adds one new note to
    var heading: String? = nil     // names the job in the inbox, when the role alone doesn't
    var sections: [String]? = nil  // the only sections the helper may change; the Manager checks every other line is untouched
    var verify = false             // the Analyst's answers are checked against a second, independent solution
    var id: String { role }

    /// Planner fills a blank brief; this is what lets Writer start.
    static let brief = AgentWork(role: "planner", label: "Fill in the brief", task: "Fill in only this note's Brief at a glance, The question (or The brief) and Marking criteria, from the brief and rubric files linked in `resources` and the course note's Key dates (due date and weight). Do not write the thesis, outline or any part of the submission: Writer does that once the brief is in. Never invent: leave a row blank rather than guess.", heading: "Fill the brief",
                                  sections: ["Brief at a glance", "The question", "The brief", "Marking criteria", "Deliverables"])
    /// Researcher answers what an essay or project needs from outside the lecture notes, as a sourced brief in Files/Research/.
    static func research(for n: Note) -> AgentWork {
        AgentWork(role: "researcher", label: "Research this", task: "Work out what this \(n.kind.lowercased()) needs from outside Oscar's lecture notes: read its Brief, question and marking criteria (and the files in `resources`), pick the two or three questions the answer most depends on that his notes and readings don't already cover, and answer them with a sourced brief. Create exactly one new note in Files/Research/ from Templates/Claude/Files/Research Template.md, named by Templates/Guides/Naming Conventions.md (`<Course> - Research - <Topic>`), with `related` linking this note. Every claim needs a link you opened; mark each finding strong, single or weak; put anything you could not verify under Gaps. Never write text for the submission and never invent a source, figure or date.", creates: "Research", heading: "Research")
    }
    /// Librarian looks a missing source up on the web and fills the citation only from what it verifies.
    static let findSource = AgentWork(role: "librarian", label: "Find this source", task: "This reading has no source linked yet. Use web search to find the actual paper, book or page, check that author, year and title match, and fill the citation and `url` only from what you have verified. If you cannot verify it, say so and change nothing: never invent a citation.", heading: "Find the source")
    /// Tutor turns a written-up lecture into an MCQ set in Apps/MCQ/.
    static let revisionSet = AgentWork(role: "tutor", label: "Make an MCQ set", task: "Create exactly one new note in Apps/MCQ/ for this lecture, named by Templates/Guides/Naming Conventions.md (`<Course> - MCQ - <topic>`) and built from Templates/Claude/Apps/MCQ Template.md (read it first and keep its structure): 8 MCQs from this lecture note and its linked slides, each with the answer, a one-line explanation and the slide or note it comes from. Link this lecture in `related`, set `course` and `status: Not started`. Never copy the slides wholesale and never add facts that are not in the note or its files.", creates: "MCQ", heading: "MCQ set")
    static func forNote(_ n: Note) -> AgentWork? {
        if ["Lectures", "Tutorials"].contains(n.folder), n.unfilled {
            return AgentWork(role: "scribe", label: "Write this up from its slides", task: "Write up this \(n.kind.lowercased()) from the files in its `resources` and Oscar's own lines, following the template and AGENTS.md §12.")
        }
        if n.folder == "Readings", n.status == "To Find" || n.title.contains("Title To Confirm") {
            return AgentWork(role: "librarian", label: "Confirm this citation", task: "Confirm the source details and citation for this reading from its own file or url. Fill only what you can verify; never invent a citation.")
        }
        if n.folder == "Essays", !n.done {
            return AgentWork(role: "writer", label: "Plan this from its brief", task: "Plan this essay from the note's Brief at a glance, The question and Marking criteria (use the brief and rubric linked in `resources` if those sections are empty), Oscar's lecture notes, the readings and any brief in Files/Research/ that links this note (cite the Reading notes made from its sources, not the brief). Fill only the Thesis / argument (as a suggestion for him to refine), Outline (with the word budget), Evidence plan (claim, evidence, note and slide or page) and Sources sections, plus `summary`, `readings` and `references` if you can support them. Never write the submission itself, never rewrite his own lines, never invent a source; leave a row blank rather than guess.", sections: ["Thesis / argument", "Outline", "Evidence plan", "Sources", "Report outline", "Working notes"])
        }
        if n.folder == "Projects", !n.done {   // the Project template has no Thesis, Outline or Evidence sections
            return AgentWork(role: "writer", label: "Plan this from its brief", task: "Plan this project from the note's Brief at a glance, The brief, Marking criteria and Deliverables (use the brief and rubric linked in `resources` if those are empty), Oscar's lecture notes and the readings. Fill the Report outline section (a structure for the written deliverable with a word or page budget; if the note has no such section, put the suggestion under Working notes) plus the Sources section, `readings`, `references` and `summary` where you can support them. Milestones and Tasks belong to Planner. Never write the submission itself, never rewrite his own lines, never invent a source; leave a row blank rather than guess.", sections: ["Thesis / argument", "Outline", "Evidence plan", "Sources", "Report outline", "Working notes"])
        }
        return nil
    }
}

struct AgentWorkSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let work: AgentWork; let note: URL
    @State private var key = "manual:work:" + UUID().uuidString
    @State private var finished = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { AgentPortrait(id: work.role, size: 28); Text(Agent.role(work.role).name).font(.system(size: 16, weight: .semibold)); Spacer(); Text("Run by the Manager · \(Manager.workTier(work.role).rawValue) effort").font(.caption).foregroundStyle(Color.ink2) }
            JobProgress(key: key, finished: finished)
            HStack { Spacer(); Button(finished ? "Done" : "Close") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("The old version is kept in the note’s history.").font(.caption).foregroundStyle(Color.ink2)
        }
        .font(.system(size: 13)).padding(20).frame(width: 520)
        .task {
            guard let n = store.notes.first(where: { $0.id == note }) else { finished = true; return }
            await store.manualJob(.work(n, work, key: key, why: "You asked from the note page"))
            finished = true
        }
    }
}
