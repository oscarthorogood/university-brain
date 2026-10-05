import SwiftUI
import AppKit

extension Color {
    static let courseColors: [String: Color] = [
        "MSOA": Color(light: 0x636C9E, dark: 0x9AA2D6),
        "SM": Color(light: 0x3F7B77, dark: 0x74B7B2),
        "TEM": Color(light: 0xA0603F, dark: 0xD99573),
    ]
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Tokens (from the States & tokens board)
extension Color {
    static let appBG = Color(light: 0xEEEDE9, dark: 0x141311)
    static let panel = Color(light: 0xF9F8F6, dark: 0x1B1A18)
    static let frame = Color(light: 0xF6F5F2, dark: 0x1E1D1B)
    static let portrait = Color(light: 0xF4F3EF, dark: 0x2C2A27)
    static let card = Color(light: 0xFFFFFF, dark: 0x232220)
    static let line = Color(light: 0xE7E4DC, dark: 0x34322E)
    static let ink = Color(light: 0x141413, dark: 0xF2F0EA)
    static let ink2 = Color(light: 0x6E6B62, dark: 0xA8A49A)
    static let warnFG = Color(light: 0x8F4A00, dark: 0xF0B366)
    static let warnBG = Color(light: 0xFDF1E2, dark: 0x3A2A14)
    static let redFG = Color(light: 0xB42318, dark: 0xFF8A7A)
    static let redBG = Color(light: 0xFBE9E7, dark: 0x3D1C18)
    static func course(_ c: String?) -> Color { c.flatMap { courseColors[$0] } ?? .ink2.opacity(0.4) }
}

enum Page: Hashable { case newTab, messages, inbox, overview, week, month, semester, sortNow, course(String), folder(String), unsorted(URL), search, agent(String), note(URL), file(URL), tags }

extension Page {
    /// Pages that show a note (and so draw their own document pane and inspector pane).
    var isNote: Bool {
        switch self {
        case .note: true
        case .unsorted(let u): u.pathExtension == "md"
        default: false
        }
    }
}

struct Message: Identifiable, Codable { var id = UUID(); let fromAgent: Bool; let text: String; var time = Date.now }

extension Note {
    /// `when` for code that has already filtered to dated notes: a note with no date sorts last, where `when!` would have crashed.
    var whenOrFar: Date { when ?? .distantFuture }
    /// Short, readable name: drops the course prefix the vault's naming convention adds.
    var display: String {
        var t = title
        for (full, _) in Vault.courses where t.hasPrefix(full) { t = String(t.dropFirst(full.count)).trimmingCharacters(in: .whitespaces) }
        for kind in ["- Project - ", "- Essay - ", "- Revision - "] + Study.kinds.map({ "- \($0.noun) - " }) where t.hasPrefix(kind) { t = String(t.dropFirst(kind.count)) }
        if ["Lectures", "Tutorials"].contains(folder), let r = t.range(of: " - ") {
            let code = String(t[..<r.lowerBound]), topic = String(t[r.upperBound...])
            let generic = topic.range(of: #"^(Lecture|Seminar|Tutorial) \d+$"#, options: .regularExpression) != nil
            t = [course, code].compactMap { $0 }.joined(separator: " ") + (generic ? "" : " · " + topic)
        }
        return t
    }
    var kind: String {
        switch folder { case "TaskNotes/Tasks": "Task"; case "Lectures": "Lecture"; case "Tutorials": "Tutorial"; case "Readings": "Reading"; case "Essays": "Essay"; case "Projects": "Project"; default: folder }
    }
}
enum Tab: String, CaseIterable {
    case classes = "Lectures & Tutorials", readings = "Readings", assignments = "Assignments"
    /// Each list gets its own pastel, like the coloured documents in Craft.
    var tint: Color {
        switch self {
        case .classes: Color(light: 0x7BA7E8, dark: 0x6B93D6)
        case .readings: Color(light: 0x7CC49A, dark: 0x5FAE82)
        case .assignments: Color(light: 0xF08E78, dark: 0xD9755F)
        }
    }
}

@main
struct SecondBrainApp: App {
    init() {
        if CommandLine.arguments.contains("--check") { Check.run(); exit(0) }
        // `--sync-calendar`: fetches the feeds and rewrites Calendar Sync.md (use SECOND_BRAIN_VAULT to test on a copy).
        if CommandLine.arguments.contains("--sync-calendar") {
            let done = DispatchSemaphore(value: 0)
            Task.detached { print(await CalendarSync.sync()); done.signal() }
            done.wait(); exit(0)
        }
        // `--sync-zotero`: one two-way Zotero sync (use SECOND_BRAIN_VAULT for a copy; ZOTERO_API_BASE=http://localhost:23119/api reads Zotero’s local API, read-only).
        if CommandLine.arguments.contains("--sync-zotero") {
            let done = DispatchSemaphore(value: 0)
            Task.detached { print(await Zotero.sync().text); done.signal() }
            done.wait(); exit(0)
        }
        // `--scan`: prints the jobs the Manager would hand out right now, best first (nothing is run).
        if CommandLine.arguments.contains("--scan") {
            MainActor.assumeIsolated {
                let jobs = Store().scan()
                print(jobs.isEmpty ? "nothing to hand out" : jobs.map { "\(Int($0.score)) · \($0.job.label)" }.joined(separator: "\n")); exit(0)
            }
        }
        // `--route "<request>"`: prints which agent the Manager would pick, at what effort and why (nothing is run).
        if let i = CommandLine.arguments.firstIndex(of: "--route"), i + 1 < CommandLine.arguments.count {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                let r = await Manager.decide(CommandLine.arguments[i + 1])
                print("\(r.agent) · \(r.tier.rawValue) · \(r.by) · \(r.reason)"); done.signal()
            }
            done.wait(); exit(0)
        }
        // `--run-top`: runs the single best job the Manager would pick, through the real consult, work and review (use SECOND_BRAIN_VAULT for a copy).
        if CommandLine.arguments.contains("--run-top") {
            let flagDone = CheckFlag()
            Task { @MainActor in
                let st = Store()
                guard let top = st.scan().first else { print("nothing to hand out"); flagDone.done = true; return }
                print("running: \(top.job.label)")
                await st.manualJob(top.job)
                if let item = st.activeJobs.first ?? st.inbox.last { print("\(item.state.rawValue) · \(item.title)\n\(item.verdict ?? "")\n\(item.advice.map { "Course agent: " + $0 + "\n" } ?? "")\(item.result ?? "")") }
                for a in st.activity.prefix(6) { print("log: " + a.text) }
                flagDone.done = true
            }
            while !flagDone.done { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
            exit(0)
        }
        // `--work <note path in vault>` and `--file <path in vault>`: run the real consult, work and review pipeline once, headlessly (use SECOND_BRAIN_VAULT for a copy).
        for (flag, isFile) in [("--work", false), ("--file", true)] {
            guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { continue }
            let url = Vault.root.appending(path: CommandLine.arguments[i + 1]), flagDone = CheckFlag()
            Task { @MainActor in
                let st = Store(), key = "headless:" + UUID().uuidString
                if isFile { await st.manualJob(.sorting([url], key: key)) }
                else if let n = st.notes.first(where: { $0.id.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }), let w = AgentWork.forNote(n) { await st.manualJob(.work(n, w, key: key, why: "run from the command line")) }
                else { print("nothing for an agent to do on that note") }
                if let item = st.inbox.last(where: { $0.key == key }) { print("\(item.state.rawValue) · \(item.title)\n\(item.verdict ?? "")\n\(item.advice.map { "Course agent: " + $0 + "\n" } ?? "")\(item.result ?? "")") }
                flagDone.done = true
            }
            while !flagDone.done { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
        if let a = ProcessInfo.processInfo.environment["SB_APPEARANCE"] { NSApplication.shared.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua) }
        NSApplication.shared.activate()
    }
    @State private var store = Store()
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @AppStorage("menuBarOn") private var menuBarOn = false
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("University Brain", id: "main") {
            ContentView().frame(minWidth: 840, minHeight: 540).environment(store)
                // An empty, invisible toolbar makes the title bar taller, which drops the
                // window buttons down into the sidebar's glass instead of onto its edge.
                .toolbar { ToolbarItem(placement: .navigation) { Color.clear.frame(width: 1, height: 1) }.sharedBackgroundVisibility(.hidden) }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.newNote() }.keyboardShortcut("n")
                Button("New Tab") { store.newTab() }.keyboardShortcut("t")
                Button("Add File…") { store.addFile() }.keyboardShortcut("o")
                Button("New Note from Template…") { store.newStructured = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Quickly…") { store.quickOpen = true }.keyboardShortcut("p")
                Button("Add Link…") { store.addLink() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("New Voice Memo…") { store.voiceMemo = true }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Sync Calendar") { Task { store.log("planner", await store.syncCalendar()) } }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { store.closeCurrentTab() }.keyboardShortcut("w")
            }
            CommandGroup(before: .toolbar) {
                Button(collapsed ? "Show Sidebar" : "Hide Sidebar") { withAnimation(.spring(duration: 0.45, bounce: 0.15)) { collapsed.toggle() } }
                    .keyboardShortcut("s", modifiers: [.control, .command])
            }
            CommandMenu("Go") {
                Button("Back") { store.goBack() }.keyboardShortcut("[").disabled(!store.canGoBack)
                Button("Home") { store.page = .overview }.keyboardShortcut("1")
                Button("Week") { store.page = .week }.keyboardShortcut("2")
                Button("Month") { store.page = .month }.keyboardShortcut("3")
                Button("Tags") { store.page = .tags }.keyboardShortcut("4")
                Divider()
                ForEach(Array(Vault.courses.values.sorted()), id: \.self) { c in Button(c == "SM" ? "Strategy" : c) { store.page = .course(c) } }
                Divider()
                Button(Agent.manager.name) { store.page = .agent(Agent.manager.id) }.keyboardShortcut("m", modifiers: [.command, .option])
                ForEach(Array(Agent.roles.enumerated()), id: \.1.id) { i, r in
                    Button(r.name) { store.page = .agent(r.id) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                }
                Divider()
                Button("Reload Vault") { store.reload() }.keyboardShortcut("r")
            }
        }
        MenuBarExtra(isInserted: $menuBarOn) {
            Button("Open University Brain") { NSApp.activate(); openWindow(id: "main") }
            if let job = store.activeJobs.first { Text("\(Agent.role(job.agent).name): \(job.title)") } else { Text(store.blockedReason() ?? "The Manager is idle") }
            if store.pausedUntil == nil { Button("Pause the Manager") { store.pause(for: nil) } } else { Button("Resume the Manager") { store.resume() } }
            Divider()
            Button("Quit University Brain") { NSApp.terminate(nil) }
        } label: { Image(systemName: store.activeJobs.isEmpty ? "books.vertical" : "books.vertical.fill") }
        Settings { SettingsView().environment(store) }
    }
}

@MainActor @Observable final class Store {
    var notes = Vault.load()
    var unsorted = Vault.unsorted()
    /// Every open tab and which one is showing. Pages are opened in the current tab (`page = …`), or in a new one with `newTab(_:)`.
    var tabs: [PageTab] = [PageTab(page: .overview)]
    var activeIndex = 0
    /// The page the current tab shows. Moving to another page keeps the old one for Back.
    var page: Page {
        get { tabs.indices.contains(activeIndex) ? tabs[activeIndex].page : .overview }
        set {
            guard tabs.indices.contains(activeIndex), tabs[activeIndex].page != newValue else { return }
            tabs[activeIndex].back = Array((tabs[activeIndex].back + [tabs[activeIndex].page]).suffix(50))
            tabs[activeIndex].page = newValue
            visited(newValue)
        }
    }
    /// Notes opened lately, newest first (the New Tab page lists them).
    /// Notes of an app (a quiz, a deck…) that are open as text for editing, rather than as the app's own page.
    var editingApps: Set<URL> = []
    var recentNotes: [URL] = (UserDefaults.standard.stringArray(forKey: "recentNotes") ?? []).map { URL(fileURLWithPath: $0) }
    func visited(_ p: Page) {
        switch p {
        case .agent(let id): touchAgent(id)
        case .note(let u), .unsorted(let u) where u.pathExtension == "md":
            recentNotes = Array(([u] + recentNotes.filter { $0 != u }).prefix(10))
            UserDefaults.standard.set(recentNotes.map(\.path), forKey: "recentNotes")
        default: break
        }
    }
    /// Agents in the order they were last opened or asked, newest first (the dock shows the top three).
    var recentAgents = UserDefaults.standard.stringArray(forKey: "recentAgents") ?? []
    func touchAgent(_ id: String) {
        recentAgents = ([id] + recentAgents.filter { $0 != id }).prefix(8).map { $0 }
        UserDefaults.standard.set(recentAgents, forKey: "recentAgents")
    }
    var filter: String? = nil        // course filter on overview
    var error: String?

