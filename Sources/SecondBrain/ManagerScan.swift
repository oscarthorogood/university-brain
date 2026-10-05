import SwiftUI

/// A job the Manager handed out, from the moment it picks it to the moment it has checked the result. Saved so the Activity Log and Undo survive a relaunch.
/// Where the app keeps its own records (the Activity Log and the jobs). Pointing the app at another vault, to try something on a copy, gives it its own records too,
/// so a test never writes into the real ones.
enum Support {
    static var dir: URL {
        if let v = ProcessInfo.processInfo.environment["SECOND_BRAIN_VAULT"] { return URL(fileURLWithPath: v).appending(path: ".app-support") }
        return URL.applicationSupportDirectory.appending(path: "SecondBrain")
    }
}

struct InboxItem: Identifiable, Codable {
    enum Kind: String, Codable { case filing, work }
    /// planning → consulting (a course agent advises) → working (the helper does it) → checking (the Manager reviews) → done, or rejected (undone).
    /// `ready` only exists in older saved files, from when a plan waited for a tick.
    enum State: String, Codable { case planning, ready, consulting, working, checking, done, failed, dismissed, rejected }
    var id = UUID()
    var kind: Kind
    var agent: String
    var title: String
    var plan = ""
    var session: String?
    var paths: [String] = []     // vault-relative: the files being filed, or the note being worked on
    var state: State
    var result: String?
    var reason: String?          // why the Manager handed it to this agent
    var key: String              // what this is about; the same thing is never proposed twice
    var created = Date.now
    // Optional so inbox.json saved by older versions still loads.
    var scope: String?           // a folder this job may add one new note to (MCQ for an MCQ set)
    var auto: Bool?
    var undo: Undo?              // what it changed, so one tap can put it back
    var outputs: [String: String]?   // note → copy of what the agent wrote there, to learn from your later edits
    var advice: String?          // what the course agent(s) told the helper
    var verdict: String?         // what the Manager's review decided
    struct Undo: Codable { var restore: [String] = []; var created: [String] = []; var moves: [[String]] = []; var statuses: [String: String] = [:]; var snapshots: [String: String]? = nil }   // snapshots: the history file holding each restored note as it was before the job
    static func outputDir(_ id: UUID) -> URL { Support.dir.appending(path: "outputs/\(id.uuidString)") }

    static var file: URL { Support.dir.appending(path: "inbox.json") }
    static func load() -> [InboxItem] {
        var items = (try? JSONDecoder().decode([InboxItem].self, from: Data(contentsOf: file))) ?? []
        for i in items.indices {   // a run cut short by quitting can't be resumed, and nothing waits for a tick any more
            switch items[i].state {
            case .planning, .ready, .consulting: items[i].state = .dismissed
            case .working, .checking: items[i].state = .failed; items[i].result = "Interrupted when the app closed."
            default: break
            }
        }
        return items.filter { $0.created > .now.addingTimeInterval(-14 * 86400) }
    }
    static func save(_ items: [InboxItem]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items.suffix(100)).write(to: file, options: .atomic)
    }
}

extension Store {
    func saveInbox() { InboxItem.save(inbox) }
    /// Jobs the Manager is working on right now.
    var activeJobs: [InboxItem] { inbox.filter { [.planning, .consulting, .working, .checking].contains($0.state) } }

    // MARK: Triggers

