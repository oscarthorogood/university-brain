import SwiftUI

/// One job the Manager is running for you (from Sort Now, File Now or a note's button): the work, the check, and the outcome with an Undo.
struct JobProgress: View {
    @Environment(Store.self) private var store
    let key: String; let finished: Bool
    var body: some View {
        let item = store.inbox.last { $0.key == key }
        VStack(alignment: .leading, spacing: 10) {
            if let item {
                HStack(spacing: 8) {
                    if [.planning, .consulting, .working, .checking].contains(item.state) { ProgressView().controlSize(.small) }
                    else { Image(systemName: item.state == .done ? "checkmark.circle.fill" : "exclamationmark.triangle").foregroundStyle(item.state == .done ? Color(light: 0x2F8467, dark: 0x5CC39A) : Color.redFG) }
                    Text(status(item)).font(.system(size: 13, weight: .medium))
                }
                if let a = item.advice { DisclosureGroup("Course context") { Text(a).font(.system(size: 12)).foregroundStyle(Color.ink2).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 12)) }
                if [.done, .rejected, .failed].contains(item.state), let r = item.result, !r.isEmpty {
                    ScrollView { Text(LocalizedStringKey(r)).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 260)
                }
                if let v = item.verdict { Text(v).font(.caption).foregroundStyle(Color.ink2) }
                if store.canUndo(item.id) { Button("Undo") { store.undoJob(item.id) }.buttonStyle(.glassAction(.control)).help("Put the note or files back as they were") }
            } else if finished {
                Text("Nothing needed doing.").font(.system(size: 13)).foregroundStyle(Color.ink2)
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Waiting for the Manager…").font(.system(size: 13)).foregroundStyle(Color.ink2) }
            }
        }
    }
    func status(_ i: InboxItem) -> String {
        let who = Agent.label(i.agent)
        switch i.state {
        case .planning: return "The Manager is picking it up…"
        case .consulting: return "Getting the course context…"
        case .working: return "Working on it (\(who))…"
        case .checking: return "The Manager is checking the result…"
        case .done: return "Done. " + (i.verdict ?? "")
        case .rejected: return "The Manager rejected it and put it back."
        case .failed: return "Didn’t finish the \(who) work."
        default: return ""
        }
    }
}
