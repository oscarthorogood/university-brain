import SwiftUI

/// One conversation with the Manager. The open one is `Store.chats` and `Store.sessions` (under the Manager's id), so everything that already talks to the chat keeps
/// working on whichever is open; the others keep their messages and their Claude session here. `messages` and `session` of the open one are always empty.
struct ChatThread: Identifiable, Codable {
    /// The empty conversation a fresh install (or one with every conversation deleted) starts with. Its id is fixed so the saved "open" id and the list agree.
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let newTitle = "New message"
    static var first: ChatThread { ChatThread(id: firstID, title: newTitle) }
    var id = UUID()
    var title: String
    var pinned = false
    var unread: Bool?    // the Manager started this one and you haven't opened it yet (optional, so older chats.json still loads)
    var created = Date.now
    var messages: [Message] = []
    var session: String?
}

/// A conversation as the list shows it, or as a search finds it.
struct ThreadHit: Identifiable {
    let thread: ChatThread, snippet: String, at: Date
    var message: UUID?    // the message a search matched
    var id: UUID { thread.id }
}

extension Store {
    static let newChatTitle = ChatThread.newTitle

    /// Messages of any conversation (the open one's are in `chats`).
    func messages(of t: ChatThread) -> [Message] { t.id == openThread ? chats[Agent.manager.id] ?? [] : t.messages }

    /// The conversations, pinned first and then the latest first; with a search, only those whose title or messages match, with the line that matched.
    func threadList(matching query: String) -> [ThreadHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var out: [ThreadHit] = []
        for t in threads {
            let msgs = messages(of: t).filter { !$0.text.hasPrefix("→") }
            let last = msgs.last, preview = last.map { clipped($0.text.senderAndBody.body.replacingOccurrences(of: "\n", with: " "), 80) } ?? "No messages yet"
            if q.isEmpty || t.title.localizedCaseInsensitiveContains(q) {
                out.append(ThreadHit(thread: t, snippet: preview, at: last?.time ?? t.created))
            } else if let hit = msgs.last(where: { $0.text.localizedCaseInsensitiveContains(q) }) {
                out.append(ThreadHit(thread: t, snippet: Self.excerpt(hit.text, around: q), at: hit.time, message: hit.id))
            }
        }
        return out.sorted { $0.thread.pinned != $1.thread.pinned ? $0.thread.pinned : $0.at > $1.at }
    }

    /// A short stretch of `text` around the first match of `q`, for a search result.
    nonisolated static func excerpt(_ text: String, around q: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let r = flat.range(of: q, options: .caseInsensitive) else { return String(flat.prefix(80)) }
        let from = flat.index(r.lowerBound, offsetBy: -30, limitedBy: flat.startIndex) ?? flat.startIndex
        let to = flat.index(r.upperBound, offsetBy: 50, limitedBy: flat.endIndex) ?? flat.endIndex
        return (from > flat.startIndex ? "…" : "") + String(flat[from..<to]) + (to < flat.endIndex ? "…" : "")
    }

    /// Opens a conversation, putting its messages and Claude session where the rest of the app looks for the chat's. Not while a reply is being written into the open one.
    func openChat(_ id: UUID, focus: UUID? = nil) {
        let m = Agent.manager.id
        guard !thinking.contains(m) else { return }
        if id != openThread, let to = threads.firstIndex(where: { $0.id == id }) {
            if let from = threads.firstIndex(where: { $0.id == openThread }) { threads[from].messages = chats[m] ?? []; threads[from].session = sessions[m] }
            chats[m] = threads[to].messages
            sessions[m] = threads[to].session
            threads[to].messages = []; threads[to].session = nil
            openThread = id; lastMode = nil; streaming[m] = nil; workingOn = nil
        }
        chatFocus = focus
        markChatSeen()
    }

    /// A new, empty conversation (the compose button). An empty one that is already open is reused.
    func newChat() {
        let m = Agent.manager.id
        guard !thinking.contains(m) else { return }
        if (chats[m] ?? []).isEmpty, threads.contains(where: { $0.id == openThread }) { return }
        let t = ChatThread(title: Self.newChatTitle)
        threads.append(t)
        openChat(t.id)
    }

