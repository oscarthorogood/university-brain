import SwiftUI

/// Something an agent can't do without Oscar. Worked out from the vault itself (instant, no model call).
struct Need: Identifiable {
    var id: String { title + sub }
    let title: String; let sub: String
    var open: Page? = nil      // go here
    var prompt: String? = nil  // or ask the agent this
}

/// What the agents did. App runs are saved in Application Support; the vault's own decision log adds its dated entries.
struct Activity: Codable, Identifiable {
    var id: String { "\(time.timeIntervalSince1970)\(agent)\(text)" }
    let time: Date; let agent: String; let text: String
    var undo: String? = nil   // the inbox job this entry can put back

    static var file: URL { Support.dir.appending(path: "activity.json") }
    static func load() -> [Activity] { (try? JSONDecoder().decode([Activity].self, from: Data(contentsOf: file))) ?? [] }
    static func save(_ a: [Activity]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(a).write(to: file, options: .atomic)
    }
    /// `## 2026-10-01 — Unsorted sort, sixth pass (…)` headings in Agents/Shared Agents/memory.md.
    static func vaultLog() -> [Activity] {
        guard let text = try? String(contentsOf: Vault.root.appending(path: "Agents/Shared Agents/memory.md"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("## "), let d = Vault.parseDate(String(line.dropFirst(3).prefix(10))) else { return nil }
            let rest = line.dropFirst(13).trimmingCharacters(in: CharacterSet(charactersIn: " —-"))
            let title = rest.components(separatedBy: " (").first ?? rest
            return Activity(time: d, agent: title.localizedCaseInsensitiveContains("sort") ? "sorter" : "vault", text: title)
        }
    }
}

extension Store {
    func log(_ agent: String, _ text: String, undo: UUID? = nil) {
        activity.insert(Activity(time: .now, agent: agent, text: text, undo: undo?.uuidString), at: 0)
        activity = Array(activity.prefix(200))
        Activity.save(activity)
    }
    var allActivity: [Activity] { (activity + Activity.vaultLog()).sorted { $0.time > $1.time } }

    func computeNeeds() {
        let current = notes.filter { $0.course != nil }
        let short = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        var n: [String: [Need]] = [:]
        n["sorter"] = unsorted.map { u in
            u.pathExtension == "txt" ? Need(title: "1 file needs review", sub: "Never filed automatically", open: .unsorted(u))
                                     : Need(title: Vault.label(u), sub: "Waiting in Unsorted", open: .unsorted(u))
        }
        n["scribe"] = current.filter { ["Lectures", "Tutorials"].contains($0.folder) && $0.unfilled && ($0.when ?? .distantFuture) < .now }
            .sorted { $0.when! > $1.when! }
            .map { Need(title: $0.display, sub: "Not written up · " + $0.when!.formatted(short), open: .note($0.id)) }
        n["librarian"] = current.filter { $0.folder == "Readings" && !$0.done && ($0.status == "To Find" || $0.title.contains("Title To Confirm")) }
            .sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }
            .map { Need(title: $0.title, sub: $0.status == "To Find" ? "Source still to find" : "Citation to confirm", open: .note($0.id)) }
        let soon = current.filter { ["Essays", "Projects"].contains($0.folder) } + notes.filter { $0.folder == "TaskNotes/Tasks" }
        n["planner"] = notes.filter { $0.folder == "Courses" && Vault.courses[$0.title] != nil && $0.unfilled }
            .map { Need(title: "\($0.title): no key dates", sub: "Add exam and deadline dates", open: .note($0.id)) }
            + soon.filter { !$0.done && $0.when != nil && (0...7).contains(days($0.when!)) }.sorted { $0.when! < $1.when! }
            .map { Need(title: $0.title, sub: days($0.when!) == 0 ? "Due today" : "Due in \(days($0.when!))d · \($0.status)", open: .note($0.id)) }
        n["writer"] = current.filter { ["Essays", "Projects"].contains($0.folder) && !$0.done && $0.when != nil && (0...28).contains(days($0.when!)) }
            .sorted { $0.when! < $1.when! }
            .map { Need(title: $0.display, sub: "Due in \(days($0.when!))d · \($0.status)", open: .note($0.id)) }
        n["tutor"] = current.filter { $0.folder == "Lectures" && $0.done && ($0.when.map { days($0) >= -7 && $0 < .now } ?? false) }
            .sorted { $0.when! > $1.when! }
            .map { Need(title: "Quiz yourself on \($0.display)", sub: "Lecture " + $0.when!.formatted(short), prompt: "Make 5 MCQs with answers from \($0.title), quoting the slides.") }
        needs = n
    }
}

