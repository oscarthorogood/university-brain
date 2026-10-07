import SwiftUI
import AVKit

// Each app has its own library page (what you see when you open it from the sidebar) and its own sub page (what one note of that type
// opens as), shaped to what the app is for:
//   MCQ         library of quizzes with scores        → a quiz you take one question at a time
//   Flashcards  library of decks with progress        → a study session: flip, "Again" or "Got it"
//   Glossary    one A–Z index of every term          → a term list you can test yourself on
//   Podcast     library of episodes                   → a player with speed, skip and a searchable transcript
// "Edit note" on any sub page opens the note itself.

enum AppKind: String, CaseIterable {
    case mcq = "MCQ", flashcards = "Flashcards", glossary = "Glossary", podcast = "Podcast"
    var icon: String { Study.kind(rawValue)?.icon ?? "square.grid.2x2" }
}

extension Store {
    /// The app a note page belongs to, unless the note is being edited (then it is an ordinary note page).
    func appKind(for p: Page) -> AppKind? {
        guard case .note(let u) = p, !editingApps.contains(u), let n = notes.first(where: { $0.id == u }) else { return nil }
        return AppKind(rawValue: n.folder)
    }
}

// MARK: - Progress, remembered on this Mac
enum StudyProgress {
    struct Quiz: Codable { var best: Int; var total: Int; var attempts: Int; var last: Date }
    static func quiz(_ url: URL) -> Quiz? {
        UserDefaults.standard.data(forKey: "quiz:" + url.path).flatMap { try? JSONDecoder().decode(Quiz.self, from: $0) }
    }
    /// Records a finished run of the whole quiz; the best score is kept (and starts again if the quiz changed length).
    static func record(_ url: URL, score: Int, total: Int) {
        var q = quiz(url) ?? Quiz(best: 0, total: total, attempts: 0, last: .now)
        q.best = q.total == total ? max(q.best, score) : score
        q.total = total; q.attempts += 1; q.last = .now
        if let data = try? JSONEncoder().encode(q) { UserDefaults.standard.set(data, forKey: "quiz:" + url.path) }
    }
    static func known(_ url: URL) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "known:" + url.path) ?? []) }
    static func setKnown(_ url: URL, _ s: Set<String>) { UserDefaults.standard.set(Array(s), forKey: "known:" + url.path) }
    static func position(_ url: URL) -> Double { UserDefaults.standard.double(forKey: "pos:" + url.path) }
    static func setPosition(_ url: URL, _ t: Double) { UserDefaults.standard.set(t, forKey: "pos:" + url.path) }
}

/// Note text by file and modified date, so a library of dozens of notes doesn't re-read them on every redraw.
@MainActor enum StudyCache {
    private static var texts: [URL: (modified: Date?, text: String)] = [:]
    static func text(_ url: URL) -> String {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let hit = texts[url], hit.modified == m { return hit.text }
        let t = Vault.body((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        texts[url] = (m, t)
        return t
    }
}

// MARK: - Shared pieces
extension View {
    /// A white card with a hairline and a soft shadow, the look of the cards in the galleries.
    func appCard(radius: CGFloat = DS.Radius.card) -> some View {
        background { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.card).shadow(color: .black.opacity(0.08), radius: 8, y: 3) }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.line.opacity(0.9)))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .ink
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .serif)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(Color.ink2)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appCard(radius: DS.Radius.tile)
    }
}

struct MeterBar: View {
    let value: Double
    var tint: Color = NoteColor.done
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.opacity(0.08))
                Capsule().fill(tint).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }.frame(height: 6)
    }
}

