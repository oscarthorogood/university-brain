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
                            Text(code == Agent.manager.id ? "Tell me what you need. I pick the agent and how much effort it deserves, on your Mac for free, say why, then hand it over. Agents can read your whole vault and make study notes from chat; edits to your own notes go through reviewed jobs."
                                 : role.course != nil ? "Ask \(role.name) anything about \(role.job.replacingOccurrences(of: "Course agent · ", with: "")). It reads your notes and doesn’t change them from chat."
                                 : "\(role.name) \(role.job.prefix(1).lowercased() + role.job.dropFirst()). It reads your whole vault; from chat it writes only in its own folder\(Agent.deliverables(role.id).isEmpty ? "" : " and makes new study notes")\(role.id == "researcher" ? " and research briefs" : ""), never changing your notes.")
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
                            if prev == nil || m.time.timeIntervalSince(prev!.time) > 600 { IMStamp(date: m.time).padding(.top, i == 0 ? 0 : 8) }
                            MessageRow(message: m, firstInRun: prev?.fromAgent != m.fromAgent, lastInRun: next?.fromAgent != m.fromAgent || next?.text.hasPrefix("→") == true,
                                       receipt: lastMine ? (replied ? "Read" : (busy ? "Delivered" : nil)) : nil)
                                .id(m.id).appearIn().padding(.top, prev?.fromAgent == m.fromAgent ? -12 : 0)
                        }
                        if busy {
                            // what the agent has written so far, growing; the dots until its first words arrive
                            if let live = store.streaming[code], !live.senderAndBody.body.isEmpty {
                                HStack { IMBubble(text: live.senderAndBody.body, mine: false); Spacer(minLength: 56) }.id("busy")
                            } else { HStack { IMTyping(); Spacer() }.id("busy") }
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo(busy ? AnyHashable("busy") : AnyHashable(messages.last?.id), anchor: .bottom) } }
                .onChange(of: busy) { if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } } }
                .onChange(of: store.streaming[code]) { if busy { proxy.scrollTo("busy", anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                TextField(code == Agent.manager.id ? "What do you need?" : "Message \(role.name)", text: $draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4).onSubmit { send() }
                let ready = !busy && !draft.trimmingCharacters(in: .whitespaces).isEmpty
                if busy {
                    Button { store.stopChat(code) } label: {
                        Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.ink)
                            .frame(width: 28, height: 28).glassEffect(.regular.interactive(), in: .circle)
                    }.buttonStyle(.plain).help("Stop \(role.name)").accessibilityLabel("Stop")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(ready ? Color.white : Color.ink2)
                            .frame(width: 28, height: 28).glassEffect(ready ? .regular.tint(IM.blue).interactive() : .regular, in: .circle)
                    }.buttonStyle(.plain).disabled(!ready).accessibilityLabel("Send")
                }
            }
            .font(.system(size: 14)).padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
        }
    }
    func send() { store.ask(code, draft); draft = "" }
}