struct NeedsCard: View {
    @Environment(Store.self) private var store
    let code: String
    var body: some View {
        let list = store.needs[code] ?? []
        Card(title: "Needs You", trailing: list.isEmpty ? "" : "\(list.count)") {
            if list.isEmpty {
                Label("Nothing waiting on you", systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(list) { need in
                            Button {
                                if let p = need.prompt { store.ask(code, p) } else if let o = need.open { store.page = o }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: need.prompt == nil ? "exclamationmark.circle" : "sparkle").foregroundStyle(need.prompt == nil ? Color.warnFG : Color.ink2)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(need.title).font(.system(size: 13)).lineLimit(1)
                                        Text(need.sub).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: need.prompt == nil ? "chevron.right" : "arrow.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2)
                                }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(.rect)
                            }
                            .buttonStyle(.glassRow).disabled(need.prompt != nil && store.thinking.contains(code))
                            .help(need.prompt ?? "Open")
                        }
                    }.padding(.horizontal, 6).padding(.bottom, 8)
                }
            }
        }
    }
}

struct ActivityLog: View {
    @Environment(Store.self) private var store
    var body: some View {
        let items = Array(store.allActivity.prefix(60))
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity Log").font(.headline).padding(16)
            if items.isEmpty {
                Text("Nothing yet. Agent runs and filings show up here.").font(.system(size: 13)).foregroundStyle(Color.ink2).padding([.horizontal, .bottom], 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { a in
                            HStack(alignment: .top, spacing: 10) {
                                if Agent.all.contains(where: { $0.id == a.agent }) { AgentPortrait(id: a.agent, size: 24) }
                                else { Image(systemName: "book.closed").frame(width: 24, height: 24).foregroundStyle(Color.ink2) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                    Text((Agent.all.first { $0.id == a.agent }?.name ?? "Vault log") + " · " + a.time.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 11)).foregroundStyle(Color.ink2)
                                    if let u = a.undo.flatMap(UUID.init(uuidString:)), store.canUndo(u) {
                                        Button("Undo") { store.undoJob(u) }.buttonStyle(.glassAction(.chip)).help("Put the note or files back as they were")
                                    }
                                }
                            }
                        }
                    }.padding([.horizontal, .bottom], 16)
                }
            }
        }.frame(width: 360, height: 420, alignment: .top)
    }
}

