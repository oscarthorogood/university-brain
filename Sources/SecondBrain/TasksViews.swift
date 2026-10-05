import SwiftUI

/// Tasks as a board (columns by status; drag a card to change it) and as an agenda (the next two weeks, day by day).
struct TasksBoard: View {
    @Environment(Store.self) private var store
    static let columns = TaskState.allCases.map(\.rawValue)
    var items: [Note]? = nil   // Week and Month pass the notes in their range; the Tasks page leaves it to show every task
    var body: some View {
        let items = items ?? store.notes.filter { n in
            guard ["TaskNotes/Tasks", "Essays", "Projects"].contains(n.folder), !n.status.isEmpty else { return false }
            return n.folder == "TaskNotes/Tasks" || (n.course != nil && store.isCurrentSemester(n))
        }
        HStack(alignment: .top, spacing: 12) {
            ForEach(Self.columns, id: \.self) { col in
                let cards = items.filter { ($0.status == col) || (col == "Not started" && !Self.columns.contains($0.status)) }
                    .sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }
                Card(title: col, trailing: "\(cards.count)") {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(col == "Done" ? Array(cards.reversed().prefix(15)) : cards) { n in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(n.display).font(.system(size: 13)).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.course(n.course)).frame(width: 7, height: 7)
                                        Text([n.kind, n.when.map { $0.formatted(.dateTime.day().month(.abbreviated)) }].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Color.ink2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.row))
                                .contentShape(.rect).onTapGesture { store.page = .note(n.id) }
                                .draggable(n.id.absoluteString)
                            }
                        }.padding(.horizontal, 8).padding(.bottom, 10)
                    }
                }
                .dropDestination(for: String.self) { dropped, _ in
                    for s in dropped {
                        guard let url = URL(string: s), let n = store.notes.first(where: { $0.id == url }), n.status != col else { continue }
                        do { try Vault.setStatus(n, to: col) } catch { store.error = "Couldn’t update \(n.title): \(error.localizedDescription)" }
                    }
                    store.reload(); return true
                }
            }
        }
    }
}

struct TasksAgenda: View {
    @Environment(Store.self) private var store
    var body: some View {
        let end = Calendar.current.date(byAdding: .day, value: 14, to: store.today)!
        let items = store.notes.filter { n in
            guard let w = n.when, !n.done, w >= store.today, w < end else { return false }
            return n.course != nil || n.folder == "TaskNotes/Tasks"
        }
        let days = Dictionary(grouping: items, by: { Calendar.current.startOfDay(for: $0.when!) }).sorted { $0.key < $1.key }
        Card(title: "Next two weeks", trailing: "\(items.count)") {
            if items.isEmpty { Text("Nothing in the next two weeks").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.key) { day, notes in
                            Heading(Calendar.current.isDateInToday(day) ? "Today" : Calendar.current.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)), trailing: "\(notes.count)")
                            ForEach(notes.sorted { $0.when! < $1.when! }) { NoteRow(note: $0, timeColumn: true) }
                        }
                    }
                }
            }
        }
    }
}
