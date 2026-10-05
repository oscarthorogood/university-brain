import SwiftUI

/// An agent standing in the middle with a few bubbles around him saying what matters now (the Manager on Today, a course
/// agent on its course page), a chat box below, and replies that grow out of him as a bubble.
struct AgentStage: View {
    @Environment(Store.self) private var store
    let id: String
    let says: [Say]
    var chat = true   // false: just the agent and its bubbles, no message box
    @State private var draft = ""
    @State private var dismissed: UUID?
    @State private var hover = false
    @State private var override: Manager.Tier?   // one-off: "keep it quick" or "think harder", for the next message only
    private var role: Agent.Role { Agent.role(id) }

    /// The latest thing you sent him, then what came back (a routing line, then the agent's answer).
    private struct Exchange { let sent: Message; let route: Message?; let answer: Message? }
    private var exchange: Exchange? {
        let msgs = store.chats[id] ?? []
        guard let i = msgs.lastIndex(where: { !$0.fromAgent }) else { return nil }
        let after = msgs[(i + 1)...]
        return Exchange(sent: msgs[i], route: after.first { $0.text.hasPrefix("→") }, answer: after.last { !$0.text.hasPrefix("→") })
    }

    private struct Slot { let x: CGFloat, y: CGFloat, w: CGFloat; var h: CGFloat? = nil; let tail: BubbleShape.Tail; let align: Alignment }

    var body: some View {
        // an old answer doesn't greet you every time you come back
        let ex = (chat ? exchange : nil).flatMap { $0.sent.id == dismissed || ($0.sent.time < .now.addingTimeInterval(-900) && $0.answer != nil) ? nil : $0 }
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let bar: CGFloat = chat ? 60 : 6, figH = min(h * 0.46, 160) * (ex == nil ? 1 : 0.62), figW = figH * 62 / 112   // he steps back while a reply is up, so it has room
            let figTop = h - bar - figH - 2
            let flank = max(70, w / 2 - figW / 2 - 14)
            let headTop = figTop + figH * 0.14, bh: CGFloat = 84   // top bubbles sit on the bottom of an 84pt-tall box (room for a button under the text) so their tails land by his head
            let slots = [Slot(x: 8, y: headTop - 2 - bh, w: w * 0.58 - 8, h: bh, tail: .bottom, align: .trailing),
                         Slot(x: w * 0.42, y: headTop - 50 - bh, w: w * 0.58 - 8, h: bh, tail: .bottom, align: .leading),
                         Slot(x: 8, y: figTop + figH * 0.34, w: flank, tail: .right, align: .trailing),
                         Slot(x: w / 2 + figW / 2 + 6, y: figTop + figH * 0.5, w: flank, tail: .left, align: .leading)]
            let n = min(slots.count, says.count)
            ZStack(alignment: .topLeading) {
                ForEach(0..<n, id: \.self) { i in
                    SayBubble(lines: stride(from: i, to: says.count, by: n).map { says[$0] }, delay: Double(i) * 1.3, tail: slots[i].tail, align: slots[i].align) { store.page = $0 }
                        .frame(width: slots[i].w, height: slots[i].h, alignment: Alignment(horizontal: slots[i].align.horizontal, vertical: .bottom))
                        .offset(x: slots[i].x, y: slots[i].y)
                }
                .opacity(ex == nil ? 1 : 0.12).allowsHitTesting(ex == nil)

                Button { store.page = .agent(id) } label: { MiniAgent(id: id, hover: hover).frame(width: figW, height: figH) }
                    .buttonStyle(.plain).onHover { hover = $0 }
                    .help("Open \(role.name)").accessibilityLabel("Open \(role.name)")
                    .contextMenu { AgentMenu(role: role) }
                    .position(x: w / 2, y: figTop + figH / 2)

                if let ex {   // grows out of his head
                    reply(ex, cap: max(50, figTop + figH * 0.1 - 85))
                        .frame(width: w - 24, height: figTop + figH * 0.1, alignment: .bottom).offset(x: 12)
                        .transition(.scale(scale: 0.1, anchor: .bottom).combined(with: .opacity))
                }

                if chat { HStack(spacing: 8) {
                    TextField("Ask \(role.name)…", text: $draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...3).onSubmit(send)
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
                .frame(width: w - 24).offset(x: 12, y: h - bar + 8) }
            }
            .animation(.spring(duration: 0.5, bounce: 0.25), value: ex?.sent.id)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: ex?.answer?.id)
        }
    }

    private var busy: Bool { store.thinking.contains(id) }
    private var effortHelp: String { override == nil ? "Effort: automatic" : override == .quick ? "Effort: quick, next message only" : "Effort: deep, next message only" }

    private func send() {
        guard !busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.ask(id, draft, tier: override); draft = ""; override = nil
    }

    /// What you said, who it went to, and the answer (scrolls when it is long).
    private func reply(_ ex: Exchange, cap: CGFloat) -> some View {
        let answer = ex.answer.map { $0.text.senderAndBody }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if ex.answer != nil { Button("Open chat") { store.page = .agent(id) }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.ink2) }
                Button { dismissed = ex.sent.id } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.ink2) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            HStack(spacing: 0) { Spacer(minLength: 40); IMBubble(text: ex.sent.text, mine: true, tail: true, size: 11).lineLimit(2) }
            if let r = ex.route { Text(LocalizedStringKey(r.text)).font(.system(size: 10)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity) }
            if let (sender, text) = answer {
                if let sender { Text(sender).font(.system(size: 10)).foregroundStyle(Color.ink2).padding(.leading, 10) }
                HStack(spacing: 0) {
                    ViewThatFits(in: .vertical) {
                        IMBubble(text: text, mine: false, size: 12)
                        ScrollView { IMBubble(text: text, mine: false, size: 12) }
                    }.frame(maxHeight: cap)
                    Spacer(minLength: 24)
                }
            } else {
                HStack { IMTyping(); Spacer() }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 22)
        .glassEffect(.regular, in: BubbleShape(tail: .bottom, radius: DS.Radius.tile, tailAt: 0.5))
    }
}
