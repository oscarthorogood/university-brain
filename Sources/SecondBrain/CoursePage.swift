import SwiftUI

/// A course page: lectures and tutorials in the top half beside the course agent's stage; below, the week-by-week outline,
/// a map of how the course's notes relate, and the assessment timeline.
struct CoursePage: View {
    @Environment(Store.self) private var store
    @Environment(\.mainWidth) private var mainWidth
    let code: String
    var body: some View {
        let classes = store.course(code, ["Lectures", "Tutorials"])
        let lectures = classes.filter { $0.folder == "Lectures" }, tutorials = classes.filter { $0.folder == "Tutorials" }
        let name = Vault.courses.first { $0.value == code }?.key ?? code
        VStack(spacing: 0) {
            PageHeader(title: code == "SM" ? "Strategy" : code, subtitle: name) {
                HStack(spacing: 8) {
                    Chip("Lectures", "\(lectures.filter(\.done).count)/\(lectures.count)")
                    Chip("Tutorials", "\(tutorials.filter(\.done).count)/\(tutorials.count)")
                    if let next = classes.first(where: { !$0.done && ($0.when ?? .distantPast) >= store.today }), let w = next.when { Chip("Next", NoteRow.format(w)) }
                }
            }
            GeometryReader { g in
                let lecturesCard = Card(title: "Lectures", trailing: "\(lectures.filter(\.done).count)/\(lectures.count)") { ClassList(notes: lectures, empty: "No lectures") }
                let tutorialsCard = Card(title: "Tutorials", trailing: "\(tutorials.filter(\.done).count)/\(tutorials.count)") { ClassList(notes: tutorials, empty: "No tutorials") }
                let stage = Card { AgentStage(id: code, says: store.courseSays(code)) }
                if mainWidth >= 840 && g.size.height >= 540 {
                    let half = (g.size.height - 12) / 2, w = g.size.width
                    VStack(spacing: 12) {
                        HStack(spacing: 12) { lecturesCard; tutorialsCard; stage.frame(width: 340) }.frame(height: half)
                        HStack(spacing: 12) {
                            CourseOutline(code: code).frame(width: (w - 24) * 0.28)
                            CourseMap(code: code).frame(width: (w - 24) * 0.42)
                            CourseTimeline(code: code)
                        }.frame(height: half)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            lecturesCard.frame(height: 300); tutorialsCard.frame(height: 220); stage.frame(height: 340)
                            CourseOutline(code: code).frame(height: 340); CourseMap(code: code).frame(height: 320); CourseTimeline(code: code).frame(height: 320)
                        }
                    }.scrollIndicators(.hidden)
                }
            }.padding([.horizontal, .bottom], 12)
        }
    }
}

/// Lectures or tutorials in three groups: what's next, what's later, and what's done (collapsed).
struct ClassList: View {
    @Environment(Store.self) private var store
    let notes: [Note]; var empty = "Nothing here"
    @State private var showDone = false
    var body: some View {
        let todo = notes.filter { !$0.done }, done = notes.filter(\.done)
        let next = todo.first
        if notes.isEmpty {
            Text(empty).font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if let next { label("Up next"); NoteRow(note: next).background(Color.ink.opacity(0.04), in: .rect(cornerRadius: DS.Radius.row)).padding(.horizontal, 6) }
                    if todo.count > 1 { label("Later"); ForEach(todo.dropFirst()) { NoteRow(note: $0) } }
                    if !done.isEmpty {
                        Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(showDone ? 90 : 0))
                                Text("Done · \(done.count)").font(.system(size: 11, weight: .semibold))
                                Spacer()
                            }.foregroundStyle(Color.ink2).padding(.horizontal, 16).padding(.vertical, 8).contentShape(.rect)
                        }.buttonStyle(.plain)
                        if showDone { ForEach(done) { NoteRow(note: $0) } }
                    }
                    if todo.isEmpty { label("All done") }
                }
            }
        }
    }
    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 2)
    }
}

