import SwiftUI

/// The small round badge a tapback leaves on a bubble's corner.
struct Tapback: View {
    let kind: String
    var body: some View {
        Image(systemName: kind == "up" ? "hand.thumbsup.fill" : kind == "down" ? "hand.thumbsdown.fill" : "questionmark")
            .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white)
            .frame(width: 20, height: 20)
            .background(kind == "down" ? Color.gray : IM.blue, in: .circle)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .accessibilityLabel(kind == "up" ? "Marked helpful" : kind == "down" ? "Marked not right" : "Asked for an explanation")
    }
}

/// Quick replies under the Manager's latest message, like the suggestions Messages offers. Tapping one sends it.
struct ChipRow: View {
    @Environment(Store.self) private var store
    let chips: [Message.Chip]
    let message: UUID
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button { store.useChip(message, chip) } label: {
                        Text(chip.label).font(.system(size: 12, weight: .medium)).foregroundStyle(IM.blue)
                            .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.interactive(), in: .capsule)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// What a job or an edit changed, in the conversation: the notes (each opens), the Manager's verdict and an Undo, so you never have to find the Activity Log.
struct ChangeCard: View {
    @Environment(Store.self) private var store
    let id: UUID
    var body: some View {
        if let item = store.inbox.first(where: { $0.id == id }) {
            let rels = (item.undo?.restore ?? []) + (item.undo?.created ?? []), undone = item.undo == nil
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill").foregroundStyle(undone ? Color.ink2 : IM.blue)
                    Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                ForEach(rels.prefix(4), id: \.self) { rel in
                    Button { open(rel) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").font(.system(size: 10))
                            Text(((rel as NSString).lastPathComponent as NSString).deletingPathExtension).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 0)
                        }.foregroundStyle(Color.ink).contentShape(.rect)
                    }.buttonStyle(.plain).help("Open this note")
                }
                if rels.count > 4 { Text("and \(rels.count - 4) more").font(.system(size: 11)).foregroundStyle(Color.ink2) }
                HStack(spacing: 8) {
                    if store.canUndo(id) { Button("Undo") { store.undoJob(id) }.help("Put the notes back as they were") }
                    else if undone { Text("Undone").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2) }
                    if let verdict = item.verdict, !undone { Text(verdict).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1) }
                }
            }
            .padding(12).frame(maxWidth: 320, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }
    private func open(_ rel: String) {
        if let note = store.notes.first(where: { Vault.rel($0.id) == rel }) { store.page = .note(note.id) }
    }
}
