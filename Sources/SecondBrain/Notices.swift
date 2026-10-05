import SwiftUI

/// One thing the app wants you to know, from anywhere in it.
struct AppNotice: Identifiable {
    let id: String; let source: String; let icon: String; let tint: Color
    let title: String; var body = ""; var time = ""; var go: Page? = nil
}

extension Store {
    static func until(_ d: Date) -> String {
        let h = Int(d.timeIntervalSinceNow / 3600)
        return h < 1 ? "soon" : h < 24 ? "in \(h)h" : "in \(h / 24)d"
    }

    /// Agents that need you, work in progress and just finished, the Manager's heads-ups, what's coming up and what's waiting in Unsorted.
    func notices() -> [AppNotice] {
        var out: [AppNotice] = []
        for (id, list) in needs.sorted(by: { $0.key < $1.key }) {
            guard let n = list.first else { continue }
            out.append(AppNotice(id: "need-\(id)-\(n.id)", source: "Agents", icon: "person.fill", tint: Agent.color(id), title: "\(Agent.role(id).name) needs you", body: n.title, time: list.count > 1 ? "+\(list.count - 1)" : "", go: n.open ?? .agent(id)))
        }
        for j in activeJobs {
            out.append(AppNotice(id: "job-\(j.id)", source: "Agents", icon: "sparkles", tint: Agent.color(j.agent), title: "\(Agent.role(j.agent).name) is working", body: j.title, time: "now", go: .messages))
        }
        for j in inbox.reversed() where [.done, .failed, .rejected].contains(j.state) && j.created > .now.addingTimeInterval(-12 * 3600) {
            let note = j.paths.first.flatMap { p in notes.first { Vault.rel($0.id) == p } }
            let verb = j.state == .done ? "finished" : j.state == .failed ? "couldn’t finish" : "was sent back"
            out.append(AppNotice(id: "done-\(j.id)", source: "Agents", icon: j.state == .done ? "checkmark" : "exclamationmark", tint: j.state == .done ? NoteColor.done : Color.redFG,
                                 title: "\(Agent.role(j.agent).name) \(verb)", body: j.title, time: j.created.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)), go: note.map { .note($0.id) } ?? .messages))
        }
        for h in headsUps().prefix(3) {
            out.append(AppNotice(id: "heads-\(h.gotIt ?? h.text)", source: "Manager", icon: "bell.fill", tint: Color(light: 0xC77A00, dark: 0xF0B366), title: h.text, go: h.go))
        }
        for n in upcoming(3) {
            let w = n.when!, isClass = ["Lectures", "Tutorials"].contains(n.folder)
            out.append(AppNotice(id: "up-\(n.id.path)", source: isClass ? "Classes" : "Deadlines", icon: isClass ? "play.rectangle.fill" : "flag.fill", tint: Color.course(n.course), title: n.display,
                                 body: isClass ? w.formatted(.dateTime.weekday(.abbreviated).hour().minute()) : "Due " + w.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                                 time: isClass || days(w) == 0 ? Self.until(w) : "\(days(w))d", go: .note(n.id)))
        }
        if let first = unsorted.first {
            out.append(AppNotice(id: "unsorted-\(unsorted.count)", source: "Unsorted", icon: "tray.fill", tint: IM.blue, title: "\(unsorted.count) file\(unsorted.count == 1 ? "" : "s") waiting", body: Vault.label(first), go: .inbox))
        }
        return Array(out.prefix(15))
    }
}

/// The box at the bottom of the sidebar: notifications as stacked cards, like the system's.
struct NoticeBox: View {
    @Environment(Store.self) private var store
    @State private var dismissed: Set<String> = []
    var body: some View {
        let items = store.notices().filter { !dismissed.contains($0.id) }
        Group {
            if items.isEmpty {
                VStack(spacing: 6) { Image(systemName: "bell.slash").font(.system(size: 18)); Text("No notifications").font(.system(size: 12)) }
                    .foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) { ForEach(items) { n in NoticeCard(notice: n) { withAnimation(.spring(duration: 0.3)) { _ = dismissed.insert(n.id) } } } }.padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }
        }
        .frame(minHeight: 110)
        .animation(.spring(duration: 0.35), value: items.map(\.id))
    }
}

struct NoticeCard: View {
    @Environment(Store.self) private var store
    let notice: AppNotice; let dismiss: () -> Void
    @State private var hover = false
    var body: some View {
        Button { if let go = notice.go { store.page = go } } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: notice.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(notice.tint)
                    .frame(width: 28, height: 28).background(notice.tint.opacity(0.18), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(notice.source.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(Color.ink2)
                        Spacer(minLength: 2)
                        if hover { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color.ink2).onTapGesture(perform: dismiss).accessibilityLabel("Dismiss") }
                        else { Text(notice.time).font(.system(size: 10)).foregroundStyle(Color.ink2) }
                    }
                    Text(notice.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if !notice.body.isEmpty { Text(notice.body).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(2).multilineTextAlignment(.leading) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 8).contentShape(.rect(cornerRadius: 14))
            .glassEffect(.regular.tint(notice.tint.opacity(0.07)), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.pressScale).onHover { hover = $0 }.accessibilityLabel("\(notice.source): \(notice.title). \(notice.body)")
    }
}
