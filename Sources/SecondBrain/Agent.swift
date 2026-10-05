import Foundation
import PDFKit

/// Set by the timeout on one queue and read by the reader on another, so it is locked.
final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _hit = false
    var hit: Bool {
        get { lock.withLock { _hit } }
        set { lock.withLock { _hit = newValue } }
    }
}

/// Runs a course agent through the Claude Code CLI (uses the signed-in Claude subscription — no API key).
enum Agent {
    static let cli: String = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                              FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/claude").path]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"

    /// `session` is nil when the run failed (including when Claude Code answered with an error such as a usage limit).
    struct Reply: Sendable {
        let text: String; let session: String?
        /// You stopped it (Stop in a chat, or pausing the Manager), so it isn't a failure and shouldn't count against the agent.
        var stopped = false
        /// The agent couldn't do the request and said so with a `DELEGATE:` line: why, for the Manager to pass it to another agent.
        var delegation: String? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard session != nil, t.uppercased().hasPrefix("DELEGATE") else { return nil }
            return String(t.drop { $0 != ":" }.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")[0]
        }
        /// Out of usage: the CLI says so in its reply, so background work should wait instead of retrying.
        var limited: Bool { session == nil && ["usage limit", "session limit", "rate limit", "limit reached", "hit your"].contains { text.localizedCaseInsensitiveContains($0) } }
    }