struct CourseFilterMenu: View {
    let courses: [String]
    @Binding var selection: String?
    var body: some View {
        Menu {
            Picker("Course", selection: $selection) {
                Text("All courses").tag(String?.none)
                ForEach(courses, id: \.self) { Text($0).tag(String?.some($0)) }
            }.pickerStyle(.inline)
        } label: { Image(systemName: selection == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill").font(.system(size: 15)) }
            .menuStyle(.button).buttonStyle(.glassIcon()).menuIndicator(.hidden).help("Filter by course")
    }
}

private func clock(_ x: Double) -> String {
    let s = max(0, Int(x.isFinite ? x : 0))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
private func rich(_ s: String) -> Text { Text(MD.inline(s)) }

// MARK: - Library pages
struct AppHomePage: View {
    let kind: AppKind
    var body: some View {
        switch kind {
        case .mcq: QuizLibraryPage()
        case .flashcards: DeckLibraryPage()
        case .glossary: GlossaryIndexPage()
        case .podcast: EpisodesPage()
        }
    }
}

/// MCQ: every quiz as a card with its question count and best score.
struct QuizLibraryPage: View {
    @Environment(Store.self) private var store
    @State private var course: String?
    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses
        let rows = store.notes.filter { $0.folder == "MCQ" }.map { n in
            (note: n, course: NoteBrowserPage.course(n, known: known), count: StudyParse.questions(StudyCache.text(n.id)).count)
        }
        let shown = rows.filter { course == nil || $0.course == course }.sorted { $0.note.title < $1.note.title }
        let bests = shown.compactMap { r in StudyProgress.quiz(r.note.id).map { Double($0.best) / Double(max($0.total, 1)) } }
        VStack(spacing: 0) {
            PageHeader(title: "MCQ", subtitle: "\(shown.count) quizzes", compact: true) {
                HStack(spacing: 10) {
                    CourseFilterMenu(courses: Set(rows.map(\.course)).sorted(), selection: $course)
                    PageTools(title: "MCQ", finder: Vault.root.appending(path: Vault.dir("MCQ")))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        StatTile(value: "\(shown.count)", label: "Quizzes")
                        StatTile(value: "\(shown.reduce(0) { $0 + $1.count })", label: "Questions")
                        StatTile(value: bests.isEmpty ? "—" : "\(Int(bests.reduce(0, +) / Double(bests.count) * 100))%", label: "Average best score", tint: NoteColor.done)
                        StatTile(value: "\(bests.count) of \(shown.count)", label: "Attempted")
                    }
                    if shown.isEmpty { Text("No quizzes yet. The Tutor makes one from a lecture note.").font(.system(size: 13)).foregroundStyle(Color.ink2) }
                    else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                            ForEach(shown, id: \.note.id) { QuizCard(note: $0.note, course: $0.course, count: $0.count) }
                        }
                    }
                }.padding(24)
            }
        }
    }
}

private struct QuizCard: View {
    @Environment(Store.self) private var store
    let note: Note
    let course: String
    let count: Int
    var body: some View {
        let p = StudyProgress.quiz(note.id)
        Button { store.page = .note(note.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Color.course(note.course)).frame(width: 7, height: 7)
                    Text(course).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                    Spacer()
                    Image(systemName: "checklist").foregroundStyle(Color.ink2)
                }
                Text(note.display).font(.system(size: 17, weight: .semibold, design: .serif)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(count) question\(count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Color.ink2)
                Spacer(minLength: 0)
                if let p {
                    MeterBar(value: Double(p.best) / Double(max(p.total, 1)))
                    Text("Best \(p.best) of \(p.total) · taken \(p.attempts) time\(p.attempts == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Color.ink2)
                } else { Text("Not taken yet").font(.system(size: 11)).foregroundStyle(Color.ink2) }
                Label(p == nil ? "Start quiz" : "Take it again", systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Color.ink.opacity(0.07), in: .capsule)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading).appCard().contentShape(.rect)
        }.buttonStyle(.plain).contextMenu { NoteMenu(note: note) }
    }
}

/// Flashcards: every deck as a small stack of cards, with how many you know.
struct DeckLibraryPage: View {
    @Environment(Store.self) private var store
    @State private var course: String?
    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses
        let rows = store.notes.filter { $0.folder == "Flashcards" }.map { n -> (note: Note, course: String, cards: [StudyParse.Card]) in
            (n, NoteBrowserPage.course(n, known: known), StudyParse.cards(StudyCache.text(n.id)))
        }
        let shown = rows.filter { course == nil || $0.course == course }.sorted { $0.note.title < $1.note.title }
        let total = shown.reduce(0) { $0 + $1.cards.count }
        let mastered = shown.reduce(0) { acc, r in let k = StudyProgress.known(r.note.id); return acc + r.cards.filter { k.contains($0.front) }.count }
        VStack(spacing: 0) {
            PageHeader(title: "Flashcards", subtitle: "\(shown.count) decks", compact: true) {
                HStack(spacing: 10) {
                    CourseFilterMenu(courses: Set(rows.map(\.course)).sorted(), selection: $course)
                    PageTools(title: "Flashcards", finder: Vault.root.appending(path: Vault.dir("Flashcards")))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        StatTile(value: "\(shown.count)", label: "Decks")
                        StatTile(value: "\(total)", label: "Cards")
                        StatTile(value: "\(mastered)", label: "Cards you know", tint: NoteColor.done)
                        StatTile(value: "\(total - mastered)", label: "Still to learn")
                    }
                    if shown.isEmpty { Text("No decks yet. The Tutor makes one from a lecture note.").font(.system(size: 13)).foregroundStyle(Color.ink2) }
                    else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 22) {
                            ForEach(shown, id: \.note.id) { DeckCard(note: $0.note, course: $0.course, cards: $0.cards) }
                        }
                    }
                }.padding(24)
            }
        }
    }
}

