import SwiftUI
import AppKit

/// Chat looks like Apple Messages everywhere: your blue bubbles on the right, the agent's grey ones on the left, a small tail on the last bubble of a run
/// (and tighter spacing inside a run), centred time stamps, "Read 13:06" under your latest message, and three dots while the agent works.
enum IM {
    static let blue = Color(light: 0x0A84FF, dark: 0x0A84FF)
    static let grey = Color(light: 0xE9E9EB, dark: 0x303033)
    static func shape(mine: Bool, tail: Bool = true) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine || !tail ? 18 : 5, bottomTrailingRadius: mine && tail ? 5 : 18, topTrailingRadius: 18, style: .continuous)
    }
}

extension String {
    /// A message that starts "**Check found problems**\n\n…": the bold heading, then what it says.
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
            .background(mine ? IM.blue : IM.grey, in: IM.shape(mine: mine, tail: tail))
    }
}

/// The grey bubble with three bouncing dots.
struct IMTyping: View {
    var body: some View {
        TypingDots().padding(.horizontal, 16).padding(.vertical, 14)
            .background(IM.grey, in: IM.shape(mine: false))
    }
}

struct MessageRow: View {
    @Environment(Store.self) private var store
    let message: Message
    var firstInRun = true, lastInRun = true
    var receipt: String? = nil     // "**Read** 13:06" or "**Delivered**", under your latest message
    var showChips = false          // quick replies appear only under the newest message
    @State private var whyOpen = false
    @State private var why = ""
    var body: some View {
        let mine = !message.fromAgent
        if !mine && message.text.hasPrefix("→") {   // which kind of work it took your request as
            Text(LocalizedStringKey(message.text)).font(.system(size: 11)).foregroundStyle(Color.ink2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        } else {
            let (sender, text) = mine ? (nil, message.text) : message.text.senderAndBody
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if let sender, firstInRun { Text(sender).font(.system(size: 11)).foregroundStyle(Color.ink2).padding(.leading, 12) }
                HStack(spacing: 0) {
                    if mine { Spacer(minLength: 56) }
                    IMBubble(text: text, mine: mine, tail: lastInRun)
                        .overlay(alignment: .topTrailing) { if !mine, let reaction = message.reaction { Tapback(kind: reaction).offset(x: 8, y: -9) } }
                        .contextMenu { menu(text: text, mine: mine) }
                        .popover(isPresented: $whyOpen, arrowEdge: .bottom) { whyForm }
                    if !mine { Spacer(minLength: 56) }
                }
                if let change = message.change { ChangeCard(id: change).padding(.top, 4) }
                if showChips, let chips = message.chips, !chips.isEmpty { ChipRow(chips: chips, message: message.id).padding(.top, 4) }
                if let receipt { Text(LocalizedStringKey(receipt)).font(.system(size: 10)).foregroundStyle(Color.ink2).padding(.trailing, 4) }
            }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    /// Right-click, the Mac's long-press: a tapback on the Manager's answer, or a copy.
    @ViewBuilder private func menu(text: String, mine: Bool) -> some View {
        if !mine {
            Button { store.react(message.id, "up") } label: { Label("Helpful", systemImage: "hand.thumbsup") }
            Button { whyOpen = true } label: { Label("Not right…", systemImage: "hand.thumbsdown") }
            Button { store.react(message.id, "ask"); store.ask("Explain your last answer: what you did, which notes you used, and why.") } label: { Label("Explain", systemImage: "questionmark.bubble") }
            Divider()
        }
        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }
    }

    /// "Not right": what was wrong, in a few words. It is kept as a rule the Manager reads before its next piece of that kind of work.
    private var whyForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What was wrong with that?").font(.system(size: 13, weight: .semibold))
            Text("Say it in a few words and I'll keep it as a rule for next time.").font(.system(size: 11)).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
            TextField("Too long, wrong course, not my style…", text: $why).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Just mark it") { store.react(message.id, "down"); close() }
                Button("Add rule", action: save).keyboardShortcut(.defaultAction).disabled(why.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(14).frame(width: 300)
    }
    private func save() {
        guard !why.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.react(message.id, "down", reason: why); close()
    }
    private func close() { whyOpen = false; why = "" }
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

extension Store {
    /// Short enough for a text.
    func clipped(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > n ? String(t.prefix(n)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" : t
    }
}