    /// Five agents, split by job (how the vault actually gets worked), not by course.
    struct Role: Identifiable, Hashable, Sendable {
        let id: String; let name: String; let job: String; let focus: String; let actions: [String]
        var course: String? = nil   // course code for a course agent, nil for a helper
    }
    static let roles: [Role] = [
        Role(id: "sorter", name: "Sorter", job: "Files everything in Unsorted",
             focus: "You keep the intake tray (Unsorted/) clear: slides and documents go to Files/Resources/{Course}/…, raw lecture notes fold into their Lecture note, links become Readings. You also run File Now and Sort Now (all of Unsorted at once, after Oscar approves).",
             actions: ["What’s waiting in Unsorted, and where would each item go?", "Anything in the inbox with conflicting dates?", "Which Unsorted items should I check by hand before Sort Now?"]),
        Role(id: "scribe", name: "Scribe", job: "Writes up lectures from slides",
             focus: "You write up Lectures and Tutorials from their slides and Oscar’s raw notes, following the templates and AGENTS.md §12 (slide numbers, his callout style, never rewriting his own lines).",
             actions: ["Which past lectures still need writing up?", "Summarise this week’s lectures in a few bullets each", "Which notes link slides that are missing?"]),
        Role(id: "librarian", name: "Librarian", job: "Keeps readings in order",
             focus: "You look after Readings: sources still `To Find`, citations marked “Title To Confirm”, reading packs, and which readings are due for which session. Never invent a citation.",
             actions: ["Which readings are due this week?", "List the readings still To Find, by course", "Which citations still need confirming?"]),
        Role(id: "planner", name: "Planner", job: "Deadlines, key dates and prep",
             focus: "You track deadlines, course Key dates and TaskNotes, flag conflicting dates, and prep Oscar for what’s next. Be concrete: dates, times, what to do first.",
             actions: ["What’s due in the next 7 days?", "Prep me for tomorrow", "Any conflicting or missing dates I should check?"]),
        Role(id: "tutor", name: "Tutor", job: "MCQs, flashcards and explanations",
             focus: "You turn Oscar’s notes and readings into study material: MCQs with answers, flashcards, summaries, glossaries, mind maps, podcast scripts and plain explanations, quoting the note, slide or page they come from. A podcast is a spoken-style script (Templates/Claude/Apps/Podcast Template.md) built only from sources you have actually read, using the PDF text copies.",
             actions: ["Make 5 MCQs from this week’s lectures", "Explain the hardest idea from last week simply", "What should I revise first, and why?"]),
        Role(id: "writer", name: "Writer", job: "Coaches essays and projects",
             focus: "You coach Oscar through essays and projects. Planner has already filled each note’s Brief, Question and Marking criteria; you work from those and from his lecture and reading notes: a thesis to consider, an outline with a word budget, an evidence plan citing note and slide, and a check of his draft against the rubric. You never write the submission for him or rewrite his own lines, and you never invent a source.",
             actions: ["Which essays and projects are due soonest, and how far along are they?", "What from my notes could I use for my next essay?", "Check my draft against the marking criteria"]),
        Role(id: "researcher", name: "Researcher", job: "Finds evidence and sources",
             focus: "You answer open questions with a short sourced brief. You search the web and read the pages, then write one new note in Files/Research/ from Templates/Claude/Files/Research Template.md (named `<Course> - Research - <Topic>`): the short answer, findings with a link and a strength (strong / single / weak) for each, the sources, and the gaps. Every claim has a link you opened; anything you could not verify goes under gaps. You gather and summarise; you never write text for Oscar's submissions, and you never invent a source, figure or date.",
             actions: ["What outside evidence does my next report need?", "Find out what's known about the company in my SM report", "What's the industry background for my case study?"]),
        Role(id: "analyst", name: "Analyst", job: "Does the maths and data work",
             focus: "You do the numbers: worked solutions for formative tutorials and workshops, and checks of Oscar's own answers against your own independent solution. Show every step, state formulas and units, and end each question with a line `**Answer:** …`. You never solve assessed questions, individual case studies or exam content, and you never run code or invent data; if a figure cannot be derived from the files, say so. Double-check every calculation before you reply.",
             actions: ["Work through this week's tutorial sheet", "Check my answers to the MSOA tutorial", "Which formulas do I need for the break-even question?"]),
    ]
    /// The front door: every request can start here. Not a helper (no desk): it routes and sets effort.
    static let manager = Role(id: "manager", name: "Manager", job: "Sends each request to the right agent",
        focus: "You are the Manager: you read a request, pick the agent best placed to handle it and how much effort it deserves, and say why in one line. You do not do the work yourself.",
        actions: ["What’s due this week, and what should I start on?", "Plan my next essay from its brief", "Make 5 MCQs from this week’s lectures", "Which readings still need finding?"])
    /// One agent per course: knows that course's notes and nothing else.
    static let courseRoles: [Role] = Vault.courses.sorted { $0.value < $1.value }.map { full, code in
        let name = code == "SM" ? "Strategy" : code
        return Role(id: code, name: name, job: "Course agent · \(full)",
                    focus: "You are the course agent for \(full) (\(code)). You know every note in the vault whose course is [[\(full)]]: the course note, Lectures, Tutorials, Readings, Essays, Projects and Revision. Answer only about this course; if asked about another, say which course agent to ask.",
                    actions: ["What’s due in \(name) in the next two weeks?", "Where are we in \(name), and what’s coming up?", "Which \(name) lectures still need writing up?", "What should I revise first for \(name)?"],
                    course: code)
    }
    static var all: [Role] { [manager] + roles + courseRoles }
    static func role(_ id: String) -> Role { all.first { $0.id == id } ?? roles[0] }
    /// The agent's own instructions in the vault: its working rules, open items and the log entries that apply.
    static func file(_ id: String) -> String {
        let r = role(id)
        if id == manager.id { return "Agents/Manager Agent/Manager agent.md" }   // outside Helper Agents: it routes work rather than being a helper
        return r.course == nil ? "Agents/Helper Agents/\(r.name)/\(r.name) agent.md" : "Agents/Course Agents/\(r.name)/\(r.name) course agent.md"
    }

    /// The one folder an agent may write in: its own notes to itself, open items and the rules it has learned.
    static func ownFolder(_ id: String) -> String {
        id == manager.id ? "Agents/Manager Agent" : role(id).course == nil ? "Agents/Helper Agents/\(role(id).name)" : "Agents/Course Agents/\(role(id).name)"
    }
    /// A permission pattern for one file (commas would split the list, so they become wildcards).
    /// What an agent may write besides its own folder: Researcher adds its briefs.
    static func writeScopes(_ id: String) -> [String] { [scope(folder: ownFolder(id))] + deliverables(id).map { scope(folder: Vault.dir($0)) } }
    /// Commas split the list and parentheses end the pattern, and `* [ ] { }` would be read as wildcards: a file called `Notes*.md` must not let an agent write to its neighbours, so all of them become `?`.
    static func scope(file rel: String) -> String { String(rel.map { ",()*[]{}!".contains($0) ? "?" : $0 }) }
    static func scope(folder rel: String) -> String { scope(file: rel) + "/**" }