private struct DeckCard: View {
    @Environment(Store.self) private var store
    let note: Note
    let course: String
    let cards: [StudyParse.Card]
    var body: some View {
        let k = StudyProgress.known(note.id)
        let got = cards.filter { k.contains($0.front) }.count
        Button { store.page = .note(note.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {   // a small stack of cards
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(0.06)).rotationEffect(.degrees(-5)).offset(x: -6, y: 4)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(0.09)).rotationEffect(.degrees(4)).offset(x: 6, y: 2)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.card).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .overlay { Text(cards.first.map { $0.front } ?? "").font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(3).multilineTextAlignment(.center).padding(10) }
                }.frame(height: 92).padding(.horizontal, 22).padding(.top, 6)
                HStack(spacing: 6) {
                    Circle().fill(Color.course(note.course)).frame(width: 7, height: 7)
                    Text(course).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                }
                Text(note.display).font(.system(size: 16, weight: .semibold, design: .serif)).lineLimit(2).multilineTextAlignment(.leading)
                MeterBar(value: Double(got) / Double(max(cards.count, 1)), tint: IM.blue)
                Text("\(got) of \(cards.count) cards known").font(.system(size: 11)).foregroundStyle(Color.ink2)
            }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading).appCard().contentShape(.rect)
        }.buttonStyle(.plain).contextMenu { NoteMenu(note: note) }
    }
}

/// Glossary: one A–Z index across every glossary note, each term pointing back at the note it came from.
struct GlossaryIndexPage: View {
    @Environment(Store.self) private var store
    @State private var course: String?
    @State private var query = ""
    struct Term: Identifiable { let term: String; let meaning: String; let note: Note; let course: String; var id: String { note.id.path + term } }
    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses
        let all: [Term] = store.notes.filter { $0.folder == "Glossary" }.flatMap { n -> [Term] in
            let c = NoteBrowserPage.course(n, known: known)
            return StudyParse.terms(StudyCache.text(n.id)).map { Term(term: $0.term, meaning: $0.meaning, note: n, course: c) }
        }
        let shown = all.filter { t in (course == nil || t.course == course) && (query.isEmpty || t.term.localizedCaseInsensitiveContains(query) || t.meaning.localizedCaseInsensitiveContains(query)) }
        let groups = Dictionary(grouping: shown) { t -> String in
            let f = t.term.first.map { String($0).uppercased() } ?? "#"
            return f.rangeOfCharacter(from: .letters) == nil ? "#" : f
        }.sorted { $0.key < $1.key }
        VStack(spacing: 0) {
            PageHeader(title: "Glossary", subtitle: "\(shown.count) terms", compact: true) {
                HStack(spacing: 10) {
                    CourseFilterMenu(courses: Set(all.map(\.course)).sorted(), selection: $course)
                    PageTools(title: "Glossary", finder: Vault.root.appending(path: Vault.dir("Glossary")))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                TextField("Search \(all.count) terms", text: $query).textFieldStyle(.plain)
            }.font(.system(size: 13)).glassField().padding(.horizontal, 24).padding(.bottom, 10)
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groups, id: \.key) { letter, terms in
                                Section {
                                    ForEach(terms.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }) { t in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(t.term).font(.system(size: 15, weight: .semibold))
                                            rich(t.meaning).font(.system(size: 13)).foregroundStyle(Color.ink2)
                                            Button { store.page = .note(t.note.id) } label: {
                                                Label(t.note.display, systemImage: "book.closed").font(.system(size: 11)).foregroundStyle(Color.ink2.opacity(0.8))
                                            }.buttonStyle(.plain)
                                        }.padding(.horizontal, 24).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                                        Divider().padding(.horizontal, 24)
                                    }
                                } header: {
                                    Text(letter).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.ink2).padding(.horizontal, 24).padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading).background(Color.card.opacity(0.95))
                                }.id(letter)
                            }
                            if shown.isEmpty { Text(all.isEmpty ? "No glossary notes yet." : "No matching terms").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(24) }
                        }
                    }
                    VStack(spacing: 2) {   // jump to a letter
                        ForEach(groups.map(\.key), id: \.self) { l in
                            Button { withAnimation(.smooth) { proxy.scrollTo(l, anchor: .top) } } label: { Text(l).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2).frame(width: 22, height: 18).contentShape(.rect) }.buttonStyle(.plain)
                        }
                    }.padding(.trailing, 14).padding(.top, 6)
                }
            }
        }
    }
}