    var query = ""
    var quickOpen = false
    // Autopilot: agents look for work and prepare it in the inbox (see ManagerScan.swift)
    var inbox: [InboxItem] = InboxItem.load()
    var autopilotOn = UserDefaults.standard.object(forKey: "autopilotOn") as? Bool ?? true
    @ObservationIgnored var handled = Set(UserDefaults.standard.stringArray(forKey: "autopilotHandled") ?? [])
    @ObservationIgnored var agentBusy = false
    @ObservationIgnored var tickRunning = false   // one autopilot tick at a time (a tick can outlive the timer that started it)
    @ObservationIgnored var manualClaims = Set<String>()   // notes an open "plan this" sheet has marked Agent In Progress
    @ObservationIgnored var autopilotTimer: Task<Void, Never>?
    var newStructured = false
    var voiceMemo = false
    var zoteroSyncing = false
    var newKind = NoteKind.lecture
    var newCourse: String?
    @ObservationIgnored var bodyCache: (rev: Int, bodies: [URL: String], backlinks: [String: [Note]])?
    /// Chats and each agent's Claude session survive a relaunch (they used to vanish, and every agent forgot the conversation).
    var chats: [String: [Message]] = Store.savedChats.chats { didSet { saveChats() } }
    var thinking: Set<String> = []
    /// What an agent has written so far of the answer it is still working on, for its chat to show growing.
    var streaming: [String: String] = [:]
    @ObservationIgnored private var chatTasks: [String: Task<Void, Never>] = [:]
    /// Stops the agent working on a chat reply: the process ends and the chat says so.
    func stopChat(_ code: String) { chatTasks[code]?.cancel() }
    @ObservationIgnored private var sessions: [String: String] = Store.savedChats.sessions
    private struct SavedChats: Codable { var chats: [String: [Message]] = [:]; var sessions: [String: String] = [:] }
    private static var chatFile: URL { Support.dir.appending(path: "chats.json") }
    private static var savedChats: SavedChats { (try? JSONDecoder().decode(SavedChats.self, from: Data(contentsOf: chatFile))) ?? SavedChats() }
    private func saveChats() {
        try? FileManager.default.createDirectory(at: Self.chatFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(SavedChats(chats: chats.mapValues { Array($0.suffix(200)) }, sessions: sessions)).write(to: Self.chatFile, options: .atomic)
    }
    /// Every request gets its effort from the Manager. Asking the Manager itself lets it pick the agent too.
    func ask(_ code: String, _ text: String, tier: Manager.Tier? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking.contains(code) else { return }
        if code == Agent.manager.id { dispatch(text, tier: tier) } else { send(code, text, tier: tier ?? Manager.tier(text, role: code)) }
    }
    /// The last few turns of the Manager's chat, so the agent it hands a follow-up to knows what "that" and "these" mean.
    private func recentManagerChat() -> String {
        (chats[Agent.manager.id] ?? []).filter { !$0.text.hasPrefix("→") }.dropLast().suffix(8)
            .map { ($0.fromAgent ? "" : "Oscar: ") + String($0.text.prefix(600)) }.joined(separator: "\n\n")
    }
    /// One agent answers in its own chat (and in the Manager's chat when the Manager sent it).
    private func converse(_ code: String, shown: String, prompt: String, tier: Manager.Tier, mirror: String?) async -> Agent.Reply {
        chats[code, default: []].append(Message(fromAgent: false, text: shown))
        thinking.insert(code)
        let team = Agent.teamLog(activity)
        let reply = await Agent.run(team.isEmpty ? prompt : prompt + "\n\n" + team, system: Agent.systemPrompt(Agent.role(code)), session: sessions[code], canEdit: false, root: Vault.root, tier: tier, writes: Agent.writeScopes(code), web: ["librarian", "researcher"].contains(code),
                                    onText: { [weak self] text in
                                        Task { @MainActor in
                                            guard let self, self.thinking.contains(code) else { return }   // a late piece after the answer is in is ignored
                                            self.streaming[code] = text
                                            if let m = mirror, self.thinking.contains(m) { self.streaming[m] = "**\(Agent.role(code).name)**\n\n" + text }
                                        }
                                    })
        streaming[code] = nil
        if let m = mirror { streaming[m] = nil }
        if let s = reply.session { sessions[code] = s }
        chats[code, default: []].append(Message(fromAgent: true, text: reply.text))
        if let m = mirror { chats[m, default: []].append(Message(fromAgent: true, text: "**\(Agent.role(code).name)**\n\n" + reply.text)) }
        thinking.remove(code)
        log(code, reply.session == nil ? "Couldn’t answer “\(shown.prefix(60))”" : "Answered “\(shown.prefix(60))”")
        return reply
    }
    private func send(_ code: String, _ text: String, tier: Manager.Tier) {
        thinking.insert(code)
        chatTasks[code] = Task { [weak self] in
            guard let self else { return }
            _ = await converse(code, shown: text, prompt: text, tier: tier, mirror: nil)
            chatTasks[code] = nil
        }
    }
    /// The Manager's chat: one agent, or a team working one after another. Each stage gets what the earlier ones handed over, and a course agent advises first.
    private func dispatch(_ text: String, tier: Manager.Tier? = nil) {
        let m = Agent.manager.id
        chats[m, default: []].append(Message(fromAgent: false, text: text))
        thinking.insert(m)
        chatTasks[m] = Task { [weak self] in
            guard let self else { return }
            defer { chatTasks[m] = nil }
            let earlier = recentManagerChat()
            let previous = chats[m]?.last { $0.fromAgent && $0.text.hasPrefix("**") }.flatMap { msg in Agent.all.first { msg.text.hasPrefix("**\($0.name)**") }?.id }
            var steps = Manager.chain(text) ?? []
            if steps.isEmpty { steps = [await Manager.decide(text, previous: previous)] }
            let names = steps.map { Agent.role($0.agent).name }
            if let busy = steps.first(where: { thinking.contains($0.agent) }) {
                chats[m, default: []].append(Message(fromAgent: true, text: "\(Agent.role(busy.agent).name) is busy with something else. Ask again in a moment."))
                thinking.remove(m); return
            }
            let first = steps[0], team = steps.count > 1
            chats[m, default: []].append(Message(fromAgent: true, text: team
                ? "→ **\(names.joined(separator: " → "))** · working together, in that order"
                : "→ **\(names[0])** · \((tier ?? first.tier).rawValue) effort\(tier == nil ? "" : " (your choice)") · \(first.reason)"))
            log(m, "Sent “\(text.prefix(50))” to \(names.joined(separator: ", then ")) (\(first.by))")
            // the course agent says what matters in its course before the work starts
            var advice = ""
            if let c = Manager.course(text.lowercased()), Agent.role(first.agent).course == nil, first.tier != .quick, !thinking.contains(c) {
                if Agent.briefingStale(c, root: Vault.root) { _ = await Agent.refreshBriefing(c, root: Vault.root) }
                if let a = await Agent.consult(c, helper: first.agent, job: text, note: nil, root: Vault.root) {
                    advice = "\n\nThe \(Agent.role(c).name) course agent advises:\n\(a)"
                    chats[m, default: []].append(Message(fromAgent: true, text: "→ **\(Agent.role(c).name)** advised first"))
                }
            }
            var done: [(name: String, text: String)] = []
            for (i, r) in steps.enumerated() {
                if team && i > 0 { chats[m, default: []].append(Message(fromAgent: true, text: "→ **\(names[i])** · stage \(i + 1) of \(steps.count)")) }
                var prompt = text + advice + (earlier.isEmpty ? "" : "\n\n(Earlier in Oscar's chat with the Manager, newest last; it may be what he means:\n\(earlier))")
                if team {
                    prompt += "\n\nThis is a team job: \(names.joined(separator: " then ")), in that order. You are \(names[i]), stage \(i + 1) of \(steps.count)."
                    if !done.isEmpty { prompt += "\nWhat the earlier agents handed over:\n" + done.map { "[\($0.name)]\n\($0.text.prefix(6000))" }.joined(separator: "\n\n") }
                    prompt += i < steps.count - 1
                        ? "\nDo only your stage; don't produce the final result. End with a `Handoff` section giving \(names[i + 1]) exactly what they need: sources actually read (note, PDF page range or URL), the facts, and any gaps."
                        : "\nYou are the last stage: produce the finished result the request asks for from the handed-over material. If something it needed is missing, say so plainly instead of inventing it."
                }
                let reply = await converse(r.agent, shown: team ? "\(text) (stage \(i + 1) of \(steps.count), from the Manager)" : text, prompt: prompt, tier: tier ?? r.tier, mirror: m)
                if reply.session == nil { chats[m, default: []].append(Message(fromAgent: true, text: reply.stopped ? "Stopped." : "\(names[i]) couldn’t finish, so I stopped there.")); break }
                if team, i == steps.count - 1, !done.isEmpty {   // a different agent checks the finished result against what was handed over
                    chats[m, default: []].append(Message(fromAgent: true, text: "→ **Checking** the result against what was handed over"))
                    let problems = await Agent.verify(result: reply.text, handoff: done.map(\.text).joined(separator: "\n\n"), root: Vault.root)
                    chats[m, default: []].append(Message(fromAgent: true, text: problems.map { "**Check found problems**\n\n" + $0 } ?? "→ Checked: every claim traces to what was handed over"))
                }
                done.append((names[i], reply.text))
            }
            thinking.remove(m)
        }
    }
    @ObservationIgnored private var watcher: VaultWatcher?
    var needs: [String: [Need]] = [:]
    var activity: [Activity] = Activity.load()
    init() {
        // a new app version brings its Templates and Agents files into the vault (see AppFiles.swift)
        if let n = AppFiles.installIfNeeded()?.count, n > 0 { log("manager", "Updated \(n) Templates and Agents file\(n == 1 ? "" : "s") in the vault to version \(AppFiles.version.split(separator: "+")[0]).") }
        rewatch(); computeNeeds(); scheduleAutopilot(after: 8)
    }
    func rewatch() {
        watcher = VaultWatcher(path: Vault.root.path) { [weak self] in MainActor.assumeIsolated { self?.reloadInBackground() } }
    }
    func addLink() {
        let alert = NSAlert()
        alert.messageText = "Add a link to Unsorted"
        alert.informativeText = "The sort files it as a reading or reference."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Link"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespaces)), let host = url.host else { return }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { self.error = "Only web links (http or https) can be added."; return }
        let stamp = Date.now.formatted(.iso8601.year().month().day()) + " " + Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).replacingOccurrences(of: ":", with: "")
        let file = Vault.root.appending(path: "Unsorted/Link - \(host) - \(stamp).md")
        do { try "\(url.absoluteString)\n".write(to: file, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        reload()
    }
    var revision = 0
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    /// What the file watcher calls. Reading every note used to happen on the main thread, so each autosave (or Obsidian touching a file) stalled typing;
    /// now the vault is read in the background and applied here, and a newer change cancels an older read that hasn't been applied yet.
    func reloadInBackground() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            // the search index goes with it: opening a note asks for it, and building it there re-read every note on the main thread after each save
            let loaded = await Task.detached(priority: .utility) { () -> (notes: [Note], unsorted: [URL], index: (bodies: [URL: String], backlinks: [String: [Note]])) in
                let notes = Vault.load()
                return (notes, Vault.unsorted(), Store.buildIndex(notes))
            }.value
            guard !Task.isCancelled, let self else { return }
            releaseStaleClaims(); notes = loaded.notes; unsorted = loaded.unsorted; revision += 1
            bodyCache = (revision, loaded.index.bodies, loaded.index.backlinks)
            computeNeeds(); scheduleAutopilot()
        }
    }
    func reload() { releaseStaleClaims(); notes = Vault.load(); unsorted = Vault.unsorted(); computeNeeds(); revision += 1; scheduleAutopilot() }
    var semesterStart: Date { Vault.parseDate("2026-09-21") ?? today }   // Semester 1, which the week numbers count from
    /// The semesters the Semester page can switch between. ponytail: Semester 2's start is a guess (mid-January); correct it here.
    static let semesters = [(name: "Semester 1", start: "2026-09-21"), (name: "Semester 2", start: "2027-01-18")]
    var currentSemester: Int { Self.semesters.lastIndex { (Vault.parseDate($0.start) ?? .distantFuture) <= today } ?? 0 }
    var semesterWeek: Int { (Calendar.current.dateComponents([.day], from: semesterStart, to: today).day ?? 0) / 7 + 1 }
    /// The next things on: classes still to come and open deadlines, soonest first.
    func upcoming(_ n: Int) -> [Note] {
        notes.filter { x in
            guard !x.done, let w = x.when else { return false }
            if ["Lectures", "Tutorials"].contains(x.folder) { return w > .now }
            return ["Essays", "Projects", "TaskNotes/Tasks"].contains(x.folder) && w >= today
        }.sorted { $0.whenOrFar < $1.whenOrFar }.prefix(n).map { $0 }
    }
    func nextDeliverable(_ c: String) -> Note? {
        notes.filter { $0.course == c && ["Essays", "Projects"].contains($0.folder) && !$0.done && ($0.when ?? .distantPast) >= today }.min { $0.whenOrFar < $1.whenOrFar }
    }
    func newNote() {
        let dir = Vault.root.appending(path: "Unsorted")
        let name = "Note " + Date.now.formatted(.iso8601.year().month().day()) + " " + Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let url = dir.appending(path: name.replacingOccurrences(of: ":", with: "") + ".md")
        do { try "".write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription; return }
        reload()
        page = .unsorted(url)
    }
    func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for src in panel.urls {
            let dst = Vault.root.appending(path: "Unsorted").appending(path: src.lastPathComponent)
            do { try FileManager.default.copyItem(at: src, to: dst) } catch { self.error = error.localizedDescription }
        }
        reload()
    }
    var today: Date { Calendar.current.startOfDay(for: .now) }
    func days(_ d: Date) -> Int { Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: d)).day ?? 0 }
    func isCurrentSemester(_ n: Note) -> Bool { (n.when ?? .distantPast) >= Calendar.current.date(byAdding: .month, value: -2, to: today)! }
    func matches(_ n: Note) -> Bool { filter == nil || n.course == filter }

