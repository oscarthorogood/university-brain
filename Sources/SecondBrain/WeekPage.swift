import SwiftUI

extension Store {
    /// Items for a weekday column. Friday also collects the weekend so Sunday deadlines don't vanish.
    func weekItems(_ folders: Set<String>, on day: Date) -> [Note] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: cal.component(.weekday, from: day) == 6 ? 3 : 1, to: start)!
        return notes.filter { n in
            guard folders.contains(n.folder), let w = n.when, matches(n) else { return false }
            return w >= start && w < end
        }.sorted { $0.whenOrFar < $1.whenOrFar }
    }
    /// Everything a week block shows.
    func weekNotes(_ monday: Date) -> [Note] { WeekBlock.rows.flatMap { r in WeekBlock.days(monday).flatMap { weekItems(r.1, on: $0) } } }
}

/// One week, Mon–Fri columns split into classes, assignments and readings. Week, Month and Semester are all built from these.
struct WeekBlock: View {
    @Environment(Store.self) private var store
    let monday: Date
    static let rows: [(String, Set<String>)] = [("Lectures & Tutorials", ["Lectures", "Tutorials"]),
                                                ("Assignments", ["Essays", "Projects", "Exams", "TaskNotes/Tasks"]),
                                                ("Readings", ["Readings"])]
    static func days(_ monday: Date) -> [Date] { (0..<5).map { Calendar.current.date(byAdding: .day, value: $0, to: monday)! } }
    static func monday(of d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -((cal.component(.weekday, from: d) + 5) % 7), to: cal.startOfDay(for: d))!
    }
    var body: some View {
        let cal = Calendar.current, days = Self.days(monday)
        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                ForEach(days, id: \.self) { d in
                    let today = cal.isDateInToday(d)
                    HStack(spacing: 6) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated))).foregroundStyle(Color.ink2)
                        Text(d.formatted(.dateTime.day())).monospacedDigit().fontWeight(today ? .bold : .regular)
                            .foregroundStyle(today ? Color.card : Color.ink).frame(minWidth: 24, minHeight: 24).background(today ? Color.ink : .clear, in: .circle)
                    }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                }
            }
            ForEach(Self.rows, id: \.0) { title, folders in
                let count = days.map { store.weekItems(folders, on: $0).count }.reduce(0, +)
                GridRow {
                    Text("\(title) · \(count)").font(.caption.weight(.semibold)).foregroundStyle(Color.ink2)
                        .padding(.top, 10).padding(.horizontal, 8).gridCellColumns(5)
                }
                GridRow {
                    ForEach(days, id: \.self) { d in
                        let list = store.weekItems(folders, on: d)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(list) { WeekRow(note: $0, day: d) }
                            if list.isEmpty { Text("—").font(.system(size: 12)).foregroundStyle(Color.ink2.opacity(0.5)).padding(8) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading).padding(4)
                        .background(Color.ink.opacity(cal.isDateInToday(d) ? 0.06 : 0.025), in: .rect(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

/// The card that holds the week grid(s): scrolls both ways, never narrower than the five columns need.
struct ScheduleCard<Content: View>: View {
    @ViewBuilder var content: (ScrollViewProxy) -> Content
    var body: some View {
        Card {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        content(proxy).padding(12).frame(width: max(geo.size.width, 680), alignment: .topLeading)
                    }
                }
            }
        }
    }
}

/// The three controls every overview ends with: previous, a picker, next.
struct StepControls<Items: View>: View {
    let label: String; let previous: String; let next: String
    var canPrevious = true, canNext = true
    let onPrevious: () -> Void, onNext: () -> Void
    @ViewBuilder var items: Items
    var body: some View {
        HStack(spacing: 10) {
            RoundButton(icon: "chevron.left", label: previous, action: onPrevious).disabled(!canPrevious).opacity(canPrevious ? 1 : 0.4)
            Menu { items } label: { Text(label) }.menuStyle(.button).buttonStyle(.glassAction(.header)).fixedSize().help("Choose")
            RoundButton(icon: "chevron.right", label: next, action: onNext).disabled(!canNext).opacity(canNext ? 1 : 0.4)
        }
    }
}

/// Week N: the current teaching week by default. Week 1 starts Mon 21 Sep 2026.
struct WeekPage: View {
    @Environment(Store.self) private var store
    @State private var week = 0   // 0 = current week (set on appear)
    @AppStorage("weekView") private var mode = ScheduleView.calendar
    let cal = Calendar.current
    static let weeks = 13         // ponytail: Semester 1 runs to mid-December; make it a setting if Semester 2 needs it

    func monday(_ w: Int) -> Date { cal.date(byAdding: .day, value: (w - 1) * 7, to: store.semesterStart)! }

    var body: some View {
        @Bindable var store = store
        let all = store.weekNotes(monday(max(week, 1))), days = WeekBlock.days(monday(max(week, 1)))
        VStack(spacing: 0) {
            PageHeader(title: "Week",
                       subtitle: "\(days.first!.formatted(.dateTime.day().month(.abbreviated))) – \(days.last!.formatted(.dateTime.day().month(.abbreviated))) · \(all.filter { !$0.done }.count) open · \(all.filter(\.done).count) done") {
                HStack(spacing: 10) {
                    Pills(options: [(nil, "All"), ("MSOA", "MSOA"), ("SM", "SM"), ("TEM", "TEM")] as [(String?, String)], selection: $store.filter)
                    ViewMenu(selection: $mode)
                    StepControls(label: "Week \(week)", previous: "Previous week", next: "Next week", canPrevious: week > 1, canNext: week < Self.weeks,
                                 onPrevious: { go(week - 1) }, onNext: { go(week + 1) }) {
                        ForEach(1...Self.weeks, id: \.self) { w in
                            Button("Week \(w) · \(monday(w).formatted(.dateTime.day().month(.abbreviated)))" + (w == store.semesterWeek ? " (now)" : "")) { go(w) }
                        }
                    }
                }
            }
            if mode != .calendar {
                ScheduleBody(mode: mode, notes: all, days: (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday(max(week, 1)))! }).padding([.horizontal, .bottom], 12)
            } else {
                ScheduleCard { _ in WeekBlock(monday: monday(max(week, 1))).id(week).transition(.opacity) }.padding([.horizontal, .bottom], 12)
            }
        }
        .onAppear { if week == 0 { week = min(max(store.semesterWeek, 1), Self.weeks) } }
    }
    func go(_ w: Int) { withAnimation(.spring(duration: 0.3)) { week = min(max(w, 1), Self.weeks) } }
}

struct WeekRow: View {
    @Environment(Store.self) private var store
    let note: Note; let day: Date
    var body: some View {
        let cal = Calendar.current
        let w = note.whenOrFar
        let off = !cal.isDate(w, inSameDayAs: day)       // a weekend item shown on Friday
        let time = cal.component(.hour, from: w) == 0 ? "" : w.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        HStack(alignment: .top, spacing: 6) {
            StatusButton(note: note)
            Button { store.page = .note(note.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.folder == "Readings" ? note.title : note.display).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                        .foregroundStyle(note.done ? Color.ink2 : Color.ink)
                    HStack(spacing: 4) {
                        Circle().fill(Color.course(note.course)).frame(width: 6, height: 6)
                        Text([off ? w.formatted(.dateTime.weekday(.abbreviated)) : nil, time.isEmpty ? nil : time, note.kind].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(Color.ink2).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .modifier(GlassRowHover())
    }
}

/// Glass on hover for a row that holds two buttons (so the whole row lights up, not just one).
struct GlassRowHover: ViewModifier {
    func body(content: Content) -> some View { content.modifier(GlassHover(shape: AnyShape(.rect(cornerRadius: DS.Radius.row)))) }
}