/// Podcast: every episode as a row with how far you got.
struct EpisodesPage: View {
    @Environment(Store.self) private var store
    @State private var course: String?
    var body: some View {
        let known = FileBrowserPage(root: "Resources").courses
        let rows = store.notes.filter { $0.folder == "Podcast" }.map { n -> (note: Note, course: String, hasAudio: Bool, hasTranscript: Bool) in
            let t = StudyCache.text(n.id)
            return (n, NoteBrowserPage.course(n, known: known), StudyParse.audio(t) != nil, !StudyParse.transcript(t).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let shown = rows.filter { course == nil || $0.course == course }.sorted { ($0.note.when ?? .distantPast) > ($1.note.when ?? .distantPast) }
        VStack(spacing: 0) {
            PageHeader(title: "Podcast", subtitle: "\(shown.count) episodes", compact: true) {
                HStack(spacing: 10) {
                    CourseFilterMenu(courses: Set(rows.map(\.course)).sorted(), selection: $course)
                    PageTools(title: "Podcast", finder: Vault.root.appending(path: Vault.dir("Podcast")))
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    if shown.isEmpty { Text("No episodes yet.").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.top, 20) }
                    ForEach(shown, id: \.note.id) { r in
                        let pos = StudyProgress.position(r.note.id)
                        Button { store.page = .note(r.note.id) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: r.hasAudio ? "play.fill" : "waveform.slash").font(.system(size: 16)).foregroundStyle(r.hasAudio ? Color.card : Color.ink2)
                                    .frame(width: 44, height: 44).background(r.hasAudio ? Color.ink : Color.ink.opacity(0.08), in: .circle)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.note.display).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.course(r.note.course)).frame(width: 7, height: 7)
                                        Text([r.course, r.note.when.map { $0.formatted(.dateTime.day().month(.abbreviated)) }].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                                        if r.hasTranscript { Label("Transcript", systemImage: "text.alignleft") }
                                    }.font(.system(size: 11)).foregroundStyle(Color.ink2)
                                }
                                Spacer()
                                if pos > 5 { Text("Resume at \(clock(pos))").font(.system(size: 11)).foregroundStyle(Color.ink2) }
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.ink2)
                            }.padding(14).frame(maxWidth: .infinity).appCard(radius: DS.Radius.tile).contentShape(.rect)
                        }.buttonStyle(.plain).contextMenu { NoteMenu(note: r.note) }
                    }
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Sub pages
/// One note of an app, shown the way that app works. "Edit note" opens the note's text instead.
struct AppSubPage: View {
    @Environment(Store.self) private var store
    let url: URL
    let kind: AppKind
    var body: some View {
        let _ = store.revision
        let text = StudyCache.text(url)
        VStack(spacing: 0) {
            AppNoteHeader(url: url, kindLabel: kind.rawValue)
            Group {
                switch kind {
                case .mcq:
                    let q = StudyParse.questions(text)
                    if q.isEmpty { fallback(text) } else { QuizRunner(url: url, questions: q) }
                case .flashcards:
                    let c = StudyParse.cards(text)
                    if c.isEmpty { fallback(text) } else { DeckStudy(url: url, cards: c) }
                case .glossary:
                    let t = StudyParse.terms(text)
                    if t.isEmpty { fallback(text) } else { GlossaryTester(url: url, terms: t) }
                case .podcast:
                    let script = StudyParse.transcript(text)
                    if let a = StudyParse.audio(text) { EpisodePlayer(url: url, audio: a, transcript: script) }
                    else if !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ScriptOnlyEpisode(transcript: script) }
                    else { fallback(text) }
                }
            }
        }
    }
    /// What a note shows when the page can't use it: never its Markdown (that is behind "Edit note"), but what is missing.
    func fallback(_ text: String) -> some View {
        let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || StudyParse.lines(text).allSatisfy { l in l.isEmpty || l.hasPrefix("#") || l.hasPrefix("[!") }
        let (title, hint): (String, String) = switch kind {
        case .mcq: ("No questions yet", "Add numbered questions with options A. to D. and an Answer: line.")
        case .flashcards: ("No cards yet", "Add cards as a Front: line and a Back: line.")
        case .glossary: ("No terms yet", "Add one term per line as - **Term** — definition.")
        case .podcast: ("No audio linked yet", "Add an Audio: line with a link to the episode, then the transcript under its own heading.")
        }
        let shape: String = switch kind { case .mcq: "a quiz"; case .flashcards: "a deck"; case .glossary: "a glossary"; case .podcast: "an episode" }
        let message = blank ? hint : "Its text can’t be shown as \(shape). Press Edit note to see it. " + hint
        return EmptyAppNote(url: url, icon: kind.icon, title: blank ? title : "This note isn’t in the \(kind.rawValue) format", hint: message)
    }
}

