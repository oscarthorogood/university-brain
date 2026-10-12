import SwiftUI

/// What the Manager has to say right now, as a few lines that each lead somewhere (Home, a course page, a note's agent tab), and on Home a box to ask it
/// something, with the latest answer under the lines.
struct AgentSays: View {
    @Environment(Store.self) private var store
    let says: [Say]
    var chat = true   // false: just the lines, no message box
    @State private var draft = ""
    @State private var dismissed: UUID?
    @State private var override: Manager.Tier?   // one-off: "keep it quick" or "think harder", for the next message only
    private let id = Agent.manager.id

    /// The latest thing you sent, then what came back (a note on the kind of work, then the answer).
    private struct Exchange { let sent: Message; let route: Message?; let answer: Message? }
    private var exchange: Exchange? {
        let msgs = store.chats[id] ?? []
        guard let i = msgs.lastIndex(where: { !$0.fromAgent }) else { return nil }
        let after = msgs[(i + 1)...]
        return Exchange(sent: msgs[i], route: after.first { $0.text.hasPrefix("→") }, answer: after.last { !$0.text.hasPrefix("→") })
    }
    private var busy: Bool { store.thinking.contains(id) }

    var body: some View {
        // an old answer doesn't greet you every time you come back
        let ex = (chat ? exchange : nil).flatMap { $0.sent.id == dismissed || ($0.sent.time < .now.addingTimeInterval(-900) && $0.answer != nil) ? nil : $0 }
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                AgentPortrait(id: id, size: 22)
                Text(Agent.manager.name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { store.page = .agent(id) } label: { Text("Open chat").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2) }
                    .buttonStyle(.plain).help("Open the conversation")
            }.padding(.horizontal, 14).padding(.top, 10)
            ScrollView {
                VStack(spacing: 2) { ForEach(Array(says.enumerated()), id: \.offset) { _, say in line(say) } }.padding(.horizontal, 6)
            }
            if let ex { reply(ex) }
            if chat { inputBar }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: ex?.answer?.id)
    }

    private func activate(_ say: Say) {
        if let prompt = say.askPrompt {
            store.ask(prompt)
            if let k = say.gotIt { store.gotIt(k) }
        } else if let go = say.go { store.page = go }
    }

    private func line(_ say: Say) -> some View {
        HStack(spacing: 6) {
            Button { activate(say) } label: {
                HStack(spacing: 8) {
                    Text(say.text).font(.system(size: 12)).multilineTextAlignment(.leading).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    if say.go != nil || say.askPrompt != nil {
                        Image(systemName: say.askPrompt == nil ? "chevron.right" : "arrow.up").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.ink2)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(.rect)
            }.buttonStyle(.glassRow).disabled(say.askPrompt != nil && busy)
            if let key = say.gotIt {
                Button { store.gotIt(key) } label: { Text("Got it").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.glassAction(.chip)).accessibilityLabel("Got it")
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the Manager…", text: $draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...3).onSubmit(send)
            Menu {
                Toggle("Automatic effort", isOn: Binding(get: { override == nil }, set: { if $0 { override = nil } }))
                Toggle("Keep it quick", isOn: Binding(get: { override == .quick }, set: { override = $0 ? .quick : nil }))
                Toggle("Think harder", isOn: Binding(get: { override == .deep }, set: { override = $0 ? .deep : nil }))
            } label: { Image(systemName: "speedometer").foregroundStyle(override == nil ? Color.ink2 : Color.ink).symbolVariant(override == nil ? .none : .fill) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(effortHelp).accessibilityLabel(effortHelp)
            Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.glassIcon(DS.Height.compact, prominent: true)).disabled(busy || draft.isEmpty)
                .opacity(busy || draft.isEmpty ? 0.4 : 1).accessibilityLabel("Send")
        }
        .font(.system(size: 13)).padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.tile + 4))
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private var effortHelp: String { override == nil ? "Effort: automatic" : override == .quick ? "Effort: quick, next message only" : "Effort: deep, next message only" }

    private func send() {
        guard !busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.ask(draft, tier: override); draft = ""; override = nil
    }

    /// What you said, the kind of work it was taken as, and the answer (scrolls when it is long).
    private func reply(_ ex: Exchange) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button { dismissed = ex.sent.id } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.ink2) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            HStack(spacing: 0) { Spacer(minLength: 40); IMBubble(text: ex.sent.text, mine: true, tail: true, size: 11).lineLimit(2) }
            if let r = ex.route { Text(LocalizedStringKey(r.text)).font(.system(size: 10)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity) }
            if let answer = ex.answer {
                ScrollView { HStack(spacing: 0) { IMBubble(text: answer.text.senderAndBody.body, mine: false, size: 12); Spacer(minLength: 24) } }.frame(maxHeight: 150)
            } else {
                HStack { IMTyping(); Spacer() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.tile))
        .padding(.horizontal, 12)
    }
}
