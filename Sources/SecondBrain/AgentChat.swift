import SwiftUI

/// The conversation with one agent: messages, a busy indicator and the box to type in. Used on the agent's page.
struct AgentChatCard: View {
    @Environment(Store.self) private var store
    let code: String
    var suggest = false          // while the chat is empty, offer the agent's example questions
    @State private var draft = ""
    var role: Agent.Role { Agent.role(code) }
    var body: some View {
        let messages = store.chats[code] ?? []
        let busy = store.thinking.contains(code)
        Card {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if messages.isEmpty {
                            Text(code == Agent.manager.id ? "Tell me what you need. I pick the agent and how much effort it deserves, on your Mac for free, say why, then hand it over. Any agent can read your whole vault and change your notes when you ask; one that can’t do a request hands it back to me, and I pick another."
                                 : role.course != nil ? "Ask \(role.name) anything about \(role.job.replacingOccurrences(of: "Course agent · ", with: "")). It reads your notes and changes them when you ask."
                                 : "\(role.name) \(role.job.prefix(1).lowercased() + role.job.dropFirst()). It reads your whole vault and edits your notes when you ask\(Agent.deliverables(role.id).isEmpty ? "" : ", and makes new study notes")\(role.id == "researcher" ? " and research briefs" : ""); if it can’t do something it hands it to the Manager.")
                                .font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.top, 8)
                            if suggest {
                                VStack(spacing: 6) {
                                    ForEach(role.actions, id: \.self) { a in
                                        Button { store.ask(code, a) } label: {
                                            HStack(spacing: 8) { Image(systemName: "sparkle"); Text(a).multilineTextAlignment(.leading); Spacer(minLength: 0) }
                                                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 7)
                                        }.buttonStyle(.glassRow).disabled(busy)
                                    }
                                }
                            }
                        }
                        // found once for the whole list; checking the messages after each one made every redraw quadratic in the length of the chat
                        let lastMineAt = messages.lastIndex { !$0.fromAgent }, lastAnswerAt = messages.lastIndex { $0.fromAgent && !$0.text.hasPrefix("→") }   // a routing note isn't an answer
                        ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                            let prev = i > 0 ? messages[i - 1] : nil, next = i + 1 < messages.count ? messages[i + 1] : nil
                            let lastMine = i == lastMineAt
                            let replied = (lastAnswerAt ?? -1) > i
                            let receipt = lastMine ? self.receipt(after: i, in: messages, replied: replied, busy: busy) : nil
                            if prev == nil || m.time.timeIntervalSince(prev!.time) > 600 { IMStamp(date: m.time).padding(.top, i == 0 ? 0 : 8) }
                            MessageRow(message: m, firstInRun: prev?.fromAgent != m.fromAgent, lastInRun: next?.fromAgent != m.fromAgent || next?.text.hasPrefix("→") == true,
                                       receipt: receipt)
                                .id(m.id).appearIn().padding(.top, prev?.fromAgent == m.fromAgent ? -12 : 0)
                        }
                        if busy {
                            // what the agent has written so far, growing; the dots until its first words arrive
                            if let live = store.streaming[code], !live.senderAndBody.body.isEmpty {
                                HStack { IMBubble(text: live.senderAndBody.body, mine: false); Spacer(minLength: 56) }.id("busy")
                            } else { HStack { IMTyping(); Spacer() }.id("busy") }
                        }
                        if store.pausedUntil != nil {   // like Messages' "notifications silenced" line
                            Label("The Manager is paused: no background jobs. Chats still work.", systemImage: "moon.fill")
                                .font(.system(size: 10)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity).padding(.top, 4)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo(busy ? AnyHashable("busy") : AnyHashable(messages.last?.id), anchor: .bottom) } }
                .onChange(of: busy) { if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } } }
                .onChange(of: store.streaming[code]) { if busy { proxy.scrollTo("busy", anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                // "+": the agent's example requests, a tap away (Messages' + opens attachments)
                Menu {
                    ForEach(role.actions, id: \.self) { a in Button(a) { store.ask(code, a) } }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink2).frame(width: 30, height: 30).glassEffect(.regular.interactive(), in: .circle)
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().disabled(busy).help("Things to ask \(role.name)").accessibilityLabel("Ask something")
                HStack(spacing: 8) {
                    TextField(code == Agent.manager.id ? "Message the Manager" : "Message", text: $draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4).onSubmit { send() }
                    let ready = !busy && !draft.trimmingCharacters(in: .whitespaces).isEmpty
                    if busy {
                        Button { store.stopChat(code) } label: {
                            Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.white).frame(width: 24, height: 24).background(Color.ink2, in: .circle)
                        }.buttonStyle(.plain).help("Stop \(role.name)").accessibilityLabel("Stop")
                    } else if ready {
                        Button(action: send) {
                            Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white).frame(width: 24, height: 24).background(IM.blue, in: .circle)
                        }.buttonStyle(.plain).accessibilityLabel("Send")
                    }
                }
                .font(.system(size: 14)).padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4).frame(minHeight: 30)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
        }
    }
    /// Under your latest message, like Messages: "Read 13:06" once an agent has answered, "Delivered" while it works.
    private func receipt(after i: Int, in messages: [Message], replied: Bool, busy: Bool) -> String? {
        if replied, let at = messages[(i + 1)...].first(where: { $0.fromAgent && !$0.text.hasPrefix("→") })?.time {
            return "**Read** " + at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return busy ? "**Delivered**" : nil
    }
    func send() { store.ask(code, draft); draft = "" }
}