/// An episode that is a script so far: the transcript is there, the audio is not. Shown as what it is, not as a broken note.
struct ScriptOnlyEpisode: View {
    let transcript: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.slash").foregroundStyle(Color.ink2)
                    Text("No audio yet. Add an Audio: line with a link to the episode to get the player.").font(.system(size: 13)).foregroundStyle(Color.ink2)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appCard()
                MarkdownView(text: transcript)
            }.frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 18).frame(maxWidth: .infinity)
        }
    }
}

/// What an app's note shows when the page can't use it yet: what is missing and how to add it. The Markdown stays behind "Edit note".
struct EmptyAppNote: View {
    @Environment(Store.self) private var store
    let url: URL
    let icon: String, title: String, hint: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Color.ink2.opacity(0.7))
            Text(title).font(.system(size: 18, weight: .semibold, design: .serif))
            Text(hint).font(.system(size: 13)).foregroundStyle(Color.ink2).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button { store.editingApps.insert(url) } label: { Label("Edit note", systemImage: "square.and.pencil") }.buttonStyle(.glassAction(.header, prominent: true))
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The top of an app's note page: back, the note's name and course, and Edit note (the only way to see the Markdown).
struct AppNoteHeader: View {
    @Environment(Store.self) private var store
    let url: URL
    let kindLabel: String
    var body: some View {
        let note = store.notes.first { $0.id == url }
        HStack(spacing: 10) {
            Button { store.goBack() } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .medium)) }
                .buttonStyle(.glassIcon()).disabled(!store.canGoBack).help("Back (⌘[)").accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 1) {
                Text(note?.display ?? url.deletingPathExtension().lastPathComponent).font(.system(size: 20, weight: .semibold, design: .serif)).lineLimit(1)
                Text([kindLabel, note?.course, note?.when.map { $0.formatted(.dateTime.day().month(.abbreviated)) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Color.ink2).lineLimit(1)
            }.padding(.leading, 6)
            Spacer(minLength: 12)
            Button { store.editingApps.insert(url) } label: { Label("Edit note", systemImage: "square.and.pencil") }.buttonStyle(.glassAction(.header))
            if let note { RoundButton(icon: "arrow.up.forward.app", label: "Open in Obsidian") { NSWorkspace.shared.open(Vault.obsidianURL(note)) } }
        }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 10)
    }
}

/// MCQ sub page: one question at a time, the answer straight after you choose, and a score at the end.
struct QuizRunner: View {
    let url: URL
    let questions: [StudyParse.Question]
    @State private var order: [Int] = []
    @State private var index = 0
    @State private var picks: [Int: String] = [:]
    @State private var finished = false

