import SwiftUI
import AVKit

/// What each study type's note shows when you read it, built from the format its template asks for.
/// A note that doesn't follow the format (older ones) falls back to the ordinary reading view.
enum StudyParse {
    struct Question: Identifiable { let id: Int; var text: String; var options: [(letter: String, text: String)] = []; var answer: String?; var note = "" }
    struct Card: Identifiable { let id: Int; var front: String; var back = "" }

    /// Lines with quote markers stripped, so callout bodies read the same as plain text.
    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { l in
            var t = Substring(l); while let f = t.first, f == ">" || f == " " { t.removeFirst() }; return String(t)
        }
    }
    static func questions(_ text: String) -> [Question] {
        var out: [Question] = [], cur: Question?
        func flush() { if let c = cur, c.options.count >= 2, !c.text.hasPrefix("Question text") { out.append(c) }; cur = nil }
        for line in lines(text) {
            if let m = line.firstMatch(of: /^\s*[-*]?\s*\(?([A-F])[.)]\s+(.+)$/), cur != nil { cur!.options.append((String(m.1), String(m.2))); continue }
            if let m = line.firstMatch(of: /(?i)^\s*\**answer\**\s*:?\**\s*\(?\**([A-F])\b\)?\**[\s—–:.\-]*(.*)$/), cur != nil { cur!.answer = String(m.1).uppercased(); cur!.note = String(m.2); continue }
            if let m = line.firstMatch(of: /^\s*\**(\d+)[.)]\**\s+(.+)$/) { flush(); cur = Question(id: out.count, text: String(m.2)); continue }
        }
        flush(); return out
    }
    static func cards(_ text: String) -> [Card] {
        var out: [Card] = [], cur: Card?, onBack = false
        func flush() { if let c = cur, !c.front.isEmpty, !c.back.isEmpty, c.front != "Term or question" { out.append(c) }; cur = nil; onBack = false }
        for line in lines(text) {
            if let m = line.firstMatch(of: /(?i)^\s*(?:\d+[.)]\s*)?\**front\**\s*:\**\s*(.*)$/) { flush(); cur = Card(id: out.count, front: String(m.1)); continue }
            if let m = line.firstMatch(of: /(?i)^\s*\**back\**\s*:\**\s*(.*)$/), cur != nil { cur!.back = String(m.1); onBack = true; continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || cur == nil { continue }
            if onBack { cur!.back += "\n" + t } else { cur!.front += "\n" + t }
        }
        flush(); return out
    }
    static func terms(_ text: String) -> [(term: String, meaning: String)] {
        lines(text).compactMap { l in
            l.firstMatch(of: /^\s*[-*]\s+\*\*(.+?)\*\*\s*[—–:\-]\s*(.+)$/).map { (String($0.1), String($0.2)) }
        }.filter { $0.term != "Term" }.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
    }
    static func tree(_ text: String) -> [(level: Int, text: String)] {
        text.components(separatedBy: "\n").compactMap { l in
            guard let m = l.firstMatch(of: /^(\s*)[-*]\s+(.+)$/), !l.hasPrefix(">") else { return nil }
            let ws = m.1, level = ws.filter { $0 == "\t" }.count + ws.filter { $0 == " " }.count / 2
            return (level, String(m.2))
        }
    }
    /// Numbered questions, each with the text that follows it up to the next one: the part after "Answer" / "Mark scheme" is hidden until asked for.
    static func paper(_ text: String) -> [(question: String, answer: String)] {
        var out: [(String, String)] = [], q: String?, a = "", inAnswer = false
        func flush() { if let q, !q.hasPrefix("Question text") { out.append((q, a.trimmingCharacters(in: .whitespacesAndNewlines))) }; q = nil; a = ""; inAnswer = false }
        for line in lines(text) {
            if let m = line.firstMatch(of: /^\s*\**(\d+)[.)]\**\s+(.+)$/) { flush(); q = String(m.2); continue }
            guard q != nil else { continue }
            if line.firstMatch(of: /(?i)^\s*\**(answer|mark scheme|model answer)\b/) != nil { inAnswer = true; a += line.replacing(/(?i)^\s*\**(answer|mark scheme|model answer)\**\s*:?\**\s*/, with: "") + "\n"; continue }
            if line.hasPrefix("#") { flush(); continue }
            if inAnswer { a += line + "\n" } else if !line.isEmpty { q! += "\n" + line }
        }
        flush(); return out.filter { !$0.1.isEmpty || !$0.0.isEmpty }
    }
    /// The audio an episode note points at: an `Audio:` line holding a link to a file in the vault, or a web address.
    static func audio(_ text: String) -> URL? {
        guard let m = text.firstMatch(of: /(?im)^[ \t]*audio[ \t]*:[ \t]*(.+)$/) else { return nil }   // same line only: an empty `Audio:` must not pick up the next line
        let v = String(m.1)
        if let link = v.firstMatch(of: /\[\[([^\]|#]+)/) {
            let t = String(link.1), u = Vault.root.appending(path: Vault.real(t))
            if FileManager.default.fileExists(atPath: u.path) { return u }
            let name = (t as NSString).lastPathComponent
            return FileManager.default.enumerator(at: Vault.root.appending(path: Vault.dir("Podcast")), includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.lastPathComponent == name }
        }
        if let w = v.firstMatch(of: /https?:\/\/\S+/) { return URL(string: String(w.0)) }
        return nil
    }
    static func transcript(_ text: String) -> String {
        guard let r = text.range(of: #"(?m)^##.*[Tt]ranscript.*$"#, options: .regularExpression) else { return "" }
        let rest = text[r.upperBound...]
        return String(rest[..<(rest.range(of: #"(?m)^##\s"#, options: .regularExpression)?.lowerBound ?? rest.endIndex)])
    }
}

extension StudyParse {
    /// Self-check: each template's format parses into what its preview needs.
    static func check() {
        let mcq = questions("1. Which?\n   - A. One\n   - B. Two\n\n   **Answer:** B — because.\n\n2. Next?\n   - A. x\n   - B. y\n   **Answer:** A")
        precondition(mcq.count == 2 && mcq[0].options.count == 2 && mcq[0].answer == "B" && mcq[0].note == "because." && mcq[1].answer == "A", "mcq parse")
        precondition(questions("1. Question text?\n   - A. a\n   - B. b").isEmpty, "the template's example question is skipped")
        let cs = cards("Front: What is X?\nBack: A thing\n\n1. Front: Y?\n\nBack: Another\nspans")
        precondition(cs.count == 2 && cs[0].back == "A thing" && cs[1].back.contains("spans"), "flashcards parse")
        let gl = terms("- **Beta** — second\n- **Alpha** — first")
        precondition(gl.map(\.term) == ["Alpha", "Beta"], "glossary parse and sort")
        let tr = tree("- Centre\n  - Branch\n    - Leaf\n  - Branch two")
        precondition(tr.map(\.level) == [0, 1, 2, 1], "mind map levels")
        let pp = paper("1. Explain X. (10 marks)\n\n   **Mark scheme:** Points.\n\n2. Define Y.\n   **Answer:** Z")
        precondition(pp.count == 2 && pp[0].answer == "Points." && pp[1].answer == "Z", "past paper parse")
        precondition(transcript("## 🎧 Episode\nAudio: x\n\n## 📝 Transcript\n\nHello\n\n## 💡 Takeaways\n- a").contains("Hello"), "transcript section")
        precondition(audio("Audio: \n\n## 📝 Transcript\nhttps://example.com/a.mp3") == nil && audio("Audio: https://example.com/a.mp3") != nil, "an empty Audio: line stays empty")
        print("study previews ok: quiz, cards, glossary, mind map, past paper and transcript formats parse")
    }
}

struct StudyPreview: View {
    let kind: Study.Kind; let text: String
    var body: some View {
        switch kind.folder {
        case "MCQ": let q = StudyParse.questions(text); if q.isEmpty { plain } else { MCQView(questions: q) }
        case "Flashcards": let c = StudyParse.cards(text); if c.isEmpty { plain } else { FlashcardsView(cards: c) }
        case "Glossary": let t = StudyParse.terms(text); if t.isEmpty { plain } else { GlossaryView(terms: t) }
        case "Mind Maps": let t = StudyParse.tree(text); if t.count < 2 { plain } else { MindMapView(nodes: t) }
        case "Past Papers": let p = StudyParse.paper(text); if p.isEmpty { plain } else { PastPaperView(items: p) }
        case "Podcast": if let u = StudyParse.audio(text) { PodcastView(url: u, transcript: StudyParse.transcript(text)) } else { plain }
        default: plain
        }
    }
    var plain: some View { MarkdownView(text: text).padding(22) }
}

private func rich(_ s: String) -> Text { Text(MD.inline(s)) }

struct MCQView: View {
    let questions: [StudyParse.Question]
    @State private var picks: [Int: String] = [:]
    var body: some View {
        let scored = questions.filter { $0.answer != nil && picks[$0.id] != nil }
        let right = scored.filter { picks[$0.id] == $0.answer }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("\(questions.count) questions", systemImage: "checklist").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !picks.isEmpty {
                    Text("\(right) / \(scored.count) right").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(NoteColor.done)
                    Button("Reset") { withAnimation { picks = [:] } }.buttonStyle(.glassAction(.chip))
                }
            }
            ForEach(questions) { q in
                VStack(alignment: .leading, spacing: 8) {
                    rich("**\(q.id + 1).** " + q.text).font(.system(size: 14))
                    ForEach(q.options, id: \.letter) { o in
                        let chosen = picks[q.id], isRight = o.letter == q.answer
                        let tint: Color? = chosen == nil ? nil : isRight ? NoteColor.done : (chosen == o.letter ? Color.redFG : nil)
                        Button { if chosen == nil { withAnimation(.spring(duration: 0.3)) { picks[q.id] = o.letter } } } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(o.letter).font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22).background(Color.ink.opacity(0.08), in: .circle)
                                rich(o.text).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if let tint, isRight || chosen == o.letter { Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(tint) }
                            }.font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(tint.map { .regular.tint($0.opacity(0.3)) } ?? .regular, in: .rect(cornerRadius: DS.Radius.row))
                    }
                    if picks[q.id] != nil, !q.note.isEmpty { rich(q.note).font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 4) }
                }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlashcardsView: View {
    let cards: [StudyParse.Card]
    @State private var index = 0
    @State private var flipped = false
    var body: some View {
        let card = cards[min(index, cards.count - 1)]
        VStack(spacing: 18) {
            Text("Card \(index + 1) of \(cards.count)").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.top, 22)
            Button { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { flipped.toggle() } } label: {
                ZStack {
                    face(card.front, label: "Front", tint: IM.blue).opacity(flipped ? 0 : 1)
                    face(card.back, label: "Back", tint: NoteColor.done).opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                }.rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
            }.buttonStyle(.plain).frame(height: 240).padding(.horizontal, 22).accessibilityLabel(flipped ? "Back: \(card.back)" : "Front: \(card.front). Press to flip.")
            HStack(spacing: 12) {
                RoundButton(icon: "chevron.left", label: "Previous card") { go(index - 1) }.disabled(index == 0).opacity(index == 0 ? 0.4 : 1)
                Button { flipped.toggle() } label: { Label(flipped ? "Show front" : "Show back", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.glassAction(.header))
                RoundButton(icon: "shuffle", label: "Random card") { go(Int.random(in: 0..<cards.count)) }
                RoundButton(icon: "chevron.right", label: "Next card") { go(index + 1) }.disabled(index >= cards.count - 1).opacity(index >= cards.count - 1 ? 0.4 : 1)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity).padding(.bottom, 22)
    }
    func go(_ i: Int) { flipped = false; withAnimation(.spring(duration: 0.3)) { index = min(max(i, 0), cards.count - 1) } }
    func face(_ s: String, label: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            ScrollView { rich(s).font(.system(size: 17)).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: DS.Radius.card))
    }
}

struct GlossaryView: View {
    let terms: [(term: String, meaning: String)]
    @State private var query = ""
    var body: some View {
        let shown = terms.filter { query.isEmpty || $0.term.localizedCaseInsensitiveContains(query) || $0.meaning.localizedCaseInsensitiveContains(query) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2); TextField("Search \(terms.count) terms", text: $query).textFieldStyle(.plain) }
                .font(.system(size: 13)).glassField().padding(.horizontal, 22).padding(.vertical, 14)
            ForEach(shown, id: \.term) { t in
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.term).font(.system(size: 14, weight: .semibold))
                    rich(t.meaning).font(.system(size: 13)).foregroundStyle(Color.ink2)
                }.padding(.horizontal, 22).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                Divider().padding(.horizontal, 22)
            }
            if shown.isEmpty { Text("No matching terms").font(.system(size: 13)).foregroundStyle(Color.ink2).padding(22) }
        }
    }
}

struct MindMapView: View {
    let nodes: [(level: Int, text: String)]
    var body: some View {
        let hues: [Color] = [IM.blue, NoteColor.done, Color(light: 0xC77A00, dark: 0xF0B366), Color(light: 0x7A56E0, dark: 0xA68CFF), Color(light: 0xB42318, dark: 0xFF8A7A)]
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, n in
                    HStack(spacing: 0) {
                        ForEach(0..<n.level, id: \.self) { _ in Rectangle().fill(Color.line).frame(width: 1, height: 28).padding(.horizontal, 13) }
                        if n.level > 0 { Rectangle().fill(Color.line).frame(width: 14, height: 1) }
                        rich(n.text).font(.system(size: n.level == 0 ? 15 : 13, weight: n.level == 0 ? .semibold : .regular)).padding(.horizontal, 12).padding(.vertical, 6)
                            .glassEffect(.regular.tint(hues[n.level % hues.count].opacity(n.level == 0 ? 0.35 : 0.2)), in: .capsule)
                    }
                }
            }.padding(22)
        }
    }
}