    func togglePin(_ id: UUID) { if let i = threads.firstIndex(where: { $0.id == id }) { threads[i].pinned.toggle() } }

    /// Removes a conversation. If it is the open one, another is opened instead (a new one when it was the last).
    func deleteChat(_ id: UUID) {
        guard !thinking.contains(Agent.manager.id) else { return }
        if id == openThread {
            if let other = threads.first(where: { $0.id != id }) { openChat(other.id) }
            else { let t = ChatThread(title: Self.newChatTitle); threads.append(t); openChat(t.id) }
        }
        threads.removeAll { $0.id == id }
    }

    /// A conversation is named after the first thing said in it.
    func nameOpenThread(after text: String) {
        guard let i = threads.firstIndex(where: { $0.id == openThread }), threads[i].title == Self.newChatTitle else { return }
        threads[i].title = clipped(text, 34)
    }

    // MARK: The Manager starts a conversation

    /// The Manager texts you first. Each message is a new conversation of its own (named after its heading), unread until you open it, with quick replies under it.
    func nudge(_ text: String, chips: [Message.Chip] = []) {
        let msg = Message(fromAgent: true, text: text, proactive: true, chips: chips.isEmpty ? nil : chips)
        let (heading, body) = text.senderAndBody
        var t = ChatThread(title: clipped(heading ?? body, 34))
        t.messages = [msg]; t.unread = true
        threads.append(t)
    }

    /// The Manager's conversations you haven't opened yet.
    var unreadNudges: Int { threads.filter { $0.unread == true }.count }
    /// Opening a conversation reads it.
    func markChatSeen() {
        guard let i = threads.firstIndex(where: { $0.id == openThread }), threads[i].unread == true else { return }
        threads[i].unread = nil
    }

    // MARK: Tapbacks and quick replies

    /// A tapback on one of the Manager's messages; the same one again takes it off. "Not right" with a reason becomes a rule it reads next time.
    func react(_ id: UUID, _ kind: String, reason: String = "") {
        let m = Agent.manager.id
        guard let i = chats[m]?.firstIndex(where: { $0.id == id }) else { return }
        let on = chats[m]?[i].reaction != kind || !reason.isEmpty
        chats[m]?[i].reaction = on ? kind : nil
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == "down", on, !why.isEmpty else { return }
        let day = Date.now.formatted(.iso8601.year().month().day())
        let rule = "Oscar marked an answer as not right (\(day)): “\(clipped(why, 160))”. Don't do that again."
        let heading = Agent.role(lastMode ?? m).name
        if AgentFiles.addRule(rule, heading: heading) {
            log(m, "Learned from your “not right”: \(clipped(why, 100))")
            chats[m, default: []].append(Message(fromAgent: true, text: "Noted. I added that to what I've learned about \(heading) work, so I'll read it before the next one."))
        } else {
            chats[m, default: []].append(Message(fromAgent: true, text: "I couldn't save that rule. The learned-rules file isn't writable."))
        }
    }

    /// Taps a quick reply: it is sent as your message, and the chips go away.
    func useChip(_ messageID: UUID, _ chip: Message.Chip) {
        let m = Agent.manager.id
        guard !thinking.contains(m) else { return }
        if let i = chats[m]?.firstIndex(where: { $0.id == messageID }) { chats[m]?[i].chips = nil }
        ask(chip.prompt)
    }
}

// MARK: The conversation list

/// Conversations in a column beside the chat, like Messages: search at the top, pinned first, a compose button.
struct ThreadList: View {
    @Environment(Store.self) private var store
    @State private var query = ""

