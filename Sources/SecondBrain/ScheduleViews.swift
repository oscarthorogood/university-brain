import SwiftUI

/// The ways Week and Month can show the same notes. Calendar is each page's own layout; the rest take the notes in range.
enum ScheduleView: String, CaseIterable, Identifiable {
    case calendar = "Calendar", list = "List", board = "Board", timeline = "Timeline", tree = "Tree"
    var id: Self { self }
    var icon: String { ["Calendar": "calendar", "List": "list.bullet", "Board": "rectangle.split.3x1", "Timeline": "chart.bar.xaxis", "Tree": "list.bullet.indent"][rawValue] ?? "calendar" }
}

/// The view dropdown in a page header.
struct ViewMenu: View {
    @Binding var selection: ScheduleView
    var body: some View {
        Menu {
            Picker("View", selection: $selection) { ForEach(ScheduleView.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }.pickerStyle(.inline)
        } label: { Label(selection.rawValue, systemImage: selection.icon) }
            .menuStyle(.button).buttonStyle(.glassAction(.header)).fixedSize().help("Choose a view")
    }
}

/// Everything in range, in the view picked. `days` are the days the range covers (the Timeline's columns).
struct ScheduleBody: View {
    let mode: ScheduleView; let notes: [Note]; let days: [Date]
    var body: some View {
        switch mode {
        case .calendar, .list: ScheduleTable(notes: notes)
        case .board: TasksBoard(items: notes)
        case .timeline: ScheduleTimeline(notes: notes, days: days)
        case .tree: ScheduleTree(notes: notes)
        }
    }
}

/// List: one row per note with columns you can sort by.
struct ScheduleTable: View {
    @Environment(Store.self) private var store
    @State private var key = "Date"
    @State private var up = true
    static let columns = ["Title", "Course", "Type", "Date", "Status"]
    func value(_ n: Note) -> String {
        switch key {
        case "Title": n.display.lowercased()
        case "Course": n.course ?? "~"
        case "Type": n.kind
        case "Status": n.status
        default: n.when.map { String($0.timeIntervalSince1970) } ?? "~"
        }
    }
    let notes: [Note]
    var body: some View {
        let rows = notes.map { (note: $0, key: value($0)) }.sorted { up ? $0.key < $1.key : $0.key > $1.key }.map(\.note)
        Card(title: "\(rows.count) items") {
            if rows.isEmpty { Text("Nothing in this range").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 22, height: 1)
                        ForEach(Self.columns, id: \.self) { c in
                            Button { if key == c { up.toggle() } else { key = c; up = true } } label: {
                                HStack(spacing: 3) { Text(c); if key == c { Image(systemName: up ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) } }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).frame(maxWidth: Self.width(c), alignment: .leading)
                        }
                    }.font(.caption.weight(.semibold)).foregroundStyle(Color.ink2).padding(.horizontal, 14).padding(.vertical, 8)
                    Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1)
                    ScrollView { LazyVStack(spacing: 0) { ForEach(rows) { TableRow(note: $0) } } }
                }
            }
        }
    }
    static func width(_ c: String) -> CGFloat { ["Title": .infinity, "Course": 70, "Type": 80, "Date": 110, "Status": 90][c] ?? 90 }
}