    /// What the other agents did lately, so Planner knows Tutor made a podcast yesterday. `items` is newest first (the Activity Log); the Manager's own routing lines are noise.
    static func teamLog(_ items: [Activity], limit: Int = 10) -> String {
        let lines = items.filter { $0.agent != manager.id && !$0.text.hasPrefix("Couldn’t") }.prefix(limit).reversed().map {
            "- \(role($0.agent).name), \($0.time.formatted(.relative(presentation: .named))): \($0.text.prefix(140))"
        }
        return lines.isEmpty ? "" : "What the team has done lately (oldest first; build on it, don't repeat it):\n" + lines.joined(separator: "\n")
    }

    /// A different agent's check of a team's finished result against what was handed over: anything unsupported comes back as lines, nil when it's fine or the check couldn't run.
    static func verify(result: String, handoff: String, root: URL) async -> String? {
        let r = await run("""
        Check this result for claims, sources, page numbers or figures that are neither in the handed-over material nor in the vault notes (or PDF text copies) it names. Open them if you need to.
        Handed over:
        \(handoff.prefix(8000))

        Result:
        \(result.prefix(8000))

        Reply with the single word OK if everything traces. Otherwise one line per problem: what it says and why it isn't supported. Nothing else.
        """, system: "You are the Manager's checker in Oscar's University Brain app. The current directory is his University Obsidian vault. You only read.\n" + docMap, session: nil, canEdit: false, root: root, tier: .quick)
        return r.session == nil || r.text.uppercased().hasPrefix("OK") ? nil : r.text
    }