    var body: some View {
        let hits = store.threadList(matching: query), busy = store.thinking.contains(Agent.manager.id)
        VStack(spacing: 10) {
            HStack {
                Text("Messages").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { store.newChat() } label: { Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium)).foregroundStyle(IM.blue) }
                    .buttonStyle(.plain).disabled(busy).help("New message").accessibilityLabel("New message")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.ink2)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color.ink2) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 10).padding(.vertical, 6).glassEffect(.regular, in: .capsule)
            ScrollView {
                LazyVStack(spacing: 2) { ForEach(hits) { row($0, busy: busy) } }
                if hits.isEmpty { Text(query.isEmpty ? "No conversations." : "No results for “\(query)”.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.top, 16) }
            }
        }.padding(12)
    }

    private func row(_ h: ThreadHit, busy: Bool) -> some View {
        let selected = h.thread.id == store.openThread, unread = h.thread.unread == true
        let fromManager = store.messages(of: h.thread).first?.fromAgent == true   // the Manager started it
        return Button { store.openChat(h.thread.id, focus: h.message) } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle().fill(fromManager ? IM.blue : IM.grey.opacity(0.6)).frame(width: 30, height: 30)
                        .glassEffect(fromManager ? .regular.tint(IM.blue.opacity(0.85)) : .regular, in: .circle)
                    Image(systemName: fromManager ? "sparkles" : "bubble.left.fill").font(.system(size: 12))
                        .foregroundStyle(fromManager ? Color.white : Color.ink2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if unread { Circle().fill(IM.blue).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                        if h.thread.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.ink2) }
                        Text(h.thread.title).font(.system(size: 13, weight: unread ? .bold : .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Calendar.current.isDateInToday(h.at) ? h.at.formatted(.dateTime.hour().minute()) : h.at.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 10)).foregroundStyle(Color.ink2)
                    }
                    Text(h.snippet).font(.system(size: 12)).foregroundStyle(Color.ink2).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            .background { if selected { Color.clear.glassEffect(.regular.tint(IM.blue.opacity(0.14)), in: .rect(cornerRadius: 12)) } }
            .contentShape(.rect)
        }
        .buttonStyle(.plain).opacity(busy && !selected ? 0.5 : 1)
        .contextMenu {
            Button { store.togglePin(h.thread.id) } label: { Label(h.thread.pinned ? "Unpin" : "Pin", systemImage: h.thread.pinned ? "pin.slash" : "pin") }
            Button(role: .destructive) { store.deleteChat(h.thread.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: Self-check

enum ChatCheck {
    static func run() {
        // a tapback's "not right" becomes a rule under the right heading, once, with the placeholder gone
        let seed = "# Learned rules\n\n## Scribe\n\nNothing yet.\n\n## Manager\n\nNothing yet.\n"
        let a = AgentFiles.insertRule(into: seed, rule: "Keep it short.", heading: "Manager")
        precondition(a.contains("## Manager\n\n- Keep it short.\n") && a.contains("## Scribe\n\nNothing yet.") && !a.hasSuffix("Nothing yet.\n"), "rule inserted: \(a)")
        let b = AgentFiles.insertRule(into: a, rule: "Second.", heading: "Manager")
        precondition(b.contains("- Keep it short.\n- Second.\n"), "rules kept in order: \(b)")
        precondition(AgentFiles.insertRule(into: a, rule: "Keep it short.", heading: "Manager") == a, "a rule is not added twice")
        precondition(AgentFiles.insertRule(into: "# x\n", rule: "r", heading: "Analyst").contains("## Analyst\n\n- r"), "missing heading added")
        // a search result shows the words around the match
        precondition(Store.excerpt("abc needle def", around: "NEEDLE") == "abc needle def", "short text is whole")
        let long = String(repeating: "a", count: 60) + " needle " + String(repeating: "b", count: 90)
        let e = Store.excerpt(long, around: "needle")
        precondition(e.hasPrefix("…") && e.hasSuffix("…") && e.contains("needle"), "long text is cut: \(e)")
        // what the status line says while a tool runs
        precondition(Agent.statusLine(tool: "Read", input: ["file_path": "/v/Lectures/SM L05.md"]) == "Reading SM L05.md", "read status")
        precondition(Agent.statusLine(tool: "WebSearch", input: [:]) == "Searching the web" && Agent.statusLine(tool: "Bash", input: [:]) == nil, "other tools")
        // chats saved before tapbacks, cards and quick replies still load
        let old = #"{"id":"\#(UUID().uuidString)","fromAgent":true,"text":"hi","time":0}"#
        let m = try! JSONDecoder().decode(Message.self, from: Data(old.utf8))
        precondition(m.reaction == nil && m.change == nil && m.chips == nil && m.proactive == nil, "old message loads")
        print("chat ok: tapback rules, search excerpts, status lines, old chats load")
    }
}