extension Store {
    /// What a job in progress looks like in a bubble.
    func jobLine(_ item: InboxItem) -> String {
        let who = Agent.role(item.agent).name
        switch item.state {
        case .consulting: return "Asking the course agent about “\(item.title)”."
        case .checking: return "Checking \(who)’s work on “\(item.title)”."
        default: return "\(who) is on “\(item.title)”."
        }
    }
    /// What the Manager would tell you right now across all courses, and where each thing leads. Plain facts from the vault, so always true.
    func managerSays() -> [Say] {
        var out: [Say] = []
        for item in activeJobs { out.append(Say(text: jobLine(item), go: .messages)) }
        out += headsUps()
        func when(_ d: Date) -> String {
            (Calendar.current.isDateInToday(d) ? "today" : d.formatted(.dateTime.weekday(.wide))) + " at " + d.formatted(.dateTime.hour().minute())
        }
        let current = notes.filter { $0.course != nil }
        for n in current.filter({ ["Lectures", "Tutorials"].contains($0.folder) && !$0.done && ($0.when ?? .distantPast) > .now }).sorted(by: { $0.when! < $1.when! }).prefix(2) {
            out.append(Say(text: "\(n.display) is \(when(n.when!)).", go: .note(n.id)))
        }
        for c in Vault.courses.values.sorted() {
            if let d = nextDeliverable(c), let w = d.when, days(w) <= 45 { out.append(Say(text: "\(c == "SM" ? "Strategy" : c): \(d.display) is due in \(days(w)) days.", go: .note(d.id))) }
        }
        let stubs = current.filter { ["Lectures", "Tutorials"].contains($0.folder) && $0.unfilled && ($0.when ?? .distantFuture) < .now }
        if let last = stubs.max(by: { $0.when! < $1.when! }) { out.append(Say(text: "\(stubs.count) class\(stubs.count == 1 ? "" : "es") still need writing up.", go: .note(last.id))) }
        let due = current.filter { $0.folder == "Readings" && !$0.done && ($0.when.map { (0...7).contains(days($0)) } ?? false) }.count
        if due > 0 { out.append(Say(text: "\(due) reading\(due == 1 ? "" : "s") due this week.", go: .folder("Readings"))) }
        let find = current.filter { $0.folder == "Readings" && $0.status == "To Find" }.count
        if find > 0 { out.append(Say(text: "\(find) reading\(find == 1 ? "" : "s") still need\(find == 1 ? "s" : "") a source.", go: .folder("Readings"))) }
        if let u = unsorted.first { out.append(Say(text: "\(unsorted.count) file\(unsorted.count == 1 ? "" : "s") waiting in Unsorted.", go: .unsorted(u))) }
        return out.isEmpty ? [Say(text: "All quiet. Ask me anything.", go: nil)] : out
    }
}

extension Store {
    /// Needs You items from every helper that belong to one course.
    func courseNeeds(_ c: String) -> [(role: String, need: Need)] {
        Agent.roles.flatMap { r in (needs[r.id] ?? []).map { (r.id, $0) } }.filter { _, n in
            if case .note(let id)? = n.open { return notes.first { $0.id == id }?.course == c }
            return n.title.contains(c + " ")
        }.map { (role: $0.0, need: $0.1) }
    }

    /// What a course agent would say right now, in its own voice, and where each thing leads. Plain facts from the vault, so always true.
    func courseSays(_ c: String) -> [Say] {
        let mine = notes.filter { $0.course == c }
        var out: [Say] = []
        for item in activeJobs where item.agent == c || item.paths.contains(where: { p in notes.first { Vault.rel($0.id) == p }?.course == c }) {
            out.append(Say(text: jobLine(item), go: .messages))
        }
        out += headsUps(course: c)
        func when(_ d: Date) -> String {
            (Calendar.current.isDateInToday(d) ? "today" : d.formatted(.dateTime.weekday(.wide))) + " at " + d.formatted(.dateTime.hour().minute())
        }
        let classes = mine.filter { ["Lectures", "Tutorials"].contains($0.folder) }
        for next in classes.filter({ !$0.done && ($0.when ?? .distantPast) > .now }).sorted(by: { $0.when! < $1.when! }).prefix(2) {
            out.append(Say(text: "\(next.display.replacingOccurrences(of: c + " ", with: "")) is \(when(next.when!)).", go: .note(next.id)))
        }
        if let stub = classes.filter({ $0.unfilled && ($0.when ?? .distantFuture) < .now }).max(by: { $0.when! < $1.when! }) {
            out.append(Say(text: "I haven’t written up \(stub.display.replacingOccurrences(of: c + " ", with: "")) yet.", go: .note(stub.id)))
        }
        if let d = nextDeliverable(c), let w = d.when { out.append(Say(text: "\(d.display) is due in \(days(w)) days.", go: .note(d.id))) }
        let due = mine.filter { $0.folder == "Readings" && !$0.done && ($0.when.map { (0...7).contains(days($0)) } ?? false) }.count
        if due > 0 { out.append(Say(text: "I’ve got \(due) reading\(due == 1 ? "" : "s") due this week.", go: .folder("Readings"))) }
        let find = mine.filter { $0.folder == "Readings" && $0.status == "To Find" }.count
        if find > 0 { out.append(Say(text: "\(find) reading\(find == 1 ? "" : "s") still need\(find == 1 ? "s" : "") a source.", go: .folder("Readings"))) }
        for (role, n) in courseNeeds(c).prefix(2) { if let o = n.open { out.append(Say(text: "\(Agent.role(role).name): \(n.title)", go: o)) } }
        return out.isEmpty ? [Say(text: "All quiet here.", go: nil)] : out
    }
}

