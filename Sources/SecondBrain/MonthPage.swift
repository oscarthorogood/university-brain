import SwiftUI

/// The month as a stack of weeks, each laid out exactly like This Week.
struct MonthPage: View {
    @Environment(Store.self) private var store
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @AppStorage("monthView") private var mode = ScheduleView.calendar
    let cal = Calendar.current

    var mondays: [Date] {
        let span = cal.dateInterval(of: .month, for: month)!
        return Array(sequence(first: WeekBlock.monday(of: span.start)) { cal.date(byAdding: .day, value: 7, to: $0) }.prefix { $0 < span.end })
    }
    /// September to May: the months the two semesters touch.
    var months: [Date] {
        let first = cal.dateInterval(of: .month, for: store.semesterStart)!.start
        return (0..<9).map { cal.date(byAdding: .month, value: $0, to: first)! }
    }
    func step(_ by: Int) { withAnimation(.spring(duration: 0.3)) { month = cal.date(byAdding: .month, value: by, to: month)! } }

    var body: some View {
        @Bindable var store = store
        let all = mondays.flatMap(store.weekNotes)
        VStack(spacing: 0) {
            PageHeader(title: "Month", subtitle: "\(mondays.count) weeks · \(all.filter { !$0.done }.count) open · \(all.filter(\.done).count) done") {
                HStack(spacing: 10) {
                    Pills(options: [(nil, "All"), ("MSOA", "MSOA"), ("SM", "SM"), ("TEM", "TEM")] as [(String?, String)], selection: $store.filter)
                    ViewMenu(selection: $mode)
                    StepControls(label: month.formatted(.dateTime.month(.wide).year()), previous: "Previous month", next: "Next month", onPrevious: { step(-1) }, onNext: { step(1) }) {
                        ForEach(months, id: \.self) { m in Button(m.formatted(.dateTime.month(.wide).year())) { withAnimation(.spring(duration: 0.3)) { month = m } } }
                    }
                }
            }
            if mode != .calendar {
                let days = mondays.flatMap { m in (0..<7).map { cal.date(byAdding: .day, value: $0, to: m)! } }
                ScheduleBody(mode: mode, notes: all, days: days).padding([.horizontal, .bottom], 12)
            } else {
                ScheduleCard { _ in
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(mondays, id: \.self) { m in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(WeekHeading.text(m, store.semesterStart)).font(.system(size: 15, weight: .medium)).padding(.horizontal, 8)
                                WeekBlock(monday: m)
                            }
                        }
                    }.id(month).transition(.opacity)
                }.padding([.horizontal, .bottom], 12)
            }
        }
    }
}

/// "Week 3 · 5 Oct – 9 Oct" above a week in a stack (just the dates before the semester starts).
enum WeekHeading {
    static func text(_ monday: Date, _ start: Date) -> String {
        let cal = Calendar.current, friday = cal.date(byAdding: .day, value: 4, to: monday)!
        let n = (cal.dateComponents([.day], from: start, to: monday).day ?? -7) / 7 + 1
        let range = "\(monday.formatted(.dateTime.day().month(.abbreviated))) – \(friday.formatted(.dateTime.day().month(.abbreviated)))"
        return n >= 1 ? "Week \(n) · \(range)" : range
    }
}