extension Store {
    /// Semester week (Week 1 starts 21 Sep) for a date, or 0 when it has none.
    func week(of d: Date?) -> Int {
        guard let d else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Vault.semesterOneStart, to: d).day ?? 0
        return Int((Double(days) / 7).rounded(.down)) + 1
    }
    func weekStart(_ w: Int) -> Date { Calendar.current.date(byAdding: .day, value: (w - 1) * 7, to: Vault.semesterOneStart) ?? Vault.semesterOneStart }
}

// MARK: Outline

/// The course week by week, built from the vault itself (classes and deadlines), with the readings on their own tab.
struct CourseOutline: View {
    @Environment(Store.self) private var store
    let code: String
    @State private var tab = 0
    var body: some View {
        let items = store.course(code, ["Lectures", "Tutorials", "Essays", "Projects"]).filter { $0.when != nil }
        let reads = store.course(code, ["Readings"])
        let revision = store.notes.filter { (Study.isStudy($0.folder) || $0.folder == "Exams") && $0.course == code }   // often undated, so not limited to this semester
        let weeks = Dictionary(grouping: items, by: { store.week(of: $0.when) }).sorted { $0.key < $1.key }
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    tabButton("Outline", 0)
                    tabButton("Readings · \(reads.filter { !$0.done }.count)", 1)
                    tabButton("Study · \(revision.count)", 2)
                    Spacer()
                    Text("Week \(store.semesterWeek)").font(.caption).foregroundStyle(Color.ink2)
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                if tab == 0 {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(weeks, id: \.key) { w, notes in
                                    let now = w == store.semesterWeek
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text("Week \(w) · " + store.weekStart(w).formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 11, weight: .semibold)).foregroundStyle(now ? Color.ink : Color.ink2)
                                            if now { Text("now").font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1).background(Color.course(code).opacity(0.25), in: .capsule) }
                                            if let r = readsIn(reads, w) { Text("· \(r) reading\(r == 1 ? "" : "s")").font(.system(size: 10)).foregroundStyle(Color.ink2) }
                                        }
                                        ForEach(notes.sorted { $0.whenOrFar < $1.whenOrFar }) { n in
                                            Button { store.page = .note(n.id) } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: n.state == .notStarted ? icon(n) : n.state.icon).font(.system(size: 11)).foregroundStyle(n.state == .notStarted ? Color.course(code) : n.state.color).frame(width: 16)
                                                    Text(n.display).font(.system(size: 12)).foregroundStyle(n.done ? Color.ink2 : Color.ink).lineLimit(1)
                                                    Spacer(minLength: 0)
                                                    Text(n.whenOrFar.formatted(.dateTime.weekday(.abbreviated).day())).font(.system(size: 10)).foregroundStyle(Color.ink2)
                                                }.padding(.horizontal, 8).padding(.vertical, 4).contentShape(.rect)
                                            }.buttonStyle(.glassRow)
                                        }
                                    }.id(w)
                                }
                            }.padding(.horizontal, 8).padding(.bottom, 12)
                        }
                        .onAppear { proxy.scrollTo(store.semesterWeek, anchor: .top) }
                    }
                } else if tab == 1 {
                    NoteList(notes: reads, empty: "No readings set")
                } else {
                    VStack(spacing: 0) {
                        NoteList(notes: revision.sorted { $0.title < $1.title }, empty: "No MCQs, flashcards or exams yet. Ask the course agent for MCQs.")
                        Button { store.filter = code; store.page = .folder("MCQ") } label: { Label("Open Study", systemImage: "arrow.right") }
                            .buttonStyle(.glassRow).padding(8)
                    }
                }
            }
        }
    }
    private func readsIn(_ reads: [Note], _ w: Int) -> Int? {
        let n = reads.filter { store.week(of: $0.when) == w }.count
        return n == 0 ? nil : n
    }
    private func icon(_ n: Note) -> String {
        switch n.folder { case "Lectures": "play.rectangle"; case "Tutorials": "person.2"; case "Essays": "doc.text"; default: "flag" }
    }
    private func tabButton(_ title: String, _ i: Int) -> some View {
        Button { withAnimation(.snappy) { tab = i } } label: {
            Text(title).font(.system(size: 12, weight: tab == i ? .semibold : .regular)).foregroundStyle(tab == i ? Color.ink : Color.ink2).lineLimit(1).fixedSize()
        }.buttonStyle(.plain)
    }
}