    var todayItems: [Note] {
        notes.filter { n in
            guard let w = n.when, ["Lectures", "Tutorials", "Essays", "Projects", "TaskNotes/Tasks"].contains(n.folder) else { return false }
            return Calendar.current.isDate(w, inSameDayAs: .now) && matches(n)
        }.sorted { $0.whenOrFar < $1.whenOrFar }
    }
    func list(_ tab: Tab) -> [Note] {
        let folders: Set<String> = switch tab {
        case .classes: ["Lectures", "Tutorials"]
        case .readings: ["Readings"]
        case .assignments: ["Essays", "Projects", "TaskNotes/Tasks"]
        }
        return notes.filter { n in
            guard folders.contains(n.folder), !n.done, matches(n), let w = n.when else { return false }
            return tab == .readings ? isCurrentSemester(n) : w >= today
        }.sorted { $0.whenOrFar < $1.whenOrFar }
    }
    func course(_ c: String, _ folders: Set<String>) -> [Note] {
        notes.filter { $0.course == c && folders.contains($0.folder) && isCurrentSemester($0) }.sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }
    }
    func openCount(_ folder: String) -> Int { notes.filter { $0.folder == folder && !$0.done && $0.status != "" && isCurrentSemester($0) }.count }
}

// MARK: - Shell
struct ContentView: View {
    @Environment(Store.self) private var store
    @AppStorage("sidebarCollapsed") private var userCollapsed = false
    @State private var windowWidth: CGFloat = 1440
    /// Narrow windows always get the icon rail on the left, so the main panel keeps room.
    private var collapsed: Bool { userCollapsed || windowWidth < 1000 }
    var body: some View {
        if store.notes.isEmpty && !Vault.exists { missingVault } else { shell }
    }
    var missingVault: some View {
        ContentUnavailableView {
            Label("Can’t find your vault", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Nothing at \(Vault.root.path). Choose the folder that holds Lectures, Readings and Courses.")
        } actions: {
            Button("Choose Folder…") {
                let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                if p.runModal() == .OK, let u = p.url { UserDefaults.standard.set(u.path, forKey: "vaultPath"); store.rewatch(); store.reload() }
            }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.ultraThinMaterial, for: .window)
    }
    var shell: some View {
        VStack(spacing: 12) {
            WindowTabBar()
            HStack(spacing: 12) {
                // One glass pane that resizes; the full sidebar and the icon rail cross-fade inside it.
                ZStack(alignment: .topLeading) {
                    if collapsed { SidebarRail().frame(width: 80).transition(.opacity) }
                    else { Sidebar().frame(width: 240).transition(.opacity) }
                }
                .frame(width: collapsed ? 80 : 240, alignment: .leading)
                .clipShape(.rect(cornerRadius: DS.Radius.pane))
                .modifier(GlassPane())
                if store.page.isNote && store.appKind(for: store.page) == nil {
                    // A note draws its own two panes: the document, and the inspector as a sidebar of its own.
                    MainPanel().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MainPanel().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .modifier(GlassPane())
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
        .containerBackground(for: .window) { WindowBackdrop() }
        .sheet(isPresented: Bindable(store).quickOpen) { QuickOpen() }
        .sheet(isPresented: Bindable(store).newStructured) { NewNoteSheet() }
        .sheet(isPresented: Bindable(store).voiceMemo) { VoiceMemoSheet().environment(store) }
        .alert("Couldn’t save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {} message: { Text(store.error ?? "") }
    }
}

enum Portrait {
    static let hair = ["MSOA": "M26 30c-2-14 10-22 22-18 10-6 22 2 20 16-4-6-12-8-20-6-8-4-16 0-22 8z",
                       "TEM": "M24 34c0-16 12-24 26-22 12 2 20 12 18 26-6-10-14-14-24-12-8 2-14 6-20 8z",
                       "SM": "M22 40c-4-18 8-28 24-28 14 0 24 10 22 24-2 6-6 10-10 12 2-8-2-14-8-18-10 2-20 4-28 10z",
                       "librarian": "M24 36c-2-16 10-26 24-24 14-2 24 8 22 22-8-8-18-10-26-8-8 2-14 6-20 10z M48 4a8 8 0 1 0 0.1 0z",
                       "planner": "M22 34c0-14 12-22 26-22s26 8 26 22c-10-6-20-8-26-8s-16 2-26 8z M18 34h60"]
    static let roleHair = ["sorter": "MSOA", "scribe": "SM", "librarian": "librarian", "planner": "planner", "tutor": "TEM", "writer": "MSOA", "manager": "SM", "researcher": "TEM", "analyst": "SM"]
    static func image(_ c: String) -> Image {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="96" height="112" viewBox="0 0 96 112" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
        <path d="M30 40c0 18 8 30 18 30s18-12 18-30"/><path d="\(hair[roleHair[c] ?? c] ?? hair["MSOA"]!)" fill="#000"/>
        \(["MSOA", "SM", "TEM"].contains(c) ? "<path d=\"M18 17l30-13 30 13-30 13z\" fill=\"#000\"/><path d=\"M35 26v9c8 5 18 5 26 0v-9\"/><path d=\"M76 17v16\"/><circle cx=\"76\" cy=\"36\" r=\"2.5\" fill=\"#000\"/>" : "")
        \(c == "writer" ? "<path d=\"M64 34l9-13\" stroke-width=\"3.5\"/>" : "")
        \(c == "manager" ? "<path d=\"M29 42c-5 0-5 12 0 12M29 54c0 8 8 10 14 8\"/>" : "")
        \(c == "tutor" ? "<circle cx=\"41\" cy=\"46\" r=\"5\"/><circle cx=\"56\" cy=\"46\" r=\"5\"/><path d=\"M46 46h5\"/>" : "")
        <circle cx="41" cy="46" r="1.8" fill="#000"/><circle cx="56" cy="46" r="1.8" fill="#000"/><path d="M48 50l-3 8h5"/><path d="M43 62c3 2 7 2 10 0"/>
        \(c == "researcher" ? "<rect x=\"34\" y=\"41\" width=\"13\" height=\"10\" rx=\"2.5\"/><rect x=\"50\" y=\"41\" width=\"13\" height=\"10\" rx=\"2.5\"/><path d=\"M47 46h3\"/><circle cx=\"66\" cy=\"98\" r=\"7\"/><path d=\"M71 103l8 9\" stroke-width=\"4\"/>" : "")
        \(c == "analyst" ? "<circle cx=\"41\" cy=\"46\" r=\"5\"/><circle cx=\"56\" cy=\"46\" r=\"5\"/><path d=\"M46 46h5\"/><path d=\"M64 96v-8M69 96v-14M74 96v-10\" stroke-width=\"4\"/>" : "")
        <path d="M42 70v10M56 70v10"/><path d="M14 112c2-20 14-32 34-32s32 12 34 32"/><path d="M40 82l8 12 8-12"/></svg>
        """
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return Image(nsImage: img)
    }
}

/// A pane of Liquid Glass: the sidebar, the main panel and the dock.
struct GlassPane: ViewModifier {
    func body(content: Content) -> some View { content.glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.pane)) }
}

// MARK: - Sidebar
/// Everything lives in the left sidebar: pages, courses, then the vault's three groups: Items (what you do), Files (documents and references) and Apps (study tools and research).
struct Sidebar: View {
    @Environment(Store.self) private var store
    @AppStorage("dockHidden") private var hidden = ""
    func entries(_ list: [SideNav.Entry]) -> some View {
        ForEach(list.filter { !SideNav.isHidden($0.name, hidden) }, id: \.name) { e in
            NavRow(icon: e.icon, title: SideNav.label(e.name), page: .folder(e.name), meta: SideNav.openCount(e.name, store))
                .contextMenu { FolderMenu(name: e.name) }
        }
    }
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                TextField("Search", text: $store.query).textFieldStyle(.plain)
                    .onSubmit { if !store.query.isEmpty { store.page = .search } }
                    .onChange(of: store.query) { _, q in if !q.isEmpty { store.page = .search } }
            }
            .font(.system(size: 13)).glassField(height: 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    NavRow(icon: "house", title: "Home", page: .overview)
                    if !SideNav.isHidden(SideNav.pinned, hidden) {
                        NavRow(icon: "tray", title: "Unsorted", page: .inbox, meta: store.unsorted.count, on: { switch store.page { case .inbox, .folder("Unsorted"), .unsorted, .sortNow: true; default: false } }())
                    }
                    NavRow(icon: "message", title: "Messages", page: .messages, on: { switch store.page { case .messages, .agent: true; default: false } }())
                    NavRow(icon: "number", title: "Tags", page: .tags)

                    NavSection("Plan") {
                        NavRow(icon: "chart.bar", title: "Week", page: .week)
                        NavRow(icon: "calendar", title: "Month", page: .month)
                        NavRow(icon: "graduationcap", title: "Semester", page: .semester)
                    }
                    NavSection("Courses") {
                        ForEach([("MSOA", "circle.circle"), ("SM", "hexagon"), ("TEM", "triangle")], id: \.0) { c, shape in
                            NavRow(icon: shape, title: c == "SM" ? "Strategy" : c, page: .course(c), iconTint: .course(c)).contextMenu { CourseMenu(code: c) }
                        }
                    }
                    NavSection("Items") { entries(SideNav.items.filter { $0.name != SideNav.pinned }) }
                    NavSection("Files") { entries(SideNav.files) }
                    NavSection("Apps") { entries(SideNav.apps) }
                }
            }.scrollIndicators(.hidden)

            NoticeButton()
        }
        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Notifications live behind one button at the foot of the sidebar, so the lists above keep the room.
struct NoticeButton: View {
    @Environment(Store.self) private var store
    @State private var open = false
    var body: some View {
        let n = store.notices().count
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: n > 0 ? "bell.badge" : "bell").font(.system(size: 13))
                Text("Notifications").font(.system(size: 13))
                Spacer()
                if n > 0 { Text("\(n)").font(.system(size: 11, weight: .semibold)).monospacedDigit().padding(.horizontal, 7).padding(.vertical, 2).background(Color.ink, in: .capsule).foregroundStyle(Color.card) }
            }
            .foregroundStyle(Color.ink).padding(.horizontal, 14).frame(maxWidth: .infinity).frame(height: DS.Height.control).contentShape(.capsule)
        }
        .buttonStyle(.glassAction(.control))
        .popover(isPresented: $open, arrowEdge: .trailing) { NoticeBox().padding(10).frame(width: 300, height: 380) }
        .accessibilityLabel(n > 0 ? "Notifications, \(n)" : "Notifications")
    }
}

/// The three note groups the sidebar lists, and the folders in each. Page ids are the short folder names (see `Vault.places`).
enum SideNav {
    struct Entry { let name: String; let icon: String }
    /// Unsorted is an Items page too, but it is pinned at the top of the sidebar instead of listed under Items.
    static let pinned = "Unsorted"
    static let items: [Entry] = [.init(name: "Unsorted", icon: "tray"), .init(name: "Lectures", icon: "play.rectangle"), .init(name: "Tutorials", icon: "person.2"), .init(name: "Readings", icon: "book"),
                                 .init(name: "Essays", icon: "doc.text"), .init(name: "Projects", icon: "folder"), .init(name: "Exams", icon: "pencil.and.list.clipboard"),
                                 .init(name: "Tasks", icon: "checkmark.circle")]
    static let files: [Entry] = {
        let documents: [Entry] = [Entry(name: "Resources", icon: "square.stack.3d.up"), Entry(name: "OneDrive", icon: "cloud"), Entry(name: "Zotero", icon: "text.book.closed")]
        let study: [Entry] = Study.kinds.filter { Study.inFiles.contains($0.folder) }.map { Entry(name: $0.folder, icon: $0.icon) }
        return documents + study + [Entry(name: "Research", icon: "magnifyingglass")]
    }()
    static let apps: [Entry] = Study.kinds.filter { !Study.inFiles.contains($0.folder) }.map { Entry(name: $0.folder, icon: $0.icon) }
    static let folders = items + files + apps
    /// Files and Apps pages show a browser instead of a plain list. Every Files page browses its folder on disk; Apps pages list their notes.
    static let grouped = Set((files + apps).map(\.name))
    static func isHidden(_ name: String, _ raw: String) -> Bool { raw.split(separator: ",").contains(Substring(name)) }
    /// Tasks is shown as "Assignments"; its id stays "Tasks" (folder and page names).
    static func label(_ name: String) -> String { name == "Tasks" ? "Assignments" : name }
    /// Notes still to do in a folder; the document folders (Resources, OneDrive, Zotero) have none.
    @MainActor static func openCount(_ name: String, _ store: Store) -> Int {
        if name == pinned { return store.unsorted.count }
        return ["Resources", "OneDrive", "Zotero"].contains(name) ? 0 : store.openCount(name == "Tasks" ? "TaskNotes/Tasks" : name)
    }
}

/// A collapsible group in the sidebar (the open state is remembered).
struct NavSection<Content: View>: View {
    let title: String
    @AppStorage private var open: Bool
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
        _open = AppStorage(wrappedValue: true, "navOpen.\(title)")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button { withAnimation(.snappy(duration: 0.25)) { open.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0))
                    Spacer()
                }.foregroundStyle(Color.ink2).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(title), \(open ? "expanded" : "collapsed")")
            if open { content }
        }
    }
}

/// One row in the sidebar: a quiet icon and name; the open page gets a soft raised pill.
struct NavRow: View {
    @Environment(Store.self) private var store
    let icon: String; let title: String; let page: Page
    var iconTint: Color? = nil; var meta = 0; var on: Bool? = nil
    var body: some View {
        let selected = on ?? (store.page == page)
        Button { store.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 20).foregroundStyle(iconTint ?? (selected ? Color.ink : Color.ink2))
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if meta > 0 { Text("\(meta)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.ink2) }
            }
            .font(.system(size: 14, weight: selected ? .medium : .regular)).foregroundStyle(Color.ink)
            .padding(.horizontal, 10).frame(height: 32).contentShape(.rect(cornerRadius: DS.Radius.row))
        }
        .buttonStyle(SideRowStyle(selected: selected))
        .accessibilityLabel(meta > 0 ? "\(title), \(meta)" : title)
    }
}

/// The cog opens the Settings window (same as ⌘,).
struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button { openSettings() } label: { Image(systemName: "gearshape").font(.system(size: 13)) }
            .buttonStyle(.glassIcon(DS.Height.icon)).help("Settings (⌘,)").accessibilityLabel("Settings")
    }
}

/// Collapses the left sidebar to an icon rail like the right one (⌃⌘S).
struct CollapseButton: View {
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15)) { collapsed.toggle() } } label: {
            Image(systemName: "sidebar.left").font(.system(size: 13))
        }
        .buttonStyle(.glassIcon(DS.Height.icon))
        .help(collapsed ? "Show Sidebar" : "Hide Sidebar").accessibilityLabel(collapsed ? "Show sidebar" : "Hide sidebar")
    }
}

/// The collapsed left sidebar: icons with labels. Items, Files and Apps open as menus.
struct SidebarRail: View {
    @Environment(Store.self) private var store
    @AppStorage("dockHidden") private var hidden = ""
    func group(_ title: String, icon: String, _ list: [SideNav.Entry]) -> some View {
        let open: Bool = { if case .folder(let f) = store.page { list.contains { $0.name == f } } else { false } }()
        return Menu {
            ForEach(list.filter { !SideNav.isHidden($0.name, hidden) }, id: \.name) { e in
                Button { store.page = .folder(e.name) } label: { Label(SideNav.label(e.name), systemImage: e.icon) }
            }
        } label: { RailLabel(icon: icon, label: title, on: open) }
            .menuStyle(.button).buttonStyle(.glass(radius: DS.Radius.tile, selected: open)).menuIndicator(.hidden).help(title)
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    RailItem(icon: "house", label: "Home", on: store.page == .overview) { store.page = .overview }
                    if !SideNav.isHidden(SideNav.pinned, hidden) {
                        RailItem(icon: "tray", label: "Unsorted", badge: store.unsorted.count, on: { switch store.page { case .inbox, .folder("Unsorted"), .unsorted, .sortNow: true; default: false } }()) { store.page = .inbox }
                    }
                    RailItem(icon: "message", label: "Messages", on: { switch store.page { case .messages, .agent: true; default: false } }()) { store.page = .messages }
                    RailItem(icon: "number", label: "Tags", on: store.page == .tags) { store.page = .tags }
                    RailItem(icon: "chart.bar", label: "Week", on: store.page == .week) { store.page = .week }
                    RailItem(icon: "calendar", label: "Month", on: store.page == .month) { store.page = .month }
                    RailItem(icon: "graduationcap", label: "Semester", on: store.page == .semester) { store.page = .semester }
                    Divider().padding(.vertical, 6).padding(.horizontal, 12)
                    ForEach([("MSOA", "circle.circle"), ("SM", "hexagon"), ("TEM", "triangle")], id: \.0) { c, shape in
                        RailItem(icon: shape, label: c == "SM" ? "Strategy" : c, tint: .course(c), on: store.page == .course(c)) { store.page = .course(c) }
                    }
                    Divider().padding(.vertical, 6).padding(.horizontal, 12)
                    group("Items", icon: "tray.full", SideNav.items.filter { $0.name != SideNav.pinned })
                    group("Files", icon: "doc.on.doc", SideNav.files)
                    group("Apps", icon: "square.grid.2x2", SideNav.apps)
                }
            }.scrollIndicators(.hidden)
            RailItem(icon: "square.and.pencil", label: "New Note") { store.newNote() }.padding(.top, 6)
        }
        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RailLabel: View {
    let icon: String; let label: String
    var tint: Color = .ink2; var badge = 0; var on = false
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(on ? Color.ink : tint)
                .frame(width: 44, height: 28)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Color.ink, in: .capsule).foregroundStyle(Color.card).offset(x: 4, y: -2)
                    }
                }
            Text(label).font(.system(size: 10, weight: on ? .semibold : .regular)).foregroundStyle(on ? Color.ink : Color.ink2).lineLimit(1).fixedSize()
        }
        .frame(width: 60, height: 46)
    }
}

struct RailItem: View {
    let icon: String; let label: String
    var tint: Color = .ink2; var badge = 0; var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { RailLabel(icon: icon, label: label, tint: tint, badge: badge, on: on) }
            .buttonStyle(.glass(radius: DS.Radius.tile, selected: on)).help(label).accessibilityLabel(badge > 0 ? "\(label), \(badge)" : label)
    }
}

struct Heading: View {
    let text: String; var trailing = ""
    init(_ text: String, trailing: String = "") { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack { Text(text).fontWeight(.semibold); Spacer(); Text(trailing) }
            .font(.caption).foregroundStyle(Color.ink2).padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 2)
    }
}

/// Line-art portrait that pulses while its agent is working. (It used to breathe forever even when idle, which kept the whole window redrawing: about a quarter of a CPU core for a one-pixel movement.)
struct AgentPortrait: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String; var size: CGFloat = 36; var selected = false
    @State private var breathe = false
    var body: some View {
        let busy = store.thinking.contains(id)
        Portrait.image(id).resizable().scaledToFit().frame(width: size * 0.9).foregroundStyle(Color.ink)
            .frame(width: size, height: size, alignment: .bottom).background(Agent.color(id).opacity(0.25)).clipShape(.circle)
            .overlay(Circle().strokeBorder(selected ? Color.ink : Color.line, lineWidth: selected ? 2 : 1))
            .overlay { if busy { Circle().strokeBorder(Color.warnFG, lineWidth: 2).scaleEffect(breathe ? 1.18 : 1).opacity(breathe ? 0 : 0.9) } }
            .scaleEffect(busy && breathe && !reduceMotion ? 1.04 : 1)
            .animation(busy && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: breathe)
            .onChange(of: busy, initial: true) { _, now in breathe = now }
    }
}

// MARK: - Pages
struct MainPanel: View {
    @Environment(Store.self) private var store
    @State private var width: CGFloat = 1100
    var body: some View {
        page
            .environment(\.mainWidth, width)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }
    @ViewBuilder var page: some View {
        switch store.page {
        case .inbox, .folder("Unsorted"): ItemsPage(title: "Unsorted", folders: ["Unsorted"], inbox: true).id("Unsorted")
        case .overview: OverviewPage()
        case .week: WeekPage()
        case .month: MonthPage()
        case .semester: SemesterPage()
        case .course(let c): CoursePage(code: c)
        case .folder(let f) where SideNav.grouped.contains(f):
            switch f {
            case "Zotero": ZoteroPage()
            case _ where SideNav.files.contains(where: { $0.name == f }):
                FileBrowserPage(root: f, loose: !["Resources", "OneDrive"].contains(f)).id(f)
            case _ where AppKind(rawValue: f) != nil: AppHomePage(kind: AppKind(rawValue: f) ?? .mcq).id(f)
            default: NoteBrowserPage(title: f, folders: [f]).id(f)
            }
        case .folder(let f): ItemsPage(title: f, folders: [f == "Tasks" ? "TaskNotes/Tasks" : f]).id(f)
        case .unsorted(let url): if url.pathExtension == "md" { NotePage(url: url).id(url) } else { UnsortedPage(url: url) }
        case .search: SearchPage()
        case .sortNow: SortNowPage()
        case .agent(let c): AgentPage(code: c)
        case .messages: MessagesPage()
        case .note(let url):
            if let kind = store.appKind(for: .note(url)) { AppSubPage(url: url, kind: kind).id(url) } else { NotePage(url: url).id(url) }
        case .file(let url): FilePage(url: url)
        case .tags: TagsPage()
        case .newTab: NewTabPage()
        }
    }
}

struct PageHeader<Trailing: View>: View {
    @Environment(Store.self) private var store
    let title: String; let subtitle: String
    var compact = false   // a one-line title, as in a Craft toolbar
    @ViewBuilder var trailing: Trailing
    /// A round + for a new note, then the title in a serif, as in Craft's page headers.
    var titleBlock: some View {
        HStack(spacing: 14) {
            Button { store.newNote() } label: { Image(systemName: "plus").font(.system(size: 15, weight: .medium)) }
                .buttonStyle(.glassIcon()).help("New Note (⌘N)").accessibilityLabel("New note")
            VStack(alignment: .leading, spacing: 1) {
                if compact { Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1) }
                else {
                    Text(title).font(.system(size: 28, weight: .semibold, design: .serif)).lineLimit(1)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.ink2).lineLimit(1)
                }
            }
        }
    }
    var body: some View {
        // One row when it fits; in a narrow window the controls drop under the title.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) { titleBlock; Spacer(minLength: 16); trailing.fixedSize() }
            VStack(alignment: .leading, spacing: 10) { titleBlock; ScrollView(.horizontal) { trailing.padding(.vertical, 2) }.scrollIndicators(.hidden) }
        }.padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 14)
    }
}

/// A segmented control: one glass pill that slides between the options.
struct Pills<T: Hashable>: View {
    let options: [(T, String)]; @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(options, id: \.0) { value, label in
                    let on = selection == value
                    Button { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { selection = value } } label: {
                        Text(label).font(.system(size: 13, weight: on ? .semibold : .regular)).fixedSize().padding(.horizontal, 16).frame(height: DS.Height.control)
                            .foregroundStyle(on ? Color.ink : Color.ink2)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(Color.ink.opacity(0.1)).interactive() : .identity, in: .capsule)
                    .glassEffectID(on ? "selected" : "option-\(label)", in: ns)
                }
            }
            .padding(4).glassEffect(.regular, in: .capsule)
        }
    }
}

struct Card<Content: View>: View {
    var title: String? = nil; var trailing = ""; var fill: Color = .card; var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack { Text(title).font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(Color.ink); Spacer(); Text(trailing).font(.caption) }.foregroundStyle(Color.ink2)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if fill != .clear {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.card.opacity(0.78))
                    .overlay { if let tint { RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(tint.opacity(0.16)) } }
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(Color.line.opacity(0.5)))
    }
}

struct NoteRow: View {
    @Environment(Store.self) private var store
    let note: Note; var badge = false; var timeColumn = false
    var body: some View {
        HStack(spacing: 12) {
            if timeColumn {
                Text(note.when.map { Calendar.current.component(.hour, from: $0) == 0 ? "Due" : $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.ink2).fixedSize().frame(width: 44, alignment: .leading)
            }
            StatusButton(note: note, size: 18)
            Button { store.page = .note(note.id) } label: {
                HStack(spacing: 10) {
                    if timeColumn { RoundedRectangle(cornerRadius: 2).fill(Color.course(note.course)).frame(width: 3, height: 22) }
                    else { Circle().fill(Color.course(note.course)).frame(width: 8, height: 8) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.display).foregroundStyle(note.done ? Color.ink2 : Color.ink).lineLimit(1)
                        if !timeColumn {
                            Text(([note.course, note.kind] + [note.when.map(NoteRow.format)]).compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if timeColumn { Text(note.kind).font(.system(size: 11)).foregroundStyle(Color.ink2) }
                    if badge, let w = note.when { Countdown(days: store.days(w)) }
                }.padding(.horizontal, 6).padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.glassRow)
        }
        .font(.system(size: 13)).padding(.horizontal, 10).frame(minHeight: timeColumn ? 38 : 46)
        .overlay(alignment: .top) { Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1) }
        .contextMenu { NoteMenu(note: note) }
    }
    static func format(_ d: Date) -> String {
        let cal = Calendar.current
        let hasTime = cal.component(.hour, from: d) != 0 || cal.component(.minute, from: d) != 0
        return hasTime ? d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                       : d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct Countdown: View {
    let days: Int
    var body: some View {
        let (fg, bg): (Color, Color) = days <= 3 ? (.redFG, .redBG) : days <= 7 ? (.warnFG, .warnBG) : (.ink2, .ink.opacity(0.05))
        Text("\(days)d").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 3).frame(minWidth: 36).foregroundStyle(fg).background(bg, in: .capsule)
    }
}

struct NoteList: View {
    let notes: [Note]; var badge = false; var empty = "Nothing here"; var timeColumn = false
    var body: some View {
        if notes.isEmpty {
            Text(empty).font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView { LazyVStack(spacing: 0) { ForEach(notes) { NoteRow(note: $0, badge: badge, timeColumn: timeColumn) } } }
        }
    }
}

struct OverviewPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        let today = store.todayItems
        VStack(spacing: 0) {
            PageHeader(title: Date.now.formatted(.dateTime.weekday(.wide)),
                       subtitle: Date.now.formatted(.dateTime.day().month(.wide)) + " · Semester 1, Week \(store.semesterWeek)") {
                HStack(spacing: 10) {
                    Pills(options: [(nil, "All"), ("MSOA", "MSOA"), ("SM", "SM"), ("TEM", "TEM")] as [(String?, String)], selection: $store.filter)
                    RoundButton(icon: "calendar", label: "Month") { store.page = .month }
                    Button { store.newNote() } label: { Label("New Note", systemImage: "plus") }
                        .buttonStyle(.glassAction(.header))
                }
            }
            SplitPane(fixed: .first, width: 420, stacked: (560, 800)) {
                // Today: stats and schedule on top, the Manager below.
                Card {
                    GeometryReader { g in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Stat(label: "Not started", value: today.filter { $0.status == "Not started" }.count, dot: .ink2)
                                Stat(label: "Started", value: today.filter { $0.state == .human || $0.state == .agent }.count, dot: .warnFG)
                                Stat(label: "Done", value: today.filter(\.done).count, dot: .ink)
                            }.padding(16)
                            NoteList(notes: today, empty: "Nothing scheduled today", timeColumn: true).frame(maxHeight: .infinity)
                            Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1)
                            AgentStage(id: Agent.manager.id, says: store.managerSays()).frame(height: g.size.height * 0.56)
                        }
                    }
                }.appearIn(0)
            } second: {
                // Everything ahead, all three at once.
                VStack(spacing: 12) {
                    ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, tab in
                        let items = store.list(tab)
                        Card(title: tab.rawValue, trailing: items.isEmpty ? "" : "\(items.count) ahead", tint: tab.tint) {
                            NoteList(notes: items, badge: true, empty: tab == .readings ? "No readings due" : tab == .classes ? "No classes ahead" : "Nothing due")
                        }.appearIn(0.06 * Double(i + 1))
                    }
                }
            }.padding([.horizontal, .bottom], 12)
        }
    }
}

struct RoundButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 15)) }
            .buttonStyle(.glassIcon())
            .help(label).accessibilityLabel(label)
    }
}

struct Stat: View {
    let label: String; let value: Int; let dot: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) { Circle().fill(dot).frame(width: 7, height: 7); Text(label).fontWeight(.semibold) }.font(.system(size: 10)).foregroundStyle(Color.ink2)
            Text("\(value)").font(.system(size: 22)).monospacedDigit().contentTransition(.numericText()).animation(.spring(duration: 0.4), value: value)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Chip: View {
    let key: String; let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        HStack(spacing: 6) { Text(key).foregroundStyle(Color.ink2); Text(value) }
            .font(.system(size: 13)).glassField()
    }
}

/// A file waiting in Unsorted that isn't a note (notes open in the normal note page): a preview with Open and Show in Finder.
/// Filing is done by Sort Now and the Manager.
struct UnsortedPage: View {
    let url: URL
    var risky: Bool { url.pathExtension == "txt" }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: Vault.label(url), subtitle: "\(url.pathExtension.uppercased()) · waiting in Unsorted") {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") }.buttonStyle(.glassAction(.header))
            }
            Card {
                if risky { Label("Looks like credentials, so it won’t be filed. Move it out of the vault and rotate the key if it’s real.", systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(Color.redFG).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                if url.pathExtension.lowercased() == "pdf" {
                    PDFViewer(url: url).id(url)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 128, height: 128)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.glassRow).padding(16)
            }.padding([.horizontal, .bottom], 12)
        }
    }
}

struct SortNowPage: View {
    @Environment(Store.self) private var store
    @State private var key: String?
    @State private var finished = false
    /// `.txt` files look like credentials, so they are never filed.
    var files: [URL] { store.unsorted.filter { $0.pathExtension != "txt" } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Sort Now", subtitle: "\(files.count) item\(files.count == 1 ? "" : "s") in Unsorted") { EmptyView() }
            Card(title: "Sorting") {
                VStack(alignment: .leading, spacing: 12) {
                    if let key { JobProgress(key: key, finished: finished) }
                    else {
                        Text(files.isEmpty ? "Nothing to sort." : "The Sorter files everything in Unsorted. The Manager asks the relevant course agents first and checks the result, and you can undo it afterwards.")
                            .font(.system(size: 13)).foregroundStyle(Color.ink2)
                        if !files.isEmpty { Button { run() } label: { Label("Sort Now", systemImage: "sparkle") }.buttonStyle(.glassAction(.control, prominent: true)) }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding([.horizontal, .bottom], 12)
        }
    }
    func run() {
        let k = "manual:sort:" + UUID().uuidString
        key = k; finished = false
        Task {
            store.log("planner", await store.syncCalendar())   // so the Sorter sees fresh deadlines in Calendar Sync.md
            await store.manualJob(.sorting(files, key: k))
            finished = true
        }
    }
}

struct SearchPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        let r = store.search(store.query)
        VStack(spacing: 0) {
            PageHeader(title: "Search", subtitle: store.query.isEmpty ? "Type in the sidebar" : "\(r.count) results for “\(store.query)”") { EmptyView() }
            Card {
                if r.isEmpty { Text("No matches").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    ScrollView { LazyVStack(spacing: 0) {
                        ForEach(r) { hit in
                            VStack(alignment: .leading, spacing: 0) {
                                NoteRow(note: hit.note)
                                if let s = hit.snippet { Text(s).font(.system(size: 12)).foregroundStyle(Color.ink2).lineLimit(2).padding(.leading, 70).padding(.trailing, 16).padding(.bottom, 8) }
                            }
                        }
                    } }
                }
            }.padding([.horizontal, .bottom], 12)
        }
    }
}
/// `SecondBrain --check`: prints what the loader sees and fails if it misses notes on disk.
enum Check {
    static func run() {
        let notes = Vault.load()
        let byFolder = Dictionary(grouping: notes, by: \.folder).mapValues(\.count)
        for f in Vault.folders { print(f.padding(toLength: 16, withPad: " ", startingAt: 0), byFolder[f] ?? 0) }
        let onDisk = Vault.folders.reduce(0) { total, f in
            total + ((try? FileManager.default.contentsOfDirectory(atPath: Vault.root.appending(path: Vault.dir(f)).path)) ?? []).filter { $0.hasSuffix(".md") }.count
        }
        print("loaded \(notes.count) / on disk \(onDisk) · dated \(notes.filter { $0.when != nil }.count) · current-course \(notes.filter { $0.course != nil }.count) · unsorted \(Vault.unsorted().count)")
        precondition(notes.count == onDisk, "loader skipped notes")
        // write-back touches only the status line (on a temp copy, never the vault)
        let src = notes.first { $0.title.contains("L03") && $0.course == "MSOA" }!
        let tmp = FileManager.default.temporaryDirectory.appending(path: "sb-check.md")
        try? FileManager.default.removeItem(at: tmp)
        try! FileManager.default.copyItem(at: src.id, to: tmp)
        let before = try! String(contentsOf: tmp, encoding: .utf8)
        let copy = Note(id: tmp, folder: src.folder, title: src.title, status: src.status, course: src.course, when: src.when, path: src.path)
        try! Vault.setStatus(copy, to: "Not started")
        let after = try! String(contentsOf: tmp, encoding: .utf8)
        let changed = zip(before.split(separator: "\n", omittingEmptySubsequences: false), after.split(separator: "\n", omittingEmptySubsequences: false)).filter { $0 != $1 }
        precondition(changed.count == 1 && changed[0].1 == "status: Not started", "write-back changed more than the status line")
        print("write-back ok: only `status:` changed")
        // app-side filing: copy + verify + original to .trash, never overwrite, never outside the vault
        let box = FileManager.default.temporaryDirectory.appending(path: "sb-move-check")
        try? FileManager.default.removeItem(at: box)
        try! FileManager.default.createDirectory(at: box.appending(path: "Unsorted"), withIntermediateDirectories: true)
        try! "slides".write(to: box.appending(path: "Unsorted/Week 2 [STUDENTS].pdf"), atomically: true, encoding: .utf8)
        let mv = Vault.moves(in: "1. File it\nMOVE: `Unsorted/Week 2 [STUDENTS].pdf` -> Resources/TEM/Slides/lecture-02.pdf")
        precondition(mv == [Vault.Move(from: "Unsorted/Week 2 [STUDENTS].pdf", to: "Resources/TEM/Slides/lecture-02.pdf")], "MOVE line parsing")
        try! Vault.perform(mv[0], in: box)
        precondition((try? String(contentsOf: box.appending(path: "Resources/TEM/Slides/lecture-02.pdf"), encoding: .utf8)) == "slides", "copy landed")
        precondition(!FileManager.default.fileExists(atPath: box.appending(path: "Unsorted/Week 2 [STUDENTS].pdf").path), "original left Unsorted")
        precondition(((try? FileManager.default.subpathsOfDirectory(atPath: box.appending(path: ".trash").path)) ?? []).contains { $0.hasSuffix("Week 2 [STUDENTS].pdf") }, "original kept in .trash")
        try! "again".write(to: box.appending(path: "Unsorted/x.pdf"), atomically: true, encoding: .utf8)
        precondition((try? Vault.perform(.init(from: "Unsorted/x.pdf", to: "Resources/TEM/Slides/lecture-02.pdf"), in: box)) == nil, "never overwrites")
        precondition((try? Vault.perform(.init(from: "Unsorted/x.pdf", to: "../escape.pdf"), in: box)) == nil, "never leaves the vault")
        print("filing ok: copy verified, original in .trash, no overwrite, no escape")
        AppFiles.check()
        CalendarSync.check()
        Zotero.check()
        CalendarSync.checkNotes()
        Vault.checkEditing()
        Manager.check()
        let tags = TagsPage.build(notes); precondition(!tags.isEmpty, "tags are indexed from frontmatter")
        let week: (Date?) -> Int = { d in d.map { Int((Double(Calendar.current.dateComponents([.day], from: Vault.semesterOneStart, to: $0).day ?? 0) / 7).rounded(.down)) + 1 } ?? 0 }
        let mapped = CourseGraph.build(notes.filter { $0.course == "SM" && CourseGraph.row($0) != nil }, week: week)
        precondition(mapped.nodes.count > 5 && mapped.edges.contains(where: \.explicit), "the course map finds notes and the links written between them")
        let essay = notes.first { $0.folder == "Essays" && $0.course == "SM" }
        print("tags ok: \(tags.count) tags · map ok: \(mapped.nodes.count) notes, \(mapped.edges.filter(\.explicit).count) written links, \(mapped.edges.filter { !$0.explicit }.count) inferred · SM essay weight: \(essay.flatMap(CourseTimeline.weight).map { "\($0)%" } ?? "not found")")
        Vault.checkNewNote()
        StudyParse.check()
        let imgs = MD.parse(["![[Resources/X/a.png|300]]", "![](https://x.y/z.jpg)", "text ![[b.png]] inline"])
        guard case .image("Resources/X/a.png", 300) = imgs[0], case .image("https://x.y/z.jpg", nil) = imgs[1], case .para = imgs[2] else { fatalError("image parsing") }
        MainActor.assumeIsolated {
            let st = Store(), hits = st.search("lecture"), linked = st.notes.filter { !st.backlinks(to: $0).isEmpty }.count
            precondition(!hits.isEmpty && st.search("zzqqxx").isEmpty, "search")
            print("search ok: \(hits.count) hits for “lecture” · \(linked) notes have backlinks")
        }
        MainActor.assumeIsolated {   // an agent's job marks the note Agent In Progress and puts its status back; a status you changed meanwhile is left alone
            let box = FileManager.default.temporaryDirectory.appending(path: "sb-claim-check"), name = "Strategic Management L01 - Lecture 1.md"
            try? FileManager.default.removeItem(at: box)
            try! FileManager.default.createDirectory(at: box.appending(path: "Lectures"), withIntermediateDirectories: true)
            let file = box.appending(path: "Lectures/" + name)
            try! "---\ncourse: \"[[Strategic Management]]\"\nstatus: Not started\ndate: 2026-10-05T15:10\n---\n".write(to: file, atomically: true, encoding: .utf8)
            setenv("SECOND_BRAIN_VAULT", box.path, 1); defer { unsetenv("SECOND_BRAIN_VAULT"); UserDefaults.standard.removeObject(forKey: "agentClaims") }
            let st = Store(), rel = Vault.rel(file), status = { Vault.frontmatter((try? String(contentsOf: file, encoding: .utf8)) ?? "")["status"] }
            st.claim(rel, manual: true); precondition(status() == "Agent In Progress" && st.notes.first?.state == .agent, "claimed")
            st.release(rel); precondition(status() == "Not started", "put back: \(status() ?? "nil")")
            st.claim(rel, manual: true); try! Vault.setStatus(st.notes.first!, to: "Done"); st.reload(); st.release(rel)
            precondition(status() == "Done" && st.claims.isEmpty, "a status you set yourself is kept")
            print("claims ok: agent jobs mark the note and restore it")
        }
        let pipelineFlag = CheckFlag()
        Task { @MainActor in await Store.checkPipeline(); pipelineFlag.done = true }
        while !pipelineFlag.done { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
        print("images ok: embeds parse as blocks, inline ones stay text")
        precondition(notes.contains { $0.course == "MSOA" && $0.title.contains("L03") && $0.done }, "MSOA L03 should parse as Done")
    }
}

struct AgentPage: View {
    @Environment(Store.self) private var store
    let code: String
    @State private var showLog = false
    var role: Agent.Role { Agent.role(code) }
    var body: some View {
        let messages = store.chats[code] ?? []
        let busy = store.thinking.contains(code)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AgentPortrait(id: code, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name).font(.system(size: 24, weight: .medium))
                    HStack(spacing: 6) {
                        Circle().fill(busy ? Color.warnFG : Color(light: 0x2F8467, dark: 0x5CC39A)).frame(width: 7, height: 7)
                        Text(busy ? "Working…" : role.job + (code == Agent.manager.id ? " · decides on your Mac" : " · runs on Claude Code")).font(.system(size: 13)).foregroundStyle(Color.ink2)
                    }
                }
                Spacer()
                RoundButton(icon: "message", label: "All messages") { store.page = .messages }
                RoundButton(icon: "list.bullet.rectangle", label: "Activity Log") { showLog.toggle() }
                    .popover(isPresented: $showLog, arrowEdge: .bottom) { ActivityLog().environment(store) }
            }.padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 14)
            SplitPane(fixed: .second, width: 300, stacked: (520, 460)) {
                AgentChatCard(code: code)
            } second: {
                VStack(spacing: 12) {
                    if code == Agent.manager.id { ManagerCard() } else { NeedsCard(code: code) }
                    Card(title: "Try", trailing: "Won’t edit your notes") {
                        VStack(spacing: 6) {
                            ForEach(role.actions, id: \.self) { a in
                                Button { store.ask(code, a) } label: {
                                    HStack(spacing: 8) { Image(systemName: "sparkle"); Text(a).multilineTextAlignment(.leading); Spacer() }
                                        .font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 9)
                                }.buttonStyle(.glassRow).disabled(busy)
                            }
                        }.padding(.horizontal, 12).padding(.bottom, 12)
                    }.fixedSize(horizontal: false, vertical: true)
                }.scrollsWhenShort()
            }.padding([.horizontal, .bottom], 12)
        }
    }
}

/// Insets the window's close/minimise/zoom buttons so they sit inside the sidebar's glass,
/// level with the ••• and collapse buttons (centre 32pt from the top, first button 34pt from the left).
struct TrafficLights: NSViewRepresentable {
    final class Placer: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); place() }
        override func layout() { super.layout(); place() }
        func place() {
            // After AppKit's own titlebar layout, which would otherwise put them back.
            DispatchQueue.main.async { [weak self] in
                guard let w = self?.window, !w.styleMask.contains(.fullScreen) else { return }
                for (i, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                    guard let b = w.standardWindowButton(type), let bar = b.superview else { continue }
                    let size = b.frame.size
                    let y = bar.isFlipped ? 28 - size.height / 2 : bar.bounds.height - 28 - size.height / 2
                    b.setFrameOrigin(NSPoint(x: 34 - size.width / 2 + CGFloat(i) * 20, y: y))
                }
            }
        }
    }
    func makeNSView(context: Context) -> Placer { Placer() }
    func updateNSView(_ v: Placer, context: Context) { v.place() }
}