    /// A briefing last written before today may carry last week's facts: a chat refreshes it before consulting.
    static func briefingStale(_ course: String, root: URL) -> Bool {
        let f = root.appending(path: ownFolder(course) + "/Course briefing.md")
        guard let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return true }
        return !Calendar.current.isDateInToday(d)
    }

    /// Notes an agent may create from chat when Oscar asks for the thing itself: study material and research briefs, never his own notes.
    static func deliverables(_ id: String) -> [String] {
        switch id {
        case "tutor": ["MCQ", "Flashcards", "Summaries", "Mind Maps", "Glossary", "Podcast"]
        case "researcher": ["Research"]
        default: []
        }
    }

    /// A text copy of each PDF in Resources, because the CLI's Read can't open PDFs without poppler and agents have no shell. Only changed PDFs are re-read.
    static func cachePDFs(root: URL) {
        let fm = FileManager.default, res = root.appending(path: Vault.dir("Resources", root: root))
        guard let walk = fm.enumerator(at: res, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for case let pdf as URL in walk where pdf.pathExtension.lowercased() == "pdf" {
            let out = root.appending(path: ".pdf-text/" + pdf.path.replacingOccurrences(of: root.path + "/", with: "") + ".txt")
            let made = (try? out.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let made, made >= ((try? pdf.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture) { continue }
            guard let doc = PDFDocument(url: pdf) else { continue }
            let text = (0..<doc.pageCount).map { "[pdf page \($0 + 1)]\n" + (doc.page(at: $0)?.string ?? "") }.joined(separator: "\n")
            try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: out, atomically: true, encoding: .utf8)
        }
    }

    /// PDFs: the app extracts the text itself so the agent doesn't need PDF tools.
    static func pdfText(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "docx" || ext == "xlsx" { return officeText(url, part: ext == "docx" ? "word/document.xml" : "xl/sharedStrings.xml") }
        guard ext == "pdf", let doc = PDFDocument(url: url) else { return "" }
        let pages = (0..<doc.pageCount).compactMap { i in doc.page(at: i)?.string.map { "[slide \(i + 1)] " + $0 } }
        let text = pages.joined(separator: "\n").prefix(40_000)
        return text.isEmpty ? "" : "\n\nIts text, extracted by the app (\(doc.pageCount) pages):\n\(text)\n"
    }

    /// Word and Excel files are zips of XML: the app reads their text itself, because the agent has no shell to open them with.
    static func officeText(_ url: URL, part: String) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", url.path, part]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        var xml = String(decoding: data, as: UTF8.self)
        for end in ["</w:p>", "</si>"] { xml = xml.replacingOccurrences(of: end, with: "\n") }
        let text = xml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n").prefix(40_000)
        return text.isEmpty ? "" : "\n\nIts text, extracted by the app:\n\(text)\n"
    }

    /// The Sorter reads what is in Unsorted and replies with where each file goes (read-only); the app does the moves.
    static func planSorting(_ files: [URL], advice: String? = nil, root: URL) async -> Reply {
        let each = max(1_500, min(12_000, itemBudget / max(files.count, 1)))   // many files share one budget instead of each bringing its own 12,000 characters
        let items = files.map { f in
            let rel = f.path.replacingOccurrences(of: root.path + "/", with: "")
            return "### `\(rel)`" + String(pdfText(f).prefix(each))
        }.joined(separator: "\n\n")
        let intro = files.isEmpty
            ? "Nothing is waiting in Unsorted, but the calendar sync found classes in the next two weeks that have no note yet. Read Agents/Helper Agents/Planner/Calendar Sync.md and the existing Lectures and Tutorials notes, and plan the notes (and any task) that are missing, in the vault's weekly sequence and templates. Skip anything already ticked or already filed."
            : "Plan how to file everything waiting in Unsorted (\(files.count) items). Read each item and the notes it relates to. Also check Agents/Helper Agents/Planner/Calendar Sync.md for new items that need a note or task (skip anything already ticked or already filed)."
        return await run("""
        \(intro)\(advice.map { "\n\nCourse agent advice:\n\($0)" } ?? "")\n\n\(items)
        Reply with a short plan: one or two lines per item naming its exact destination and which notes you'll link or update. Don't change anything yet.
        If an item is unclear, say so and leave it out rather than guessing.
        If there is genuinely nothing you can file without guessing, reply with a single line starting `NOTHING:` and the reason, and stop.
        End with one line per file that should move, exactly in this form (paths from the vault root, no backticks):
        MOVE: <current path> -> <destination path>
        The app does the moving itself straight after your reply; originals go to .trash/.
        """, system: filingPrompt, session: nil, canEdit: false, root: root)
    }

    /// Where the Sorter may write while it carries out a plan: the note folders and the synced calendar note it ticks. Never `Agents/` or `Templates/`
    /// (it used to have write access to the whole vault, with only the review to catch a stray edit there).
    static func filingScopes(root: URL) -> [String] { Array(Set(noteScopes(root: root) + [scope(file: CalendarSync.file)])).sorted() }
    /// Every note folder (Lectures, Readings, MCQ… and Courses), where an agent may edit notes when Oscar asks it to. Never `Agents/` or `Templates/`.
    static func noteScopes(root: URL) -> [String] { Array(Set(Vault.folders.map { scope(folder: Vault.dir($0, root: root)) })).sorted() }

    /// Stage 2: carry out that plan in the same session, once the app has done the moves.
    static func approveFiling(session: String, moved: [String], root: URL) async -> Reply {
        let done = moved.isEmpty ? "No files needed moving." : "The app has already moved: " + moved.joined(separator: "; ") + "."
        return await run("\(done) Now do the note changes from your plan (don't move files), then reply with one short line per step saying what you did.",
                  system: filingPrompt, session: session, canEdit: false, root: root, writes: filingScopes(root: root))
    }


    // MARK: The Manager-centred pipeline: consult a course agent, the helper does the work, the Manager reviews.

    /// Replaced in tests, so the whole pipeline can run without spending any Claude usage.
    nonisolated(unsafe) static var stub: ((_ prompt: String, _ system: String, _ session: String?, _ writes: [String], _ tier: Manager.Tier) async -> Reply)?

    /// The Manager asks a course agent what matters about a job in its course, before the helper starts. Cheap: Haiku, and it reads its short course briefing first.
    static func consult(_ course: String, helper: String, job: String, note: String?, root: URL) async -> String? {
        let r = await run("""
        The Manager is about to give \(role(helper).name) this job: \(job).\(note.map { " The note is `\($0)`." } ?? "")
        Read your Course briefing (\(ownFolder(course))/Course briefing.md) first, and only open notes for specifics. In under 120 words, tell the helper the course-specific facts and cautions that matter for this job: dates and weights, what the lecturer emphasises, related notes to read, mistakes to avoid. Don't do the job.
        """, system: systemPrompt(role(course)), session: nil, canEdit: false, root: root, tier: .quick)
        return r.session == nil || r.text.isEmpty ? nil : r.text
    }

    /// A course agent keeps a short briefing of where its course is, so consults are cheap. Haiku, writes only that file.
    static func refreshBriefing(_ course: String, root: URL) async -> Reply {
        let file = ownFolder(course) + "/Course briefing.md"
        return await run("""
        Rewrite `\(file)` as your short Course briefing (under 40 lines, plain Markdown). Its first line is `Written <today's date>, teaching week <n>` from the date you were given. Then: where the course is now, the next dates, the assessments and their weights, the state of lectures, tutorials and readings, what the lecturer keeps emphasising, and the notes that need attention. Use only what is in the vault. Edit only that file, then reply with one line.
        """, system: systemPrompt(role(course)), session: nil, canEdit: false, root: root, tier: .quick, writes: [scope(file: file)])
    }

    /// One go at a job: the helper edits only the note it is given (or adds the one new note in `creating`), and may only change `sections` if the job names them.
    /// With a `session` it is a retry: the Manager's review found something and the helper fixes just that.
    static func doWork(role: String, task: String, note: URL, extra: String, advice: String?, creating: String?, sections: [String]?, feedback: String?, session: String?, root: URL) async -> Reply {
        let rel = Vault.rel(note)
        let where_ = creating.map { "creating the one new note inside `\(Vault.dir($0, root: root))/`" } ?? "editing only `\(rel)`"
        let prompt: String
        if let feedback, session != nil {
            prompt = "The Manager reviewed your work and found problems:\n\(feedback)\nFix only those, \(where_), then reply with one short line per change."
        } else {
            prompt = """
            \(task) The note is `\(rel)`.\(extra)
            \(advice.map { "The course agent advises:\n\($0)\n" } ?? "")
            Do the work now, \(where_).\(sections.map { " You may change only these sections (and `summary`, `readings`, `references` in the frontmatter if the job needs them): \($0.joined(separator: ", ")). Leave every other line exactly as it is." } ?? "")
            If there is nothing you can do without inventing content, reply with a single line starting `NOTHING:` and the reason, and change nothing. Otherwise reply with one short line per change you made.
            """
        }
        return await run(prompt, system: workPrompt(role), session: session, canEdit: false, root: root, tier: Manager.workTier(role),
                         writes: [creating.map { scope(folder: Vault.dir($0, root: root)) } ?? scope(file: rel)], web: ["librarian", "researcher"].contains(role))
    }

    /// The Analyst's second, independent pass: it solves the same questions without seeing the first answers, and replies only `Q<n>: <final answer>` lines.
    static func solveIndependently(note: URL, root: URL) async -> Reply {
        let rel = Vault.rel(note)
        return await run("""
        Read `\(rel)` and solve each question in its task section yourself, from scratch. Do not read any solutions already in the note. Reply with only one line per question in the form `Q<n>: <final numeric answer with its unit>`, nothing else.
        """, system: workPrompt("analyst"), session: nil, canEdit: false, root: root, tier: .careful)
    }

    /// The reply a stopped run gives.
    static let stoppedText = "Stopped by you."
    /// Set for everything the Manager starts on its own, so pausing can stop exactly that (not a chat, not a job you started with a button).
    @TaskLocal static var background = false
    /// Set for a job started from a button (Sort Now, a note's page): Stop ends these too, pausing does not.
    @TaskLocal static var button = false
    private static let live = LiveRuns()
    /// Ends the Manager's own runs that are going now, and refuses new ones for a few seconds, so the rest of a job in progress stops as well.
    static func stopBackgroundRuns() { live.stop(buttonsToo: false) }
    /// The same, and the jobs you started yourself as well. Chats are left alone (each has its own Stop).
    static func stopJobs() { live.stop(buttonsToo: true) }

    /// `canEdit` allows edits anywhere; `writes` allows edits only to those files or folders (`Folder/**`); `web` adds web search for finding sources.
    /// `onText` hears the answer as it is written (about ten times a second at most), for a chat to show it growing.
    static func run(_ prompt: String, system: String, session: String?, canEdit: Bool, root: URL, tier: Manager.Tier = .standard, writes: [String] = [], web: Bool = false,
                    onText: (@Sendable (String) -> Void)? = nil) async -> Reply {
        let prompt = clip(prompt)
        if let stub { return await stub(prompt, system, session, writes, tier) }
        let background = Agent.background, button = Agent.button
        if live.blocked(background: background, button: button) { return Reply(text: stoppedText, session: nil, stopped: true) }
        await Task.detached { cachePDFs(root: root) }.value
        let tools = (["Read", "Glob", "Grep"] + (canEdit ? ["Edit", "Write"] : writes.flatMap { ["Edit(\($0))", "Write(\($0))"] }) + (web ? ["WebSearch", "WebFetch"] : [])).joined(separator: ",")
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose"] + Manager.args(tier) + [
                    "--append-system-prompt", system,
                    "--allowedTools", tools]
        if let session { args += ["--resume", session] }
        // a call that hangs would freeze the Manager, so each one has a time limit
        let limit: Double = tier == .quick ? 240 : tier == .standard ? 900 : 1500
        var done = await launch(args + (onText == nil ? [] : ["--include-partial-messages"]), root: root, limit: limit, background: background, button: button, onText: onText)
        // a CLI that doesn't know the partial-messages flag fails at once with nothing to show: ask again without it
        if onText != nil, done.reply.session == nil, done.failedFast, !done.reply.stopped {
            done = await launch(args, root: root, limit: limit, background: background, button: button, onText: onText)
        }
        return done.reply
    }

    private struct Launch: Sendable { let reply: Reply; let failedFast: Bool }

    /// One Claude Code process, from start to its last line of output. Output is read as it arrives, so a chat can show the answer growing;
    /// cancelling the calling task (or `stopBackgroundRuns`) ends the process.
    private static func launch(_ args: [String], root: URL, limit: Double, background: Bool, button: Bool, onText: (@Sendable (String) -> Void)?) async -> Launch {
        let handle = ProcessHandle(), id = live.add(handle, background: background, button: button)
        defer { live.remove(id) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Launch, Never>) in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: cli)
                p.arguments = args
                p.currentDirectoryURL = root
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env
                let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
                p.standardInput = FileHandle.nullDevice   // nothing can make it wait for input
                do { try p.run() } catch {
                    cont.resume(returning: Launch(reply: Reply(text: "Couldn’t start Claude Code at \(cli): \(error.localizedDescription)", session: nil), failedFast: false)); return
                }
                handle.set(p)   // a stop that came before this point ends it now
                let began = Date(), timedOut = TimeoutFlag()
                DispatchQueue.global().asyncAfter(deadline: .now() + limit) {
                    guard p.isRunning else { return }
                    timedOut.hit = true; p.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
                }
                // Read as it comes, so a large reply can't fill the pipe and stall the process, and so the answer can be shown while it is written.
                // stream-json: one event per line; the last "result" is the answer, and rate-limit events say how much of the plan is used.
                DispatchQueue.global().async {
                    var raw = Data(), pending = Data(), current = "", lastEmit = Date.distantPast
                    var json: [String: Any]?
                    func emit(_ text: String, force: Bool) {
                        guard let onText, !text.isEmpty, force || Date().timeIntervalSince(lastEmit) > 0.08 else { return }
                        lastEmit = Date(); onText(text)
                    }
                    func take(_ line: Data) {
                        guard !line.isEmpty else { return }
                        guard let e = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { raw.append(line); raw.append(10); return }
                        switch e["type"] as? String {
                        case "rate_limit_event": PlanUsage.record(e)
                        case "result": json = e
                        case "stream_event":   // with partial messages on: the text arrives a few words at a time
                            guard let ev = e["event"] as? [String: Any] else { break }
                            if ev["type"] as? String == "message_start" { current = "" }
                            else if ev["type"] as? String == "content_block_delta", let d = ev["delta"] as? [String: Any], d["type"] as? String == "text_delta", let t = d["text"] as? String {
                                current += t; emit(current, force: false)
                            }
                        case "assistant":      // a whole message; its text replaces what was built up from pieces
                            if let m = e["message"] as? [String: Any], let parts = m["content"] as? [[String: Any]] {
                                let text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                                if !text.isEmpty { current = text; emit(text, force: true) }
                            }
                        default: break
                        }
                    }
                    while true {
                        let chunk = out.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        pending.append(chunk)
                        while let nl = pending.firstIndex(of: 10) {
                            take(pending.subdata(in: pending.startIndex..<nl))
                            pending.removeSubrange(pending.startIndex...nl)
                        }
                    }
                    take(pending)
                    p.waitUntilExit()
                    if timedOut.hit { cont.resume(returning: Launch(reply: Reply(text: "The agent took longer than \(Int(limit / 60)) minutes and was stopped.", session: nil), failedFast: false)); return }
                    if handle.isCancelled { cont.resume(returning: Launch(reply: Reply(text: stoppedText, session: nil, stopped: true), failedFast: false)); return }
                    let text = (json?["result"] as? String) ?? (raw.isEmpty ? "The agent didn’t reply. Is Claude Code signed in? Run `claude` once in Terminal." : String(decoding: raw, as: UTF8.self))
                    let failed = (json?["is_error"] as? Bool) == true
                    let session = failed ? nil : json?["session_id"] as? String
                    cont.resume(returning: Launch(reply: Reply(text: text.trimmingCharacters(in: .whitespacesAndNewlines), session: session),
                                                  failedFast: session == nil && json == nil && p.terminationStatus != 0 && Date().timeIntervalSince(began) < 10))
                }
            }
        } onCancel: { handle.cancel() }
    }
}