    var list: [Int] { order.isEmpty ? Array(questions.indices) : order }
    var scored: [Int] { list.filter { questions[$0].answer != nil } }
    var right: Int { scored.filter { picks[$0] == questions[$0].answer }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if finished { results } else if list.indices.contains(index) { question(questions[list[index]]) }
            }.frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity)
        }
    }

    func question(_ q: StudyParse.Question) -> some View {
        let chosen = picks[q.id]
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Question \(index + 1) of \(list.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink2)
                Spacer()
                Text("\(right) right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NoteColor.done).monospacedDigit()
            }
            MeterBar(value: Double(index) / Double(max(list.count, 1)), tint: IM.blue)
            rich(q.text).font(.system(size: 20, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(q.options, id: \.letter) { o in
                    let isRight = o.letter == q.answer
                    let tint: Color? = chosen == nil || q.answer == nil ? nil : isRight ? NoteColor.done : (chosen == o.letter ? Color.redFG : nil)
                    Button { if chosen == nil { withAnimation(.spring(duration: 0.3)) { picks[q.id] = o.letter } } } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(o.letter).font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26).background(Color.ink.opacity(0.08), in: .circle)
                            rich(o.text).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if let tint, isRight || chosen == o.letter { Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(tint) }
                        }.font(.system(size: 15)).padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character(o.letter.lowercased())), modifiers: [])
                    .glassEffect(tint.map { .regular.tint($0.opacity(0.3)) } ?? .regular, in: .rect(cornerRadius: DS.Radius.row))
                }
            }
            if chosen != nil, !q.note.isEmpty { rich(q.note).font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.horizontal, 4) }
            if chosen != nil {
                HStack {
                    Spacer()
                    Button { advance() } label: { Label(index + 1 < list.count ? "Next" : "See results", systemImage: "arrow.right") }
                        .buttonStyle(.glassAction(.header, prominent: true)).keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    func advance() {
        if index + 1 < list.count { withAnimation(.smooth) { index += 1 } }
        else {
            if list.count == questions.count, !scored.isEmpty { StudyProgress.record(url, score: right, total: scored.count) }
            withAnimation(.smooth) { finished = true }
        }
    }

    var results: some View {
        let missed = scored.filter { picks[$0] != questions[$0].answer }
        let frac = Double(right) / Double(max(scored.count, 1))
        return VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.ink.opacity(0.08), lineWidth: 12)
                Circle().trim(from: 0, to: frac).stroke(frac >= 0.7 ? NoteColor.done : Color.warnFG, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(right) / \(scored.count)").font(.system(size: 30, weight: .semibold, design: .serif)).monospacedDigit()
                    Text("\(Int(frac * 100))%").font(.system(size: 13)).foregroundStyle(Color.ink2)
                }
            }.frame(width: 170, height: 170).padding(.top, 10)
            if let best = StudyProgress.quiz(url) { Text("Best \(best.best) of \(best.total) · taken \(best.attempts) time\(best.attempts == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Color.ink2) }
            HStack(spacing: 10) {
                Button { restart(Array(questions.indices)) } label: { Label("Take it again", systemImage: "arrow.counterclockwise") }.buttonStyle(.glassAction(.header))
                if !missed.isEmpty { Button { restart(missed) } label: { Label("Retry the \(missed.count) you missed", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.glassAction(.header, prominent: true)) }
            }
            if !missed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What you missed").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink2)
                    ForEach(missed, id: \.self) { i in
                        let q = questions[i]
                        VStack(alignment: .leading, spacing: 4) {
                            rich(q.text).font(.system(size: 14, weight: .medium))
                            if let a = q.answer, let o = q.options.first(where: { $0.letter == a }) { rich("**\(a).** \(o.text)").font(.system(size: 13)).foregroundStyle(NoteColor.done) }
                            if !q.note.isEmpty { rich(q.note).font(.system(size: 12)).foregroundStyle(Color.ink2) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appCard(radius: DS.Radius.tile)
                    }
                }
            }
        }
    }

    func restart(_ these: [Int]) { order = these; picks = [:]; index = 0; withAnimation(.smooth) { finished = false } }
}

/// Flashcards sub page: a study session. "Again" puts a card back at the end; "Got it" keeps it as known, and that is remembered.
struct DeckStudy: View {
    let url: URL
    let cards: [StudyParse.Card]
    @State private var known: Set<String> = []
    @State private var queue: [Int] = []
    @State private var flipped = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(known.count) of \(cards.count) known").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink2).monospacedDigit()
                Spacer()
                if !queue.isEmpty { Text("\(queue.count) left in this round").font(.system(size: 12)).foregroundStyle(Color.ink2) }
                Menu {
                    Button("Shuffle this round") { queue.shuffle(); flipped = false }
                    Button("Study every card") { queue = Array(cards.indices); flipped = false }
                    Divider()
                    Button("Forget my progress", role: .destructive) { known = []; StudyProgress.setKnown(url, []); queue = Array(cards.indices); flipped = false }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24).contentShape(.rect) }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            MeterBar(value: Double(known.count) / Double(max(cards.count, 1)), tint: IM.blue)
            if let i = queue.first, cards.indices.contains(i) { card(cards[i]) } else if loaded { done }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 620).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
        .onAppear {
            guard !loaded else { return }
            known = StudyProgress.known(url)
            queue = cards.indices.filter { !known.contains(cards[$0].front) }
            loaded = true
        }
    }

    func card(_ c: StudyParse.Card) -> some View {
        VStack(spacing: 18) {
            Button { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { flipped.toggle() } } label: {
                ZStack {
                    face(c.front, label: "Front", tint: IM.blue).opacity(flipped ? 0 : 1)
                    face(c.back, label: "Back", tint: NoteColor.done).opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                }.rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
            }.buttonStyle(.plain).frame(height: 280).keyboardShortcut(.space, modifiers: []).accessibilityLabel(flipped ? "Back: \(c.back)" : "Front: \(c.front). Press to flip.")
            if flipped {
                HStack(spacing: 12) {
                    Button { again() } label: { Label("Again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }.buttonStyle(.glassAction(.header)).keyboardShortcut("1", modifiers: [])
                    Button { gotIt(c) } label: { Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity) }.buttonStyle(.glassAction(.header, prominent: true)).keyboardShortcut("2", modifiers: [])
                }
            } else { Text("Press space to flip").font(.system(size: 12)).foregroundStyle(Color.ink2) }
        }
    }

    func face(_ s: String, label: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            ScrollView { rich(s).font(.system(size: 20, design: .serif)).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: DS.Radius.card))
    }

    func gotIt(_ c: StudyParse.Card) {
        known.insert(c.front); StudyProgress.setKnown(url, known)
        flipped = false
        withAnimation(.smooth) { if !queue.isEmpty { queue.removeFirst() } }
    }
    func again() {
        flipped = false
        withAnimation(.smooth) { if let i = queue.first { queue.removeFirst(); queue.append(i) } }
    }

    var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(NoteColor.done).padding(.top, 30)
            Text(known.count >= cards.count ? "You know every card" : "Round finished").font(.system(size: 20, weight: .semibold, design: .serif))
            Text("\(known.count) of \(cards.count) known").font(.system(size: 13)).foregroundStyle(Color.ink2)
            HStack(spacing: 10) {
                Button { queue = Array(cards.indices); flipped = false } label: { Label("Study every card", systemImage: "rectangle.on.rectangle") }.buttonStyle(.glassAction(.header))
                Button { known = []; StudyProgress.setKnown(url, []); queue = Array(cards.indices); flipped = false } label: { Label("Start again", systemImage: "arrow.counterclockwise") }.buttonStyle(.glassAction(.header, prominent: true))
            }
        }
    }
}

