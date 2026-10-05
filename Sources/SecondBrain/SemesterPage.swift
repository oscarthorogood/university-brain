import SwiftUI

/// A whole semester as a stack of weeks, each laid out exactly like This Week. The arrows switch semester.
struct SemesterPage: View {
    @Environment(Store.self) private var store
    @AppStorage("semesterView") private var mode = ScheduleView.calendar
    @State private var index = -1   // -1 = the current semester (set on appear)
    let cal = Calendar.current
    var chosen: Int { index < 0 ? store.currentSemester : index }
    var start: Date { Vault.parseDate(Store.semesters[chosen].start)! }
    func monday(_ w: Int) -> Date { cal.date(byAdding: .day, value: (w - 1) * 7, to: start)! }
    func go(_ i: Int) { withAnimation(.spring(duration: 0.3)) { index = min(max(i, 0), Store.semesters.count - 1) } }

    var body: some View {
        @Bindable var store = store
        let weeks = Array(1...WeekPage.weeks), all = weeks.flatMap { store.weekNotes(monday($0)) }
        VStack(spacing: 0) {
            PageHeader(title: "Semester", subtitle: "\(WeekPage.weeks) weeks from \(start.formatted(.dateTime.day().month(.abbreviated))) · \(all.filter { !$0.done }.count) open · \(all.filter(\.done).count) done") {
                HStack(spacing: 10) {
                    Pills(options: [(nil, "All"), ("MSOA", "MSOA"), ("SM", "SM"), ("TEM", "TEM")] as [(String?, String)], selection: $store.filter)
                    ViewMenu(selection: $mode)
                    StepControls(label: Store.semesters[chosen].name, previous: "Previous semester", next: "Next semester", canPrevious: chosen > 0, canNext: chosen < Store.semesters.count - 1,
                                 onPrevious: { go(chosen - 1) }, onNext: { go(chosen + 1) }) {
                        ForEach(Array(Store.semesters.enumerated()), id: \.offset) { i, s in Button(s.name + (i == store.currentSemester ? " (now)" : "")) { go(i) } }
                    }
                }
            }
            if mode != .calendar {
                let days = weeks.flatMap { w in (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday(w))! } }
                ScheduleBody(mode: mode, notes: all, days: days).padding([.horizontal, .bottom], 12)
            } else {
                ScheduleCard { proxy in
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(weeks, id: \.self) { w in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(WeekHeading.text(monday(w), start)).font(.system(size: 15, weight: .medium)).padding(.horizontal, 8)
                                WeekBlock(monday: monday(w))
                            }.id(w)
                        }
                    }
                    .onAppear { scroll(proxy) }
                    .onChange(of: chosen) { _, _ in scroll(proxy) }
                }.padding([.horizontal, .bottom], 12)
            }
        }
    }
    /// The current semester opens at this week; another opens at its first.
    func scroll(_ proxy: ScrollViewProxy) {
        let now = chosen == store.currentSemester ? min(max((cal.dateComponents([.day], from: start, to: store.today).day ?? 0) / 7 + 1, 1), WeekPage.weeks) : 1
        proxy.scrollTo(now, anchor: .top)
    }
}