/// One running Claude process, so it can be ended from another thread (the user stopping it, or the task that started it being cancelled).
final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?, cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    /// Called once the process has started; if a stop already came, it ends at once.
    func set(_ p: Process) { lock.withLock { process = p; if cancelled { p.terminate() } } }
    func cancel() { lock.withLock { cancelled = true; process?.terminate() } }
}

/// The processes that are running now, and whether new ones from the Manager (or from a button) are being refused for a moment after a stop.
final class LiveRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [UUID: (handle: ProcessHandle, background: Bool, button: Bool)] = [:]
    private var refuseBackground = Date.distantPast, refuseButton = Date.distantPast
    func add(_ h: ProcessHandle, background: Bool, button: Bool) -> UUID { let id = UUID(); lock.withLock { handles[id] = (h, background, button) }; return id }
    func remove(_ id: UUID) { lock.withLock { handles[id] = nil } }
    func stop(buttonsToo: Bool) {
        let victims = lock.withLock { () -> [ProcessHandle] in
            let until = Date().addingTimeInterval(4)   // the rest of a job that was mid-way must not start fresh runs
            refuseBackground = until
            if buttonsToo { refuseButton = until }
            return handles.values.filter { $0.background || (buttonsToo && $0.button) }.map { $0.handle }
        }
        for v in victims { v.cancel() }
    }
    func blocked(background: Bool, button: Bool) -> Bool {
        lock.withLock { let now = Date(); return (background && now < refuseBackground) || (button && now < refuseButton) }
    }
}