// MARK: Map

struct MapNode: Identifiable { let note: Note; let row: Int; let week: Int; var id: URL { note.id } }
struct MapEdge: Hashable { let a: URL; let b: URL; let explicit: Bool }

/// How a course's notes relate: the links written in their frontmatter (`related`, `readings`) plus two inferences,
/// a reading belongs to the lecture in the week it is due, and a tutorial to the lecture in its week.
enum CourseGraph {
    static let rows = ["Readings", "Lectures", "Tutorials", "Deadlines"]
    static func row(_ n: Note) -> Int? {
        switch n.folder { case "Readings": 0; case "Lectures": 1; case "Tutorials": 2; case "Essays", "Projects": 3; default: nil }
    }
    static func build(_ notes: [Note], week: (Date?) -> Int) -> (nodes: [MapNode], edges: [MapEdge]) {
        let nodes = notes.compactMap { n -> MapNode? in row(n).flatMap { r in n.when.map { MapNode(note: n, row: r, week: week($0)) } } }
        let byTitle = Dictionary(nodes.map { ($0.note.title, $0.note.id) }, uniquingKeysWith: { a, _ in a })
        var pairs: [String: MapEdge] = [:]
        func add(_ x: URL, _ y: URL, explicit: Bool) {
            let (a, b) = x.absoluteString < y.absoluteString ? (x, y) : (y, x)
            let key = a.absoluteString + "|" + b.absoluteString
            if pairs[key] == nil || explicit { pairs[key] = MapEdge(a: a, b: b, explicit: explicit) }
        }
        for n in nodes {
            let text = (try? String(contentsOf: n.note.id, encoding: .utf8)) ?? ""
            for key in ["related", "readings"] {
                for raw in Vault.rawItems(text, key) {
                    let name = Vault.unlink(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))).components(separatedBy: "|")[0].components(separatedBy: "#")[0]
                    if let other = byTitle[name], other != n.id { add(n.id, other, explicit: true) }
                }
            }
        }
        let lectures = nodes.filter { $0.row == 1 }
        let linkedToLecture = Set(pairs.values.flatMap { e in [e.a, e.b].filter { u in lectures.contains { $0.id == u } } == [] ? [] : [e.a, e.b] })
        for n in nodes where n.row == 0 || n.row == 2 {
            guard n.row == 2 || !linkedToLecture.contains(n.id), let l = lectures.first(where: { $0.week == n.week }) else { continue }
            add(n.id, l.id, explicit: false)
        }
        return (nodes, Array(pairs.values))
    }
}