/// Glossary sub page: the terms of one note in A–Z order, with a mode that hides the meanings so you can test yourself.
struct GlossaryTester: View {
    let url: URL
    let terms: [(term: String, meaning: String)]
    @State private var query = ""
    @State private var testing = false
    @State private var revealed: Set<String> = []
    var body: some View {
        let shown = terms.filter { query.isEmpty || $0.term.localizedCaseInsensitiveContains(query) || $0.meaning.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2); TextField("Search \(terms.count) terms", text: $query).textFieldStyle(.plain) }
                    .font(.system(size: 13)).glassField()
                Toggle(isOn: $testing) { Label("Test myself", systemImage: "eye.slash") }.toggleStyle(.button).buttonStyle(.glassAction(.control))
                    .onChange(of: testing) { revealed = [] }
            }.padding(.horizontal, 24).padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.term) { t in
                        let hidden = testing && !revealed.contains(t.term)
                        Button { if testing { withAnimation(.smooth) { if revealed.contains(t.term) { revealed.remove(t.term) } else { revealed.insert(t.term) } } } } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.term).font(.system(size: 16, weight: .semibold, design: .serif))
                                if hidden { Text("Tap to reveal").font(.system(size: 12)).foregroundStyle(Color.ink2.opacity(0.7)) }
                                else { rich(t.meaning).font(.system(size: 13)).foregroundStyle(Color.ink2).multilineTextAlignment(.leading) }
                            }.padding(.horizontal, 24).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }.buttonStyle(.plain)
                        Divider().padding(.horizontal, 24)
                    }
                    if shown.isEmpty { Text("No matching terms").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(24) }
                }.frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
    }
}

