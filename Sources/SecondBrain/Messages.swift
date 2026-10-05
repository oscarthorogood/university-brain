import SwiftUI

/// Chat looks like iMessage everywhere, in Liquid Glass: blue-tinted glass bubbles for you on the right, clear glass for the agent on the
/// left, a small tail on the last bubble of a run, centred time stamps, "Delivered" / "Read", and three dots while the agent works.
enum IM {
    static let blue = Color(light: 0x0A84FF, dark: 0x0A84FF)
    static func shape(mine: Bool, tail: Bool = true) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine || !tail ? 18 : 5, bottomTrailingRadius: mine && tail ? 5 : 18, topTrailingRadius: 18, style: .continuous)
    }
}

extension String {
    /// The Manager mirrors an answer as "**Planner**\n\n…": that is the sender's name, then what they said.
    var senderAndBody: (sender: String?, body: String) {
        guard hasPrefix("**"), let end = range(of: "**\n\n", range: index(startIndex, offsetBy: 2)..<endIndex) else { return (nil, self) }
        return (String(self[index(startIndex, offsetBy: 2)..<end.lowerBound]), String(self[end.upperBound...]))
    }
}

struct IMBubble: View {
    let text: String; let mine: Bool
    var tail = true
    var size: CGFloat = 14
    var body: some View {
        Text(LocalizedStringKey(text)).font(.system(size: size)).lineSpacing(2).textSelection(.enabled)
            .foregroundStyle(mine ? Color.white : Color.ink)
            .padding(.horizontal, size * 0.9).padding(.vertical, size * 0.55)
            .glassEffect(mine ? .regular.tint(IM.blue) : .regular, in: IM.shape(mine: mine, tail: tail))
    }
}

/// The grey bubble with three bouncing dots.
struct IMTyping: View {
    var body: some View {
        TypingDots().padding(.horizontal, 16).padding(.vertical, 14)
            .glassEffect(.regular, in: IM.shape(mine: false))
    }
}

struct MessageRow: View {
    let message: Message
    var firstInRun = true, lastInRun = true
    var receipt: String? = nil     // "Delivered" or "Read", under your latest message
    var body: some View {
        let mine = !message.fromAgent
        if !mine && message.text.hasPrefix("→") {   // the Manager saying where it sent your request
            Text(LocalizedStringKey(message.text)).font(.system(size: 11)).foregroundStyle(Color.ink2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        } else {
            let (sender, text) = mine ? (nil, message.text) : message.text.senderAndBody
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if let sender, firstInRun { Text(sender).font(.system(size: 11)).foregroundStyle(Color.ink2).padding(.leading, 12) }
                HStack(spacing: 0) {
                    if mine { Spacer(minLength: 56) }
                    IMBubble(text: text, mine: mine, tail: lastInRun)
                    if !mine { Spacer(minLength: 56) }
                }
                if let receipt { Text(receipt).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.ink2).padding(.trailing, 4) }
            }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }
}

/// "Today 17:53", centred between conversations that are more than ten minutes apart.
struct IMStamp: View {
    let date: Date
    var body: some View {
        let day = Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        Text("\(Text(day).fontWeight(.semibold)) \(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))")
            .font(.system(size: 10)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity)
    }
}

/// The Messages app, for agents: every conversation in a list on the left (latest first), the open chat on the right.
struct MessagesInbox: View {
    @Environment(Store.self) private var store
    static let group = "group"   // the pinned Group Chat: not an agent, so it can't clash with an agent id
    @State private var selected = MessagesInbox.group

    private func last(_ id: String) -> Message? { store.chats[id]?.last { !$0.text.hasPrefix("→") } }
    /// Agents you have talked to come first, newest on top; the rest follow in roster order.
    private var order: [String] {
        let all = Agent.all.map(\.id)
        return all.filter { last($0) != nil }.sorted { last($0)!.time > last($1)!.time } + all.filter { last($0) == nil }
    }