/// One thing an agent says, and where clicking it goes.
struct Say: Equatable {
    let text: String; var go: Page? = nil
    var gotIt: String? = nil       // a free heads-up: "got it" hides it for a day
    var askRole: String? = nil     // clicking it asks this agent…
    var askPrompt: String? = nil   // …this
}

/// A speech bubble: types (…), says one insight, then moves on to the next.
struct SayBubble: View {
    let lines: [Say]; let delay: Double; var tail = BubbleShape.Tail.left; var align = Alignment.leading; var open: (Page) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Store.self) private var store
    @State private var index = 0
    @State private var typing = true
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if typing && !reduceMotion { TypingDots().transition(.opacity) }
                else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lines[index % lines.count].text).font(.system(size: 11)).multilineTextAlignment(.leading).lineLimit(4)
                        let line = lines[index % lines.count]
                        if let key = line.gotIt {
                            Button { store.gotIt(key) } label: { Text("Got it").font(.system(size: 10, weight: .semibold)) }
                                .buttonStyle(.glassAction(.chip)).accessibilityLabel("Got it")
                        }
                    }
                    .id(index).transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .opacity))
                }
            }
            .padding(.leading, tail == .left ? 18 : 12).padding(.trailing, tail == .right ? 18 : 12).padding(.top, 8).padding(.bottom, tail == .bottom ? 18 : 8)
            .frame(minWidth: 44, minHeight: 32, alignment: .leading)
            .glassEffect(.regular, in: BubbleShape(tail: tail, radius: DS.Radius.row, tailAt: tail == .bottom ? (align == .trailing ? 0.86 : 0.14) : nil))
            .contentShape(Rectangle())
            .onTapGesture {
                let l = lines[index % lines.count]
                if let role = l.askRole, let prompt = l.askPrompt { open(.agent(role)); store.ask(role, prompt); if let k = l.gotIt { store.gotIt(k) } }
                else if let go = l.go { open(go) }
            }
        }
        .frame(maxWidth: .infinity, alignment: align)
        .accessibilityElement(children: .ignore).accessibilityLabel(lines[index % lines.count].text)
        .task(id: lines) {
            index = 0
            if reduceMotion { typing = false; return }
            try? await Task.sleep(for: .seconds(0.6 + delay))
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.2)) { typing = true }
                try? await Task.sleep(for: .seconds(1.1))
                withAnimation(.spring(duration: 0.4, bounce: 0.35)) { typing = false }
                try? await Task.sleep(for: .seconds(6))
                guard lines.count > 1 else { return }
                index += 1
            }
        }
    }
}

struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !Visibility.shared.visible)) { t in
            let x = t.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle().fill(Color.ink2).frame(width: 4, height: 4)
                        .opacity(0.3 + 0.7 * max(0, sin((x * 5) - Double(i) * 0.8)))
                }
            }
        }
    }
}