struct PastPaperView: View {
    let items: [(question: String, answer: String)]
    @State private var open: Set<Int> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 8) {
                    rich("**\(i + 1).** " + item.question).font(.system(size: 14))
                    if !item.answer.isEmpty {
                        Button { withAnimation(.spring(duration: 0.3)) { if open.contains(i) { open.remove(i) } else { open.insert(i) } } } label: {
                            Label(open.contains(i) ? "Hide answer" : "Show answer", systemImage: open.contains(i) ? "eye.slash" : "eye")
                        }.buttonStyle(.glassAction(.chip))
                        if open.contains(i) { rich(item.answer).font(.system(size: 13)).foregroundStyle(Color.ink2).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.tint(NoteColor.done.opacity(0.15)), in: .rect(cornerRadius: DS.Radius.row)) }
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.tile))
            }
        }.padding(22)
    }
}

struct PodcastView: View {
    let url: URL; let transcript: String
    @State private var player: AVPlayer
    init(url: URL, transcript: String) { self.url = url; self.transcript = transcript; _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 22)).foregroundStyle(IM.blue)
                VStack(alignment: .leading, spacing: 1) { Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1); Text(url.isFileURL ? "In your vault" : url.host() ?? "Web").font(.system(size: 11)).foregroundStyle(Color.ink2) }
                Spacer()
            }
            VideoPlayer(player: player).frame(height: 54).clipShape(.rect(cornerRadius: DS.Radius.row))
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Transcript").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2)
                MarkdownView(text: transcript)
            }
        }.padding(22).onDisappear { player.pause() }
    }
}