    /// Looks again shortly after the vault settles or the app opens. One thing at a time.
    func scheduleAutopilot(after seconds: Double = 20) {
        guard autopilotOn else { return }
        autopilotTimer?.cancel()
        autopilotTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            // The tick runs in a task of its own. Every vault reload reschedules (and so cancels) this timer; if the tick ran inside it,
            // a reload part-way through would cancel the tick's own network calls, and the review would read the cancelled link checks as dead links.
            Task { await self.autopilotTick() }
        }
    }
    func setAutopilot(_ on: Bool) {
        autopilotOn = on
        UserDefaults.standard.set(on, forKey: "autopilotOn")
        if on { scheduleAutopilot(after: 2) } else { autopilotTimer?.cancel() }
    }

    // MARK: Budget
    /// Deep (Opus) jobs are the costly ones; with no reading of the plan, the Manager starts at most one on its own per day.
    func deepBudgetLeft() -> Bool {
        let day = (UserDefaults.standard.array(forKey: "managerDeepPlans") as? [Date] ?? []).filter { $0 > .now.addingTimeInterval(-86400) }
        UserDefaults.standard.set(day, forKey: "managerDeepPlans")
        return day.isEmpty
    }
    func spendDeep() {
        UserDefaults.standard.set((UserDefaults.standard.array(forKey: "managerDeepPlans") as? [Date] ?? []) + [Date.now], forKey: "managerDeepPlans")
    }
    /// Room for another background job. With a recent reading of the Claude plan the Manager spends while there is room, up to the preset in the Manager menu
    /// (the rest is left for your own use); without one it keeps cautious caps. A runaway guard of 12 an hour applies either way.
    func budgetLeft(deep: Bool) -> Bool {
        guard Date.now > (UserDefaults.standard.object(forKey: "autopilotPausedUntil") as? Date ?? .distantPast) else { return false }
        let hour = (UserDefaults.standard.array(forKey: "autopilotPlans") as? [Date] ?? []).filter { $0 > .now.addingTimeInterval(-3600) }
        UserDefaults.standard.set(hour, forKey: "autopilotPlans")
        guard hour.count < 12 else { return false }
        guard let s = PlanUsage.current, !PlanUsage.stale, let five = s.used(s.five) else { return hour.count < (Triage.available ? 5 : 3) && (!deep || deepBudgetLeft()) }
        return Manager.hasRoom(five: five, week: s.used(s.week) ?? 0, deep: deep, preset: budgetPreset)
    }
    /// Said once in a while, so a quiet Manager isn't a mystery.
    func holdOff() {
        guard ((UserDefaults.standard.object(forKey: "holdLogged") as? Date) ?? .distantPast) < .now.addingTimeInterval(-3 * 3600) else { return }
        UserDefaults.standard.set(Date.now, forKey: "holdLogged")
        let five = PlanUsage.current.flatMap { $0.used($0.five) }.map { "\(Int(($0 * 100).rounded()))% of the 5-hour window" } ?? "the plan"
        log(Agent.manager.id, "Holding off background work: \(five) is used and the budget is \(budgetPreset). It carries on when there is room.")
    }
    func spendPlan() {
        UserDefaults.standard.set((UserDefaults.standard.array(forKey: "autopilotPlans") as? [Date] ?? []) + [Date.now], forKey: "autopilotPlans")
    }
    /// Web research is the heaviest thing an agent does on the Claude plan, so the Manager starts at most one on its own a day.
    func researchLeft() -> Bool { ((UserDefaults.standard.array(forKey: "managerResearch") as? [Date]) ?? []).allSatisfy { $0 < .now.addingTimeInterval(-86400) } }
    func spendResearch() { UserDefaults.standard.set([Date.now], forKey: "managerResearch") }

    /// Runs a calendar sync and remembers when and how it went (Settings → Sync shows it).
    @discardableResult func syncCalendar() async -> String {
        let r = await CalendarSync.sync()
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastCalendarSync")   // a number, because Settings reads it with @AppStorage
        UserDefaults.standard.set(r, forKey: "lastCalendarResult")
        reload()
        return r
    }

    // MARK: The tick
    func autopilotTick() async {
        guard !tickRunning else { return }   // the running tick schedules the next one when it ends
        tickRunning = true
        defer { tickRunning = false }
        await tick()
    }
    private func tick() async {
        guard autopilotOn, !agentBusy else { return }
        // The calendar is plain fetching and a rewrite of one managed section, so it just happens, as often as Settings → Sync says.
        let cfg = SyncConfig.load()
        if cfg.everyMinutes > 0, cfg.feeds.contains(where: \.enabled),
           Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: "lastCalendarSync") > Double(cfg.everyMinutes) * 60 {
            let r = await syncCalendar()
            log("planner", r.hasPrefix("Synced") ? r : "Calendar sync failed: \(r)")
        }
        // Zotero: every 15 minutes while connected, both ways. Only changes and failures reach the log.
        if Zotero.Config.connected, Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: "lastZoteroSync") > 15 * 60 {
            let r = await syncZotero()
            if r.changed { log("librarian", r.text) }
        }
        maybeBrief()
        notifyDueToday()
        // Paused, quiet hours, on battery: the Manager still keeps the calendar but starts nothing.
        guard blockedReason() == nil else { scheduleAutopilot(after: 600); return }
        guard thinking.isEmpty else { scheduleAutopilot(after: 60); return }   // you are chatting with an agent: you go first
        await runChecks()
        await weekAhead()
        let jobs = scan()
        await maintainBriefings(hasJobs: !jobs.isEmpty)
        guard !jobs.isEmpty else { return }
        if PlanUsage.stale { await PlanUsage.refresh() }
        guard budgetLeft(deep: false) else { holdOff(); scheduleAutopilot(after: 900); return }
        let deepOK = budgetLeft(deep: true)
        guard let job = jobs.first(where: { !$0.job.isDeep || deepOK })?.job else { scheduleAutopilot(after: 900); return }
        // Decided on this Mac, so it costs nothing: junk waiting in Unsorted never reaches Claude.
        if case .sorting(let files, let key) = job, !(await Triage.worthIt(files)) {
            markHandled(key); log(Agent.manager.id, "Left \(files.count) item\(files.count == 1 ? "" : "s") in Unsorted alone: they look like junk. Sort Now still files them if you want.")
            scheduleAutopilot(after: 5); return
        }
        guard !agentBusy else { scheduleAutopilot(after: 20); return }
        spendPlan()
        await runJob(job)
        scheduleAutopilot(after: 20)   // there may be more; the budget decides how many
    }

    /// Run a job now, from a button (Sort Now, File Now, a note's page): waits its turn, ignores the budget and the pause, and goes through the same consult, work and review.
    func manualJob(_ job: Job) async {
        while agentBusy { try? await Task.sleep(for: .milliseconds(400)) }
        await runJob(job)
    }

    // MARK: Finding work

    enum Job {
        case sorting([URL], key: String); case work(Note, AgentWork, key: String, why: String); case learn(InboxItem, String, key: String)
        var isDeep: Bool { if case .work(_, let w, _, _) = self { w.role == "writer" } else { false } }
        var agent: String {
            switch self { case .sorting: "sorter"; case .work(_, let w, _, _): w.role; case .learn(let i, _, _): i.agent }
        }
        var label: String {
            switch self {
            case .learn(let i, let rel, _): "\(i.agent) · learn from your edits to \(rel)"
            case .sorting(let f, _): "sorter · \(f.count) file(s) in Unsorted"
            case .work(let n, let w, _, let why): "\(w.role) · \(n.display) — \(why)"
            }
        }
    }

    func known(_ key: String) -> Bool { inbox.contains { $0.key == key && $0.state != .rejected } || handled.contains(key) }
    /// Remembers a key, oldest dropped first. (Trimming the Set itself dropped arbitrary keys, recent ones included, so finished jobs and one-off alerts came back.)
    func markHandled(_ key: String) {
        guard handled.insert(key).inserted else { return }
        var order = UserDefaults.standard.stringArray(forKey: "autopilotHandled") ?? []
        order.append(key)
        if order.count > 2000 { order.removeFirst(order.count - 2000); handled = Set(order) }
        UserDefaults.standard.set(order, forKey: "autopilotHandled")
    }

    /// The Manager's scan: everything a helper could usefully do right now, ranked, best first.
    func scan(allowDeep: Bool = true) -> [(score: Double, job: Job)] {
        var found: [(score: Double, job: Job)] = []
        func add(_ id: String, _ score: Double, _ job: Job) { if jobOn(id) { found.append((score, job)) } }
        // 1. Unsorted: skip credential-looking files and notes that are empty or still being typed.
        let fm = FileManager.default
        let files = unsorted.filter { u in
            if u.pathExtension == "txt" { return false }
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if u.pathExtension == "md" { return (v?.fileSize ?? 0) > 60 && (v?.contentModificationDate ?? .distantPast) < .now.addingTimeInterval(-600) }
            return fm.fileExists(atPath: u.path)
        }
        if !files.isEmpty {
            let key = "sort:" + files.map { $0.lastPathComponent + String((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }.joined(separator: "|")
            if !known(key) { add("unsorted", 100, .sorting(files, key: key)) }
        }
        var researchText: String?, revisionText: String?   // read once, only if needed
        // a revision set is only made for the newest written-up lecture of each course, so a batch of lectures doesn't become a batch of jobs
        let newestLecture = Dictionary(grouping: notes.filter { $0.folder == "Lectures" && !$0.unfilled && $0.course != nil && ($0.when.map { (-5...0).contains(days($0)) } ?? false) }, by: \.course)
            .compactMapValues { $0.max { $0.whenOrFar < $1.whenOrFar }?.id }
        for n in notes where n.course != nil {
            guard !inUse(n.id) else { continue }
            let text = (try? String(contentsOf: n.id, encoding: .utf8)) ?? ""
            let hasSource = !Vault.rawItems(text, "resources").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.isEmpty || !(Vault.frontmatter(text)["url"] ?? "").isEmpty
            let due = n.when.map { days($0) }
            var work = AgentWork.forNote(n), id = "writeup"
            let tpl = ["Lectures", "Tutorials"].contains(n.folder) ? Sections.template(forFolder: n.folder) : ""
            if ["Essays", "Projects"].contains(n.folder), !n.done, Manager.needsBrief(text) { work = AgentWork.brief; id = "brief" }   // Planner fills the brief; Writer starts once it is in
            else if ["Essays", "Projects"].contains(n.folder), !n.done, researchLeft(), let d = due, (0...21).contains(d), jobOn("research") {
                if researchText == nil { researchText = notes.filter { $0.folder == "Research" }.map { (try? String(contentsOf: $0.id, encoding: .utf8)) ?? "" }.joined() }
                if !(researchText ?? "").contains(n.title) { work = AgentWork.research(for: n); id = "research" }
            }
            else if n.folder == "Tutorials", let d = due, d <= 0, quantitative(n, text) {   // the Analyst: Oscar's own answers to check, or worked solutions
                if !Sections.isTemplate("My work", in: text, template: tpl), !text.contains("Check of your answers") { work = AgentWork.analystCheck; id = "checkanswers" }
                else if (hasSource || !Sections.isTemplate("The task", in: text, template: tpl)), Sections.isTemplate("Solutions check", in: text, template: tpl) { work = AgentWork.analystSolutions; id = "solutions" }
            }
            else if work?.role == "librarian", !hasSource { work = AgentWork.findSource; id = "source" }
            else if work == nil, n.folder == "Lectures", let c = n.course, newestLecture[c] == n.id { work = AgentWork.revisionSet; id = "revisionset" }
            else if work == nil, n.folder == "Lectures", let d = due, (0...7).contains(d), !missingReadings(text).isEmpty { work = AgentWork.readingNotes(missing: missingReadings(text)); id = "readingnotes" }
            guard let w = work, !cooling(w.role, n.path) else { continue }
            var score = 0.0, why = "", suffix = Int((try? n.id.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0)
            switch (w.role, w.heading) {
            case ("writer", _):   // essays and projects due within four weeks that still have a blank outline; costly, so gated
                guard allowDeep, Manager.writerReady(n, text), let d = due, (0...28).contains(d) else { continue }
                id = "outline"; score = 80 - Double(d); why = "Due in \(d)d and the outline is still blank"
            case ("researcher", _):
                guard let d = due else { continue }
                score = 82 - Double(d); why = "Due in \(d)d, the brief is in, and nothing outside the notes has been researched"
            case ("planner", _):   // the brief is blank: Planner fills it, and that is what lets Writer begin
                guard hasSource, let d = due, (0...28).contains(d) else { continue }
                score = 85 - Double(d); why = "Due in \(d)d and the brief is still blank"
            case ("analyst", "Check your answers"): score = 55; why = "You have written your answers and they haven't been checked"
            case ("analyst", _): score = 60; why = "The tutorial has happened and has no worked solutions"
            case ("librarian", "Find the source"):
                guard let d = due, (0...7).contains(d) else { continue }
                score = 45; why = "Due in \(d)d with no source yet"
            case ("librarian", "Create reading notes"): score = 40; why = "A lecture this week links readings that have no note"; suffix = 0
            case ("tutor", _):
                if revisionText == nil { revisionText = notes.filter { Study.isStudy($0.folder) }.map { (try? String(contentsOf: $0.id, encoding: .utf8)) ?? "" }.joined() }
                guard !(revisionText ?? "").contains(n.title) else { continue }
                score = 30; why = "Written up recently with no revision set"; suffix = 0   // once per lecture
            case ("scribe", _):
                guard (n.when ?? .distantFuture) <= .now, hasSource else { continue }
                score = 50; why = "Delivered, slides linked, not written up"
            default:
                guard hasSource else { continue }
                id = "citation"; score = 20; why = "Reading with a source to confirm"
            }
            if let d = due, d <= 3, d >= -1, !n.done { score += 30; why += " (due very soon)" }   // an at-risk deadline jumps the queue
            let key = "work:\(w.role):\(n.path):\(suffix)"
            if !known(key) { add(id, score, .work(n, w, key: key, why: why)) }
        }
        // an exam gets a date: Planner builds a topic checklist and revision plan, anchored on the course note
        for e in examsWithoutPlan() {
            guard let course = notes.first(where: { $0.folder == "Courses" && $0.course == e.code }), !cooling("planner", course.path) else { continue }
            let key = "exam:\(e.code):\(e.day)"
            if !known(key) { add("examplan", 70, .work(course, AgentWork.examPlan(course: e.course, day: e.day), key: key, why: "A written exam is on \(e.day) and has no revision plan")) }
        }
        // learn from edits you made to what an agent wrote
        for item in inbox where item.state == .done && item.kind == .work && (item.created > .now.addingTimeInterval(-14 * 86400)) {
            for (rel, file) in item.outputs ?? [:] {
                let url = Vault.root.appending(path: rel)
                guard let mt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate), mt < .now.addingTimeInterval(-1800),   // you have stopped typing
                      let now = try? String(contentsOf: url, encoding: .utf8), let was = try? String(contentsOf: InboxItem.outputDir(item.id).appending(path: file), encoding: .utf8), now != was else { continue }
                let key = "learn:\(item.id):\(rel):\(Int(mt.timeIntervalSince1970))"
                if !known(key) { add("learn", 10, .learn(item, rel, key: key)) }
            }
        }
        return found.filter { agentFree($0.job.agent) }.sorted { $0.score > $1.score }
    }

    // MARK: The pipeline: consult, work, review

    /// Course agents to ask about a job: the note's course, or the courses the Unsorted files look like they belong to.
    func coursesFor(_ job: Job) -> [String] {
        switch job {
        case .work(let n, _, _, _): return n.course.flatMap { agentOn($0) ? [$0] : nil } ?? []
        case .learn: return []
        case .sorting(let files, _):
            var out: [String] = []
            for f in files {
                let rel = Vault.rel(f).lowercased()
                for (full, code) in Vault.courses where !out.contains(code) && agentOn(code) && (rel.contains(full.lowercased()) || rel.range(of: "\\b\(code.lowercased())\\b", options: .regularExpression) != nil) { out.append(code) }
            }
            return out
        }
    }

    private func makeItem(_ job: Job) -> InboxItem? {
        switch job {
        case .sorting(let files, let key):
            return InboxItem(kind: .filing, agent: "sorter", title: "Filing \(files.count) item\(files.count == 1 ? "" : "s")", paths: files.map { Vault.rel($0) }, state: .planning, reason: "\(files.count) waiting in Unsorted", key: key)
        case .work(let n, let w, let key, let why):
            let title = w.heading.map { "\($0): \(n.display)" } ?? (w.role == "scribe" ? "Write up \(n.display)" : w.role == "writer" ? "Plan \(n.display)" : "Confirm citation: \(n.display)")
            return InboxItem(kind: .work, agent: w.role, title: title, paths: [Vault.rel(n.id)], state: .planning, reason: why, key: key, scope: w.creates)
        case .learn: return nil
        }
    }

    func runJob(_ job: Job) async {
        if case .learn(let i, let rel, let key) = job { await runLearn(i, rel, key); return }
        guard let item = makeItem(job) else { return }
        let id = item.id, agent = item.agent, root = Vault.root
        func update(_ f: (inout InboxItem) -> Void) { if let i = inbox.firstIndex(where: { $0.id == id }) { f(&inbox[i]); saveInbox() } }
        spendJob(agent)
        if agent == "writer" { spendDeep() }
        if agent == "researcher" { spendResearch() }
        log(Agent.manager.id, "Assigned to \(Agent.role(agent).name) (\(Manager.workTier(agent).rawValue)): \(item.title) — \(item.reason ?? "")")
        inbox.append(item); saveInbox()
        let rel0 = item.paths.first
        if item.kind == .work, let p = rel0 { claim(p) }   // the note shows Agent In Progress while a helper has it
        agentBusy = true
        defer { agentBusy = false; for a in Set([agent, Agent.manager.id] + coursesFor(job)) { thinking.remove(a) }; if item.kind == .work { release(rel0) } }
        // so nothing a helper does is lost, and the review has the text from before (off the main thread: it reads every note)
        let noteURLs = notes.map(\.id)
        await Task.detached { for u in noteURLs { try? Vault.snapshot(u, root: root) } }.value
        let before = Set(notes.map { Vault.rel($0.id) }), started = Date().addingTimeInterval(-1)
        let prevStatus = item.kind == .work ? claims[rel0 ?? ""] : nil

        // consult: a course agent tells the helper what matters in its course
        var advice: String?
        let courses = coursesFor(job)
        if !courses.isEmpty {
            update { $0.state = .consulting }
            var parts: [String] = []
            for c in courses.prefix(2) {
                thinking.insert(c)
                let a = await Agent.consult(c, helper: agent, job: item.title, note: rel0, root: root)
                thinking.remove(c)
                if let a { parts.append("\(Agent.role(c).name): \(a)"); log(c, "Advised \(Agent.role(agent).name) on “\(item.title)”: \(String(a.split(separator: "\n").first ?? "").prefix(140))") }
            }
            advice = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
            update { $0.advice = advice }
        }

        // work: the helper does it, with no tick
        update { $0.state = .working }
        thinking.insert(agent)
        var summary = "", planText = "", ok = true, nothing = false, session: String?, moved: [[String]] = [], work: AgentWork?
        switch job {
        case .sorting(let files, _):
            // exact copies of files already in Resources/ are decided here, byte for byte: Claude never sees them
            var trashed: [String] = []
            let twins = await Task.detached { Vault.duplicates(of: files, in: root) }.value   // hashes files, so off the main thread
            for (from, twin) in twins.sorted(by: { $0.key < $1.key }) {
                if let bin = try? Vault.trashDuplicate(from, in: root) { moved.append([from, bin]); trashed.append("\((from as NSString).lastPathComponent) = \(twin)") }
            }
            let rest = files.filter { FileManager.default.fileExists(atPath: $0.path) }
            let dupNote = trashed.isEmpty ? nil : "The app has already moved these exact copies of filed files to .trash, so leave them out: " + trashed.joined(separator: "; ") + "."
            let dupSummary = trashed.isEmpty ? "" : "Moved \(trashed.count) exact duplicate\(trashed.count == 1 ? "" : "s") of already-filed files to .trash. "
            if rest.isEmpty { summary = dupSummary + "Nothing else was waiting." }
            else {
            let given = [advice, dupNote].compactMap { $0 }.joined(separator: "\n\n")
            let plan = await Agent.planSorting(rest, advice: given.isEmpty ? nil : given, root: root)
            if plan.session == nil { ok = false; summary = plan.text; if plan.limited { pauseForLimit() } }
            else if plan.text.hasPrefix("NOTHING:") || (Vault.moves(in: plan.text).isEmpty && plan.text.prefix(240).localizedCaseInsensitiveContains("nothing")) { if trashed.isEmpty { nothing = true } else { summary = plan.text } }
            else if let planSession = plan.session {
                planText = plan.text
                update { $0.plan = plan.text }
                var done: [String] = [], failed: [String] = []
                for m in Vault.moves(in: plan.text) {
                    do { try Vault.perform(m, in: root); done.append("\(m.from) → \(m.to)"); moved.append([m.from, m.to]) } catch { failed.append(error.localizedDescription) }
                }
                let r = await Agent.approveFiling(session: planSession, moved: done, root: root)
                ok = r.session != nil; session = r.session
                summary = (ok ? "Filed \(done.count) file\(done.count == 1 ? "" : "s")" : "Didn’t finish") + (failed.isEmpty ? "" : "; \(failed.count) not moved") + ". " + r.text
                if r.limited { pauseForLimit() }
            }
            if ok && !nothing { summary = dupSummary + summary }
            }
        case .work(let n, let w, _, _):
            work = w
            let noteURL = n.id
            let extra = await Task.detached {   // PDF and Office text extraction is slow, so off the main thread
                let text = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""
                return Vault.rawItems(text, "resources").prefix(2).map { raw in
                    String(Agent.pdfText(root.appending(path: Vault.unlink(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))).components(separatedBy: "|")[0])).prefix(30_000))
                }.joined()
            }.value
            let team = Agent.teamLog(activity), r = await Agent.doWork(role: w.role, task: w.task, note: n.id, extra: extra + (team.isEmpty ? "" : "\n\n" + team), advice: advice, creating: w.creates, sections: w.sections, feedback: nil, session: nil, root: root)
            if r.session == nil { ok = false; summary = r.text; if r.limited { pauseForLimit() } }
            else if r.text.hasPrefix("NOTHING:") { nothing = true } else { summary = r.text; session = r.session }
        case .learn: return
        }
        thinking.remove(agent)
        if nothing { inbox.removeAll { $0.id == id }; saveInbox(); markHandled(item.key); return }
        guard ok else {
            update { $0.state = .failed; $0.result = summary }
            markHandled(item.key); startCooling(agent, rel0 ?? item.key)
            log(agent, "Didn’t finish: \(item.title)")
            return
        }

        // review: the Manager checks the result, on this Mac. Problems send it back once; if it still fails, the job is undone.
        update { $0.state = .checking }
        thinking.insert(Agent.manager.id)
        reload()
        var verdict = await reviewJob(item, work: work, started: started, before: before, moved: moved, root: root)
        if (!verdict.ok || !verdict.flags.isEmpty), item.kind == .work, case .work(let n, let w, _, _) = job, let s = session {
            let why = (verdict.problems + verdict.flags).map { "- " + $0 }.joined(separator: "\n")
            log(Agent.manager.id, "Sent “\(item.title)” back to \(Agent.role(agent).name): \(verdict.problems.first ?? verdict.flags.first ?? "")")
            update { $0.state = .working }; thinking.remove(Agent.manager.id); thinking.insert(agent)
            let r = await Agent.doWork(role: w.role, task: w.task, note: n.id, extra: "", advice: advice, creating: w.creates, sections: w.sections, feedback: why, session: s, root: root)
            thinking.remove(agent); thinking.insert(Agent.manager.id)
            update { $0.state = .checking }
            if r.session != nil { summary = r.text; reload(); verdict = await reviewJob(item, work: work, started: started, before: before, moved: moved, root: root) }
            else { verdict.problems.append("the retry didn't finish") }
        }
        thinking.remove(Agent.manager.id)

        // what changed, so one tap can put it back, and a copy of what the agent wrote, so it can learn from your later edits
        reload()
        var undo = InboxItem.Undo(moves: moved), outputs: [String: String] = [:]
        if item.kind == .work, let rel = rel0, let prev = prevStatus { undo.statuses[rel] = prev }
        let body = { (t: String) in t.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("status:") }.joined(separator: "\n") }
        let dir = InboxItem.outputDir(id)
        let currentRels = Set(notes.map { Vault.rel($0.id) })
        // a filing job edits existing notes (course, project, calendar ticks): the ones it names are its own, so undo puts them back; a note you edited meanwhile isn't named and is left alone
        let said = planText + summary
        var edited: Set<String> = []
        if item.kind == .filing {
            let changed = await Review.touchedInBackground(since: started, root: root)
            edited = Set(changed.filter { said.contains($0) || said.contains(((($0 as NSString).lastPathComponent) as NSString).deletingPathExtension) })
        }
        for rel in before.subtracting(currentRels) {
            let url = root.appending(path: rel)
            if let v = Vault.history(url).first { undo.restore.append(rel); undo.snapshots = (undo.snapshots ?? [:]).merging([rel: v.url.lastPathComponent]) { $1 } }
        }
        for n in notes {
            let rel = Vault.rel(n.id)
            if !before.contains(rel) { undo.created.append(rel) }
            else if item.paths.contains(rel) || edited.contains(rel) || item.scope.map({ rel.hasPrefix($0 + "/") }) == true, let v = Vault.history(n.id).first, let old = try? String(contentsOf: v.url, encoding: .utf8), let now = try? String(contentsOf: n.id, encoding: .utf8), body(old) != body(now) { undo.restore.append(rel); undo.snapshots = (undo.snapshots ?? [:]).merging([rel: v.url.lastPathComponent]) { $1 } }
            else { continue }
            if item.kind == .work, let text = try? String(contentsOf: n.id, encoding: .utf8) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = "\(outputs.count).md"
                if (try? text.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)) != nil { outputs[rel] = name }
            }
        }
        let hasUndo = !(undo.restore.isEmpty && undo.created.isEmpty && undo.moves.isEmpty)
        update { $0.undo = hasUndo ? undo : nil; $0.outputs = outputs.isEmpty ? nil : outputs; $0.result = summary; $0.session = session }
        startCooling(agent, rel0 ?? item.key); markHandled(item.key)

        if !verdict.ok {
            let reasons = verdict.problems.joined(separator: "; ")
            update { $0.verdict = "Rejected: " + reasons }
            if hasUndo { undoJob(id) }
            update { $0.state = .rejected }
            recordReview(agent, passed: false)
            log(Agent.manager.id, "Rejected “\(item.title)” and put it back: \(reasons)")
        } else {
            let line = summary.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -*•#")) }.first { !$0.isEmpty }.map { String($0.prefix(150)) }
            let note = verdict.flags.isEmpty ? "checked" : "flagged: " + verdict.flags.joined(separator: "; ")
            update { $0.state = .done; $0.verdict = verdict.flags.isEmpty ? "Checked: fine" : "Flagged: " + verdict.flags.joined(separator: "; ") }
            recordReview(agent, passed: true)
            log(agent, "\(item.title)\(line.map { " — " + $0 } ?? "") · Manager \(note)" + (advice == nil ? "" : " · \(courses.map { Agent.role($0).name }.joined(separator: ", ")) advised"), undo: hasUndo ? id : nil)
            scheduleAutopilot(after: 3)   // what it just did may be what the next helper was waiting for (Sorter files slides → Scribe; Planner fills a brief → Writer)
        }
    }

    func pauseForLimit() { UserDefaults.standard.set(Date.now.addingTimeInterval(3600), forKey: "autopilotPausedUntil"); log(Agent.manager.id, "Claude's usage limit was reached, so I'm waiting an hour.") }

    /// The Manager's review, entirely on this Mac apart from the on-device model: stayed inside its scope, left Oscar's lines and the template alone, links open, numbers agree.
    func reviewJob(_ item: InboxItem, work: AgentWork?, started: Date, before: Set<String>, moved: [[String]], root: URL) async -> Review.Verdict {
        var v = Review.Verdict()
        let touched = await Review.touchedInBackground(since: started, root: root)
        let courseSet = Set(Vault.courses.keys)
        if item.kind == .filing {
            // the Sorter's own file says to tick Calendar Sync when it files something, so that one is allowed
            let outside = touched.filter { t in t.hasSuffix(".md") && t != CalendarSync.file && !Vault.folders.contains { t.hasPrefix(Vault.dir($0, root: root) + "/") } }
            if !outside.isEmpty { v.problems.append("it changed notes outside your note folders: \(outside.prefix(2).joined(separator: ", "))") }
            for pair in moved where pair.count == 2 && !FileManager.default.fileExists(atPath: root.appending(path: Vault.real(pair[1], root: root)).path) { v.problems.append("\(pair[1]) isn't where it was filed") }
            // what it wrote: new notes are held to their template, and a link to a Resources file that isn't there is flagged (the Sorter can't check its own writes)
            let created = Set(notes.map { Vault.rel($0.id) }.filter { !before.contains($0) })
            for new in created {
                guard let text = try? String(contentsOf: root.appending(path: new), encoding: .utf8) else { continue }
                let folder = Vault.logical((new as NSString).deletingLastPathComponent)
                let r = Review.checkNew(rel: new, text: text, template: Sections.template(forFolder: folder, root: root), folder: folder, courses: courseSet)
                v.problems += r.problems.map { "\((new as NSString).lastPathComponent): " + $0 }; v.flags += r.flags
            }
            for t in touched where t.hasSuffix(".md") {
                let url = root.appending(path: t)
                guard let after = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let old = created.contains(t) ? "" : (Vault.history(url).first.flatMap { try? String(contentsOf: $0.url, encoding: .utf8) } ?? "")
                let gone = Review.missingFiles(in: after, before: old, root: root)
                if !gone.isEmpty { v.flags.append("\((t as NSString).lastPathComponent) links to \(gone.count) file\(gone.count == 1 ? "" : "s") that isn't there (first: \(gone[0]))") }
            }
            return v
        }
        guard let rel = item.paths.first else { return v }
        let created = notes.map { Vault.rel($0.id) }.filter { !before.contains($0) }
        var allowed: Set<String> = [rel]
        if let scope = item.scope { allowed.formUnion(touched.filter { $0.hasPrefix(scope + "/") && $0.hasSuffix(".md") }) }
        // other notes may have changed because you were editing them; only the agents' own files and the templates are certainly not yours
        let stray = touched.filter { !allowed.contains($0) && ($0.hasPrefix("Agents/") || $0.hasPrefix("Templates/")) }
        if !stray.isEmpty { v.problems.append("it changed files it wasn't given: \(stray.prefix(3).joined(separator: ", "))") }
        if item.scope != nil && created.count > 1 { v.problems.append("it created \(created.count) notes; the job allows one") }
        if item.scope != nil && created.isEmpty && item.agent != "librarian" { v.problems.append("it was meant to create a note and didn't") }
        // the edited note
        if item.scope == nil {
            let url = root.appending(path: rel)
            if let after = try? String(contentsOf: url, encoding: .utf8) {
                if let prev = Vault.history(url).first, let beforeText = try? String(contentsOf: prev.url, encoding: .utf8) {
                    let folder = Vault.logical((rel as NSString).deletingLastPathComponent)
                    let r = Review.checkEdit(rel: rel, before: beforeText, after: after, sections: work?.sections, template: Sections.template(forFolder: folder, root: root))
                    v.problems += r.problems; v.flags += r.flags
                    if item.agent == "scribe", !after.lowercased().contains("slide"), !Vault.rawItems(after, "resources").isEmpty { v.flags.append("the write-up cites no slide numbers") }
                    if ["librarian", "researcher"].contains(item.agent) { v.problems += await Review.deadLinks(in: after.replacingOccurrences(of: beforeText, with: "")) }
                    if item.agent == "writer", let w = work?.sections {   // is what it wrote a plan, not finished prose?
                        for s in w.prefix(3) { if let b = Sections.body(s, in: after), b.count > 200, let d = await Review.judge("Is this an outline, plan or list of evidence rather than finished paragraphs written for submission?", of: b) { v.flags.append("“\(s)”: \(d)"); break } }
                    }
                    if work?.verify == true {   // the Analyst: a second, independent solution has to agree
                        let second = await Agent.solveIndependently(note: url, root: root)
                        let cmp = Review.compare(first: Review.answers(in: after), second: second.text)
                        v.problems += cmp.problems; v.flags += cmp.flags
                    }
                }
            } else {
                v.problems.append("the note was deleted or cannot be read")
            }
        }
        // new notes
        for new in created where allowed.contains(new) || item.scope != nil {
            guard let text = try? String(contentsOf: root.appending(path: new), encoding: .utf8) else { continue }
            let folder = Vault.logical((new as NSString).deletingLastPathComponent)
            let r = Review.checkNew(rel: new, text: text, template: Sections.template(forFolder: folder, root: root), folder: folder, courses: courseSet)
            v.problems += r.problems; v.flags += r.flags
            if folder == "Research" { let rr = await Review.checkResearch(text); v.problems += rr.problems; v.flags += rr.flags }
            else if ["librarian", "researcher"].contains(item.agent) { v.problems += await Review.deadLinks(in: text) }
        }
        return v
    }

    // MARK: Putting it back
    func canUndo(_ id: UUID) -> Bool { inbox.contains { $0.id == id && $0.state == .done && $0.undo != nil } }
    func undoJob(_ id: UUID) {
        guard let i = inbox.firstIndex(where: { $0.id == id }), let u = inbox[i].undo else { return }
        let fm = FileManager.default, root = Vault.root
        for rel in u.restore {   // the text from before the job; what is there now is kept in history too
            let url = root.appending(path: rel)
            let wanted = u.snapshots?[rel].map { Vault.historyDir(url).appending(path: $0) }
            if let src = wanted ?? Vault.history(url).first?.url, let text = try? String(contentsOf: src, encoding: .utf8) { try? Vault.write(text, to: url) }
        }
        reload()
        for (rel, st) in u.statuses {   // the restored text was taken while the helper had the note: give it back its own status
            if let n = notes.first(where: { Vault.rel($0.id) == rel }), n.state == .agent { try? Vault.setStatus(n, to: st.isEmpty ? TaskState.notStarted.rawValue : st) }
        }
        let bin = root.appending(path: ".trash/Undone-" + Date.now.formatted(.iso8601.year().month().day()))
        for rel in u.created {
            let src = root.appending(path: rel)
            try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
            var dst = bin.appending(path: src.lastPathComponent)   // a note undone twice in a day mustn't fail on the name and stay put
            if fm.fileExists(atPath: dst.path) { dst = bin.appending(path: UUID().uuidString.prefix(6) + " " + src.lastPathComponent) }
            try? fm.moveItem(at: src, to: dst)
        }
        for m in u.moves where m.count == 2 {   // back to where it was
            // moves are recorded with the short folder names the Sorter writes ("Resources/TEM/…"); the file is where `Vault.real` puts it ("Files/Resources/TEM/…")
            let from = root.appending(path: Vault.real(m[0], root: root)), to = root.appending(path: Vault.real(m[1], root: root))
            guard !fm.fileExists(atPath: from.path), fm.fileExists(atPath: to.path) else { continue }
            try? fm.createDirectory(at: from.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: to, to: from)
        }
        inbox[i].undo = nil; inbox[i].outputs = nil; inbox[i].result = (inbox[i].result ?? "") + "\n(Undone.)"
        saveInbox(); log(inbox[i].agent, "Undid: \(inbox[i].title)"); reload()
    }
    /// The last finished job that can still be put back (for the Manager menu).
    var lastUndoable: InboxItem? { inbox.last { $0.state == .done && $0.undo != nil } }

    // MARK: Learning from your edits
    nonisolated static func lineDiff(_ a: String, _ b: String) -> String {
        let x = a.components(separatedBy: "\n"), y = b.components(separatedBy: "\n")
        var out: [(Int, String)] = []
        for c in y.difference(from: x) {
            switch c { case .remove(let o, let l, _): out.append((o * 2, "- " + l)); case .insert(let o, let l, _): out.append((o * 2 + 1, "+ " + l)) }
        }
        return out.sorted { $0.0 < $1.0 }.prefix(160).map(\.1).joined(separator: "\n")
    }
    /// One run, no review: the agent reads what you changed and may add a few rules to its own file. Old text stays in history.
    func runLearn(_ item: InboxItem, _ rel: String, _ key: String) async {
        markHandled(key)   // whatever comes of it, the same edit isn't looked at twice
        guard let file = item.outputs?[rel], let was = try? String(contentsOf: InboxItem.outputDir(item.id).appending(path: file), encoding: .utf8),
              let now = try? String(contentsOf: Vault.root.appending(path: rel), encoding: .utf8) else { return }
        let diff = Self.lineDiff(was, now), mine = Agent.file(item.agent)
        guard !diff.isEmpty else { return }
        spendJob(item.agent)
        agentBusy = true; thinking.insert(item.agent)
        defer { agentBusy = false; thinking.remove(item.agent) }
        try? Vault.snapshot(Vault.root.appending(path: mine))
        let r = await Agent.run("""
        Earlier you wrote text into `\(rel)`. Oscar has since edited it. This is a line diff (`-` is something you wrote that he removed or changed, `+` is what he put instead):
        \(diff)
        Decide whether his edits show a lasting preference about how you should work (tone, length, structure, what to include or leave out). Content fixes that only apply to this note are not rules.
        If there is no lasting preference, reply with one line starting `NOTHING:` and stop.
        Otherwise add at most 3 short, general, imperative rules to your own file `\(mine)` under the heading `## Learned from Oscar's edits` (add the heading at the end if it is missing). Don't repeat a rule that is already there, merge similar ones, and keep the section under 12 rules. Edit only that file. Reply with the rules you added, one per line.
        """, system: Agent.systemPrompt(Agent.role(item.agent)), session: nil, canEdit: false, root: Vault.root, tier: .standard, writes: [Agent.scope(file: mine)])
        guard r.session != nil else { if r.limited { pauseForLimit() }; return }
        if !r.text.hasPrefix("NOTHING") {
            let rules = r.text.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -*•")) }.filter { !$0.isEmpty }.prefix(3).joined(separator: "; ")
            log(item.agent, "Learned from your edits to \((rel as NSString).lastPathComponent): \(rules)")
        }
        reload()
    }
}