struct CourseMap: View {
    @Environment(Store.self) private var store
    let code: String
    @State private var graph: (nodes: [MapNode], edges: [MapEdge]) = ([], [])
    @State private var hover: URL?
    var body: some View {
        let tint = Color.course(code)
        Card(title: "Course map", trailing: graph.nodes.isEmpty ? "" : "\(graph.nodes.count) notes · \(graph.edges.filter(\.explicit).count) links") {
            if graph.nodes.isEmpty {
                Text("Nothing to map yet").font(.system(size: 13)).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { g in
                    let pos = positions(g.size)
                    let lit = hover.map { h in Set(graph.edges.filter { $0.a == h || $0.b == h }.flatMap { [$0.a, $0.b] }) } ?? []
                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, _ in
                            for e in graph.edges {
                                guard let p = pos[e.a], let q = pos[e.b] else { continue }
                                var path = Path(); path.move(to: p)
                                path.addCurve(to: q, control1: CGPoint(x: p.x, y: (p.y + q.y) / 2), control2: CGPoint(x: q.x, y: (p.y + q.y) / 2))
                                let on = hover != nil && (e.a == hover || e.b == hover)
                                if on { ctx.stroke(path, with: .color(tint), lineWidth: 2) }
                                else {
                                    let dim = hover == nil ? 1.0 : 0.25
                                    ctx.stroke(path, with: .color(Color.ink.opacity((e.explicit ? 0.3 : 0.14) * dim)),
                                               style: StrokeStyle(lineWidth: e.explicit ? 1.2 : 1, dash: e.explicit ? [] : [2, 3]))
                                }
                            }
                        }
                        ForEach(CourseGraph.rows.indices, id: \.self) { r in
                            Text(CourseGraph.rows[r]).font(.system(size: 9)).foregroundStyle(Color.ink2).position(x: 28, y: rowY(r, g.size.height))
                        }
                        ForEach(axis(g.size), id: \.0) { w, x in
                            Text("W\(w)").font(.system(size: 9)).foregroundStyle(w == store.semesterWeek ? Color.ink : Color.ink2).position(x: x, y: g.size.height - 12)
                        }
                        ForEach(graph.nodes) { n in
                            if let p = pos[n.id] {
                                let faded = hover != nil && n.id != hover && !lit.contains(n.id)
                                Button { store.page = .note(n.note.id) } label: { node(n, tint) }
                                    .buttonStyle(.plain).onHover { hover = $0 ? n.id : (hover == n.id ? nil : hover) }
                                    .help(n.note.display).accessibilityLabel(n.note.display)
                                    .opacity(faded ? 0.3 : 1).position(p)
                            }
                        }
                        if let h = hover, let n = graph.nodes.first(where: { $0.id == h }) {
                            Text(n.note.display + (n.note.done ? " · done" : "")).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule).position(x: g.size.width / 2, y: 12)
                        }
                    }
                }
            }
        }
        .task(id: store.revision) {
            let mine = store.course(code, ["Lectures", "Tutorials", "Readings", "Essays", "Projects"])
            graph = CourseGraph.build(mine, week: store.week(of:))
        }
    }

    @ViewBuilder private func node(_ n: MapNode, _ tint: Color) -> some View {
        let filled = n.note.done
        ZStack {
            if n.row == 3 {
                RoundedRectangle(cornerRadius: 2).fill(filled ? tint : Color.card).frame(width: 11, height: 11).rotationEffect(.degrees(45))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(tint, lineWidth: 1.5).rotationEffect(.degrees(45)))
            } else {
                Circle().fill(filled ? tint : Color.card).frame(width: n.row == 1 ? 12 : 9, height: n.row == 1 ? 12 : 9).overlay(Circle().stroke(tint, lineWidth: 1.5))
            }
        }.frame(width: 20, height: 20).contentShape(.rect)
    }

    private func rowY(_ r: Int, _ h: CGFloat) -> CGFloat { 14 + (CGFloat(r) + 0.5) / 4 * (h - 40) }
    private func range() -> (lo: Int, hi: Int) {
        let ws = graph.nodes.map(\.week); let lo = ws.min() ?? 1
        return (lo, max(ws.max() ?? lo, lo + 1))
    }
    private func x(_ w: Int, _ size: CGSize) -> CGFloat {
        let r = range(); return 58 + CGFloat(w - r.lo) / CGFloat(r.hi - r.lo) * (size.width - 58 - 16)
    }
    private func axis(_ size: CGSize) -> [(Int, CGFloat)] {
        let r = range(); return stride(from: r.lo, through: r.hi, by: max(1, (r.hi - r.lo) / 6)).map { ($0, x($0, size)) }
    }
    /// Columns are weeks, rows are kinds of note; notes in the same cell are spread out a little so none hides another.
    private func positions(_ size: CGSize) -> [URL: CGPoint] {
        var out: [URL: CGPoint] = [:]
        for (_, cell) in Dictionary(grouping: graph.nodes, by: { $0.row * 100 + $0.week }) {
            for (k, n) in cell.sorted(by: { ($0.note.when ?? .distantPast) < ($1.note.when ?? .distantPast) }).enumerated() {
                let off = (CGFloat(k) - CGFloat(cell.count - 1) / 2) * 12
                out[n.id] = n.row == 0 ? CGPoint(x: x(n.week, size), y: rowY(n.row, size.height) + off) : CGPoint(x: x(n.week, size) + off, y: rowY(n.row, size.height))
            }
        }
        return out
    }
}