    var body: some View {
        HStack(spacing: 12) {
            ScrollView {
                LazyVStack(spacing: 2) { groupRow; ForEach(order, id: \.self) { row($0) } }.padding(8)
            }
            .frame(width: 280).glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.card))
            if selected == Self.group { GroupChat() } else {
            let role = Agent.role(selected)
            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    AgentPortrait(id: selected, size: 46)
                    Text(role.name).font(.system(size: 12, weight: .semibold))
                    Text(store.thinking.contains(selected) ? "Working…" : role.job).font(.system(size: 10)).foregroundStyle(Color.ink2).lineLimit(1)
                }
                AgentChatCard(code: selected, suggest: true).id(selected)
            } }
        }
    }

    private func row(_ id: String) -> some View {
        let r = Agent.role(id), m = last(id)
        return Button { selected = id } label: {
            HStack(spacing: 10) {
                AgentPortrait(id: id, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(r.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let m { Text(Calendar.current.isDateInToday(m.time) ? m.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : m.time.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11)).foregroundStyle(Color.ink2) }
                    }
                    Text(store.thinking.contains(id) ? "Working…" : m.map { $0.text.senderAndBody.body.replacingOccurrences(of: "\n", with: " ") } ?? r.job)
                        .font(.system(size: 12)).foregroundStyle(Color.ink2).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == id ? Color.ink.opacity(0.1) : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }.buttonStyle(.plain)
    }
}

extension MessagesInbox {
    /// Pinned at the top: everything the agents say to each other.
    fileprivate var groupRow: some View {
        let m = store.agentTalk.last
        return Button { selected = Self.group } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill").font(.system(size: 16)).foregroundStyle(Color.ink).frame(width: 38, height: 38).background(Color.ink.opacity(0.1), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Group Chat").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let m { Text(m.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))).font(.system(size: 11)).foregroundStyle(Color.ink2) }
                    }
                    Text(m.map { "\(Agent.role($0.agent).name): \($0.text)" } ?? "Everyone, in one place")
                        .font(.system(size: 12)).foregroundStyle(Color.ink2).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == Self.group ? Color.ink.opacity(0.1) : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }.buttonStyle(.plain)
    }
}

extension Store {
    /// Every line an agent has logged (assignments, advice, finished work, the Manager's checks), oldest first. This is the group chat.
    // ponytail: read from the Activity Log (last 200 entries) rather than a second store; give it its own file if it should outlive that.
    var agentTalk: [Activity] { activity.filter { a in Agent.all.contains { $0.id == a.agent } }.reversed() }
}

/// The agents talking to each other: assignments, advice, results and checks, in the order they happened.
struct GroupChat: View {
    @Environment(Store.self) private var store
    var body: some View {
        let talk = store.agentTalk, ids = Agent.all.map(\.id)
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                HStack(spacing: -8) { ForEach(ids.prefix(6), id: \.self) { AgentPortrait(id: $0, size: 30) } }
                Text("Group Chat").font(.system(size: 12, weight: .semibold))
                Text("\(ids.count) agents · everything they say to each other").font(.system(size: 10)).foregroundStyle(Color.ink2)
            }
            Card {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if talk.isEmpty { Text("Nothing yet. When the Manager hands out a job, the agents will talk about it here.").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.top, 8) }
                            ForEach(Array(talk.enumerated()), id: \.element.id) { i, a in
                                let prev = i > 0 ? talk[i - 1] : nil
                                if prev == nil || a.time.timeIntervalSince(prev!.time) > 600 { IMStamp(date: a.time).padding(.top, i == 0 ? 0 : 8) }
                                VStack(alignment: .leading, spacing: 2) {
                                    if prev?.agent != a.agent { Text(Agent.role(a.agent).name).font(.system(size: 11)).foregroundStyle(Color.ink2).padding(.leading, 40) }
                                    HStack(alignment: .bottom, spacing: 6) {
                                        AgentPortrait(id: a.agent, size: 28)
                                        IMBubble(text: a.text, mine: false)
                                        Spacer(minLength: 56)
                                    }
                                }.id(a.id)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear { proxy.scrollTo(talk.last?.id, anchor: .bottom) }
                    .onChange(of: talk.count) { withAnimation { proxy.scrollTo(talk.last?.id, anchor: .bottom) } }
                }
            }
        }
    }
}

/// Every agent's chat in one inbox, with the Manager's menu.
struct MessagesPage: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Messages", subtitle: "\(Agent.courseRoles.count) course agents · \(Agent.roles.count) helpers · Manager") { ManagerMenu() }
            MessagesInbox().padding([.horizontal, .bottom], 12)
        }
    }
}