private struct TableRow: View {
    @Environment(Store.self) private var store
    let note: Note
    var body: some View {
        HStack(spacing: 8) {
            StatusButton(note: note).frame(width: 22)
            Button { store.page = .note(note.id) } label: {
                HStack(spacing: 8) {
                    Text(note.display).lineLimit(1).foregroundStyle(note.done ? Color.ink2 : Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) { Circle().fill(Color.course(note.course)).frame(width: 7, height: 7); Text(note.course ?? "—") }.frame(maxWidth: ScheduleTable.width("Course"), alignment: .leading)
                    Text(note.kind).frame(maxWidth: ScheduleTable.width("Type"), alignment: .leading)
                    Text(note.when.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "—").monospacedDigit().frame(maxWidth: ScheduleTable.width("Date"), alignment: .leading)
                    Text(note.status.isEmpty ? "—" : note.status).frame(maxWidth: ScheduleTable.width("Status"), alignment: .leading)
                }.font(.system(size: 12)).contentShape(.rect)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 14).padding(.vertical, 7).modifier(GlassRowHover())
    }
}

/// Timeline: a row per course, a column per day, each note a chip on its day. Notes carry one date, not a span, so there are no bars.
struct ScheduleTimeline: View {
    @Environment(Store.self) private var store
    let notes: [Note]; let days: [Date]
    var body: some View {
        let cal = Calendar.current, colW = max(CGFloat(days.count > 10 ? 52 : 120), 0)
        let rows: [(String, String?)] = Vault.courses.values.sorted().map { ($0, $0) } + [("Other", nil)]
        Card(title: "\(notes.count) items") {
            GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .topLeading, horizontalSpacing: 4, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 56, height: 1)
                        ForEach(days, id: \.self) { d in
                            VStack(spacing: 1) {
                                Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 10)).foregroundStyle(Color.ink2)
                                Text(d.formatted(.dateTime.day())).font(.system(size: 12, weight: cal.isDateInToday(d) ? .bold : .regular)).monospacedDigit()
                                    .foregroundStyle(cal.isDateInToday(d) ? Color.card : Color.ink).frame(width: 24, height: 24).background(cal.isDateInToday(d) ? Color.ink : .clear, in: .circle)
                            }.frame(width: colW)
                        }
                    }
                    ForEach(rows, id: \.0) { label, code in
                        let mine = notes.filter { $0.course == code }
                        if code != nil || !mine.isEmpty {
                            GridRow {
                                HStack(spacing: 4) { Circle().fill(Color.course(code)).frame(width: 7, height: 7); Text(label).font(.system(size: 11, weight: .semibold)) }.frame(width: 56, alignment: .leading).padding(.top, 8)
                                ForEach(days, id: \.self) { d in
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(mine.filter { $0.when.map { cal.isDate($0, inSameDayAs: d) } == true }.sorted { $0.whenOrFar < $1.whenOrFar }) { n in
                                            Button { store.page = .note(n.id) } label: {
                                                Text(colW > 60 ? n.display : String(n.kind.prefix(1))).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                                    .padding(.horizontal, 5).padding(.vertical, 3).frame(maxWidth: .infinity, alignment: colW > 60 ? .leading : .center)
                                                    .background(Color.course(code).opacity(n.done ? 0.12 : 0.28), in: .rect(cornerRadius: 6))
                                            }.buttonStyle(.plain).help("\(n.kind): \(n.display)")
                                        }
                                    }.frame(width: colW, alignment: .topLeading).frame(minHeight: 30, alignment: .topLeading).padding(2)
                                    .background(Color.ink.opacity(cal.isDateInToday(d) ? 0.06 : 0.025), in: .rect(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }.padding(12).frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
            }
        }
    }
}

/// Tree: course → type → note, each level folds.
struct ScheduleTree: View {
    @Environment(Store.self) private var store
    @State private var folded: Set<String> = []
    let notes: [Note]
    var body: some View {
        let courses = (Vault.courses.values.sorted() + ["Other"]).compactMap { code -> (String, [Note])? in
            let mine = notes.filter { ($0.course ?? "Other") == code }
            return mine.isEmpty ? nil : (code, mine)
        }
        Card(title: "\(notes.count) items") {
            if notes.isEmpty { Text("Nothing in this range").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(courses, id: \.0) { code, mine in
                            node(code, depth: 0, count: mine.count, dot: Color.course(code == "Other" ? nil : code)) {
                                ForEach(Dictionary(grouping: mine, by: \.kind).sorted { $0.key < $1.key }, id: \.key) { kind, group in
                                    node(code + kind, depth: 1, count: group.count, title: kind + "s", dot: nil) {
                                        ForEach(group.sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }) { n in
                                            Button { store.page = .note(n.id) } label: {
                                                HStack {
                                                    Text(n.display).lineLimit(1).foregroundStyle(n.done ? Color.ink2 : Color.ink)
                                                    Spacer()
                                                    Text(n.when.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "").foregroundStyle(Color.ink2).monospacedDigit()
                                                }.font(.system(size: 12)).padding(.leading, 56).padding(.trailing, 14).padding(.vertical, 5).contentShape(.rect)
                                            }.buttonStyle(.plain).modifier(GlassRowHover())
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(8)
                }
            }
        }
    }
    @ViewBuilder func node<C: View>(_ id: String, depth: Int, count: Int, title: String? = nil, dot: Color?, @ViewBuilder _ children: () -> C) -> some View {
        let open = !folded.contains(id)
        Button { withAnimation(.spring(duration: 0.25)) { if open { folded.insert(id) } else { folded.remove(id) } } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title ?? id).fontWeight(.semibold); Text("\(count)").foregroundStyle(Color.ink2); Spacer()
            }.font(.system(size: 13)).padding(.leading, 14 + CGFloat(depth) * 22).padding(.vertical, 6).contentShape(.rect)
        }.buttonStyle(.plain)
        if open { children() }
    }
}