// MARK: Timeline

/// Every deadline for the course on one line across the semester, with its weight, and the list below to tick them off.
struct CourseTimeline: View {
    @Environment(Store.self) private var store
    let code: String
    var body: some View {
        let work = store.course(code, ["Essays", "Projects"])
        Card(title: "Assessment timeline", trailing: work.isEmpty ? "" : "\(work.filter { !$0.done }.count) to go") {
            VStack(spacing: 0) {
                Track(work: work, code: code, today: store.today).frame(height: 92).padding(.horizontal, 16).padding(.top, 4)
                Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1)
                NoteList(notes: work, badge: true, empty: "No assignments")
            }
        }
    }

    struct Track: View {
        let work: [Note]; let code: String; let today: Date
        var body: some View {
            let start = Vault.semesterOneStart
            let last = work.compactMap(\.when).max() ?? start
            let end = max(last, Calendar.current.date(byAdding: .day, value: 84, to: start)!).addingTimeInterval(7 * 86400)
            let tint = Color.course(code)
            Canvas { ctx, size in
                func x(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(start) / end.timeIntervalSince(start)) * size.width }
                let y = size.height / 2
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color.line), lineWidth: 2)
                var d = start
                while d <= end {
                    let tx = x(d), w = Int(d.timeIntervalSince(start) / (7 * 86400)) + 1
                    ctx.stroke(Path { $0.move(to: CGPoint(x: tx, y: y - 3)); $0.addLine(to: CGPoint(x: tx, y: y + 3)) }, with: .color(Color.line), lineWidth: 1)
                    if w % 2 == 1 { ctx.draw(Text("W\(w)").font(.system(size: 9)).foregroundStyle(Color.ink2), at: CGPoint(x: min(max(tx, 10), size.width - 10), y: size.height - 4)) }
                    d = Calendar.current.date(byAdding: .day, value: 7, to: d)!
                }
                if today >= start && today <= end {
                    let tx = x(today)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: tx, y: 4)); $0.addLine(to: CGPoint(x: tx, y: size.height - 14)) }, with: .color(Color.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ctx.draw(Text("today").font(.system(size: 9)).foregroundStyle(Color.ink2), at: CGPoint(x: tx, y: 0), anchor: .top)
                }
                for (i, n) in work.enumerated() {
                    guard let due = n.when else { continue }
                    let px = min(max(x(due), 34), size.width - 34), up = i % 2 == 0
                    let dot = Path(ellipseIn: CGRect(x: px - 6, y: y - 6, width: 12, height: 12))
                    ctx.fill(dot, with: .color(n.done ? tint : Color.card)); ctx.stroke(dot, with: .color(tint), lineWidth: 2)
                    let weight = CourseTimeline.weight(n).map { "\($0)%" } ?? ""
                    let label = [weight, due.formatted(.dateTime.day().month(.abbreviated))].filter { !$0.isEmpty }.joined(separator: " · ")
                    ctx.draw(Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.ink), at: CGPoint(x: px, y: up ? y - 16 : y + 18))
                }
            }
        }
    }

    /// The weight written in the note ("Weighting | 70% …" in the brief table), else a "(70% of …)" in its summary.
    nonisolated static func weight(_ n: Note) -> Int? {
        guard let t = try? String(contentsOf: n.id, encoding: .utf8) else { return nil }
        func pct(_ s: String) -> Int? { s.range(of: #"\d{1,3}\s?%"#, options: .regularExpression).flatMap { Int(s[$0].filter(\.isNumber)) } }
        if let line = t.split(separator: "\n").first(where: { $0.localizedCaseInsensitiveContains("weight") && pct(String($0)) != nil }) { return pct(String(line)) }
        return t.split(separator: "\n").first(where: { $0.hasPrefix("summary:") }).flatMap { pct(String($0)) }
    }
}