/// Podcast sub page: a player with skip, speed and a position that is remembered, above a transcript you can search.
struct EpisodePlayer: View {
    let url: URL
    let audio: URL
    let transcript: String
    @State private var player: AVPlayer
    @State private var playing = false
    @State private var rate = 1.0
    @State private var scrub: Double?
    @State private var query = ""

    init(url: URL, audio: URL, transcript: String) {
        self.url = url; self.audio = audio; self.transcript = transcript
        _player = State(initialValue: AVPlayer(url: audio))
    }

    var paragraphs: [String] {
        transcript.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform").font(.system(size: 26)).foregroundStyle(IM.blue).frame(width: 64, height: 64)
                            .background(IM.blue.opacity(0.14), in: .rect(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audio.deletingPathExtension().lastPathComponent).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                            Text(audio.isFileURL ? "In your vault" : audio.host() ?? "Web").font(.system(size: 12)).foregroundStyle(Color.ink2)
                        }
                        Spacer(minLength: 0)
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let t = player.currentTime().seconds
                        let d = player.currentItem?.duration.seconds ?? 0
                        let now = scrub ?? (t.isFinite ? t : 0)
                        let total = d.isFinite && d > 0 ? d : max(now, 1)
                        VStack(spacing: 4) {
                            Slider(value: Binding(get: { now }, set: { scrub = $0 }), in: 0...total, onEditingChanged: { editing in
                                if !editing, let s = scrub { player.seek(to: CMTime(seconds: s, preferredTimescale: 600)); scrub = nil }
                            })
                            HStack {
                                Text(clock(now)).monospacedDigit()
                                Spacer()
                                Text("-" + clock(total - now)).monospacedDigit()
                            }.font(.system(size: 11)).foregroundStyle(Color.ink2)
                        }
                    }
                    HStack(spacing: 26) {
                        Button { skip(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 22)) }.buttonStyle(.plain).help("Back 15 seconds")
                        Button { toggle() } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 24)).foregroundStyle(Color.card).frame(width: 60, height: 60).background(Color.ink, in: .circle)
                        }.buttonStyle(.plain).keyboardShortcut(.space, modifiers: []).help(playing ? "Pause" : "Play")
                        Button { skip(15) } label: { Image(systemName: "goforward.15").font(.system(size: 22)) }.buttonStyle(.plain).help("Forward 15 seconds")
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in Button("\(r.formatted())×") { setRate(r) } }
                        } label: { Text("\(rate.formatted())×").font(.system(size: 13, weight: .semibold)).frame(width: 46, height: 30).background(Color.ink.opacity(0.07), in: .capsule) }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Speed")
                    }.foregroundStyle(Color.ink)
                }.padding(20).appCard()

                if paragraphs.isEmpty && transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("This episode has no transcript.").font(.system(size: 13)).foregroundStyle(Color.ink2)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2); TextField("Search the transcript", text: $query).textFieldStyle(.plain) }
                            .font(.system(size: 13)).glassField()
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                            rich(p).font(.system(size: 14)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if paragraphs.isEmpty { Text("No matches").font(.system(size: 13)).foregroundStyle(Color.ink2) }
                    }
                }
            }.frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 18).frame(maxWidth: .infinity)
        }
        .onAppear {
            let p = StudyProgress.position(url)
            if p > 5 { player.seek(to: CMTime(seconds: p, preferredTimescale: 600)) }
        }
        .onDisappear {
            StudyProgress.setPosition(url, player.currentTime().seconds)
            player.pause()
        }
    }

    func toggle() {
        playing.toggle()
        if playing { player.defaultRate = Float(rate); player.play() } else { player.pause() }
    }
    func skip(_ s: Double) { player.seek(to: CMTime(seconds: max(0, player.currentTime().seconds + s), preferredTimescale: 600)) }
    func setRate(_ r: Double) {
        rate = r
        player.defaultRate = Float(r)
        if playing { player.rate = Float(r) }
    }
}
