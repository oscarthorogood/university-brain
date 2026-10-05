import Foundation
import FoundationModels

/// A note read by its `## ` sections, so a check can say exactly which parts a helper changed.
enum Sections {
    /// The frontmatter as `key → its block` (the key's line and any indented list lines under it), and the sections after it.
    static func parse(_ text: String) -> (front: [(key: String, block: String)], sections: [(title: String, body: String)]) {
        var lines = text.components(separatedBy: "\n"), front: [(String, String)] = []
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            var key: String?, block: [String] = []
            for l in lines[1..<end] {
                if !l.hasPrefix(" "), !l.hasPrefix("\t"), let c = l.firstIndex(of: ":") {
                    if let key { front.append((key, block.joined(separator: "\n"))) }
                    key = String(l[..<c]); block = [l]
                } else { block.append(l) }
            }
            if let key { front.append((key, block.joined(separator: "\n"))) }
            lines = Array(lines[(end + 1)...])
        }
        var sections: [(String, String)] = [("", "")], cur = 0
        for l in lines {
            if l.hasPrefix("## ") { sections.append((String(l.dropFirst(3)), "")); cur = sections.count - 1 }
            else { sections[cur].1 += l + "\n" }
        }
        return (front, sections)
    }
    /// A heading without its emoji, case or punctuation, so "🧱 Outline" and "Outline" match.
    static func normal(_ h: String) -> String { String(String.UnicodeScalarView(h.lowercased().unicodeScalars.filter { $0.properties.isAlphabetic || $0 == " " })).trimmingCharacters(in: .whitespaces) }   // emoji, and the invisible modifier after some of them, are dropped

    static func body(_ heading: String, in text: String) -> String? { parse(text).sections.first { normal($0.title) == normal(heading) }?.body }
    /// A line with its list and quote markers removed, so scaffolding compares equal whichever version of the template it came from.
    static func bare(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while let f = t.first, ">-*+ ".contains(f) { t.removeFirst() }
        t = t.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespaces).isEmpty ? "" : t
    }
    /// Whether Oscar or an agent has written anything in this section beyond the template's own scaffolding (callout titles, sub-headings, empty bullets,
    /// and a table's header and empty rows).
    static func hasContent(_ heading: String, in text: String, template: String) -> Bool {
        guard let mine = body(heading, in: text) else { return false }
        let known = Set(template.components(separatedBy: "\n").map(bare))
        var headerSeen = false
        for raw in mine.components(separatedBy: "\n") {
            let l = bare(raw)
            if l.isEmpty || known.contains(l) || l.hasPrefix("[!") || l.hasPrefix("#") { continue }
            if l.hasPrefix("|") {
                if !headerSeen { headerSeen = true; continue }   // the first table row is the header
                let cells = l.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.contains(where: { !$0.isEmpty && !$0.allSatisfy { "-: ".contains($0) } }) { return true }
                continue
            }
            return true
        }
        return false
    }
    /// Still the template.
    static func isTemplate(_ heading: String, in text: String, template: String) -> Bool { !hasContent(heading, in: text, template: template) }
    static func template(forFolder folder: String, root: URL = Vault.root) -> String {
        let name = ["Lectures": "Lecture", "Tutorials": "Tutorial", "Essays": "Essay", "Projects": "Projects", "Readings": "Readings", "Research": "Research"][folder] ?? Study.kind(folder)?.noun ?? folder
        return (try? String(contentsOf: Vault.template("\(name) Template", root: root), encoding: .utf8)) ?? ""
    }
}

/// The Manager's review of a helper's finished work. It runs on this Mac: plain checks first, then the on-device model for small pieces.
/// `problems` fail the job (one retry, then it is undone); `flags` are worth a second look and are logged.
enum Review {
    struct Verdict { var problems: [String] = []; var flags: [String] = []; var ok: Bool { problems.isEmpty } }

    static let injection = #"(?i)ignore (all |any )?(previous|prior|above) (instructions|prompts)|disregard (the )?(system|previous)|you are now|as an ai (language )?model"#
    static func hasInjection(_ s: String) -> Bool { s.range(of: injection, options: .regularExpression) != nil }

    /// Every file changed since `since`, outside the dot-folders: the way to see that a helper stayed inside what it was allowed to touch.
    static func touched(since: Date, root: URL) -> [String] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        for case let u as URL in walk {
            guard let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), v.isRegularFile == true, let m = v.contentModificationDate, m >= since else { continue }
            out.append(Vault.rel(u))
        }
        return out
    }
    /// `touched`, off the main thread: it walks the whole vault.
    static func touchedInBackground(since: Date, root: URL) async -> [String] {
        await Task.detached { touched(since: since, root: root) }.value
    }

    /// Structural checks on one edited note: nothing the helper wasn't given has changed.
    static func checkEdit(rel: String, before: String, after: String, sections allowed: [String]?, template: String) -> Verdict {
        var v = Verdict()
        let b = Sections.parse(before), a = Sections.parse(after)
        let free: Set<String> = ["status", "summary", "readings", "references", "related", "tags"]   // the Agent In Progress mark flips status; the rest are fields a job may fill
        for (key, block) in b.front where !free.contains(key) {
            guard let now = a.front.first(where: { $0.key == key }) else { v.problems.append("`\(key)` was removed from the frontmatter"); continue }
            if now.block != block, ["course", "Course", "base", "date", "due", "Lecture No.", "Tutorial No."].contains(key) { v.problems.append("`\(key)` was changed") }
        }
        let oldHeads = b.sections.map(\.title).filter { !$0.isEmpty }, newHeads = Set(a.sections.map { Sections.normal($0.title) })
        for h in oldHeads where !newHeads.contains(Sections.normal(h)) { v.problems.append("the section “\(h)” was removed") }
        if let allowed {
            let ok = Set(allowed.map(Sections.normal))
            for (title, body) in b.sections where !title.isEmpty && !ok.contains(Sections.normal(title)) {
                let now = a.sections.first { Sections.normal($0.title) == Sections.normal(title) }?.body ?? ""
                if now.trimmingCharacters(in: .whitespacesAndNewlines) != body.trimmingCharacters(in: .whitespacesAndNewlines) { v.problems.append("the section “\(title)” is not one this job may change, but it changed") }
            }
        }
        // Oscar's own lines (anything that isn't in the template) must still be there
        let beforeLines = before.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let afterLines = after.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let templateLines = Set(template.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        
        var lost = [String]()
        for change in afterLines.difference(from: beforeLines) {
            if case let .remove(_, line, _) = change, !line.isEmpty, !templateLines.contains(line), !line.hasPrefix("status:") {
                lost.append(line)
            }
        }
        if lost.count > 0 { v.problems.append("\(lost.count) of Oscar's own line\(lost.count == 1 ? "" : "s") disappeared (first: “\(lost[0].prefix(60))”)") }
        if hasInjection(after) { v.problems.append("the text contains instructions aimed at an AI, probably copied from a web page") }
        return v
    }

    /// Links to Resources files (`[[Resources/…/x.pdf|x.pdf]]`) that don't exist, ignoring any that were already dangling in `before`.
    static func missingFiles(in after: String, before: String = "", root: URL) -> [String] {
        func targets(_ s: String) -> Set<String> { Set(s.matches(of: /\[\[(Resources\/[^\]|#]+\.[A-Za-z0-9]{2,5})(?:[|#][^\]]*)?\]\]/).map { String($0.1) }) }
        return targets(after).subtracting(targets(before)).filter { !FileManager.default.fileExists(atPath: root.appending(path: Vault.real($0, root: root)).path) }.sorted()
    }

    /// Structural checks on a new note.
    static func checkNew(rel: String, text: String, template: String, folder: String, courses: Set<String>) -> Verdict {
        var v = Verdict()
        let p = Sections.parse(text), keys = p.front.map(\.key)
        for k in Sections.parse(template).front.map(\.key) where !keys.contains(k) { v.problems.append("the new note is missing `\(k)` in its frontmatter") }
        let name = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
        if name.contains(where: { "\\/:*?\"<>|".contains($0) }) { v.problems.append("the title has a character that isn't allowed") }
        if let base = p.front.first(where: { $0.key == "base" })?.block, !base.contains("\(folder).base") { v.problems.append("`base` should point to \(folder).base") }
        let course = (p.front.first { $0.key.lowercased() == "course" }?.block ?? "").components(separatedBy: "[[").last?.components(separatedBy: "]]").first ?? ""
        if !courses.contains(course) && folder != "Readings" { v.problems.append("`course` isn't one of your courses") }
        if folder == "Research" && !name.contains(" - Research - ") { v.problems.append("the title should be “<Course> - Research - <Topic>”") }
        if let k = Study.kind(folder), !name.contains(" - \(k.noun) - ") { v.problems.append("the title should be “<Course> - \(k.noun) - <Topic>”") }
        if hasInjection(text) { v.problems.append("the text contains instructions aimed at an AI, probably copied from a web page") }
        return v
    }

    /// Research briefs: every finding has a link, and every link opens.
    static func checkResearch(_ text: String) async -> Verdict {
        var v = Verdict()
        if let body = Sections.body("Findings", in: text) {
            let rows = body.components(separatedBy: "\n").filter { $0.contains("|") && !$0.contains("---") && !$0.lowercased().contains("| finding") && $0.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces).count > 2 }
            let bare = rows.filter { $0.range(of: #"https?://\S+"#, options: .regularExpression) == nil }
            if !bare.isEmpty { v.problems.append("\(bare.count) finding\(bare.count == 1 ? " has" : "s have") no source link") }
        }
        v.problems += await deadLinks(in: text)
        return v
    }

    /// Errors that mean the check couldn't run, not that the link is dead.
    private static let offline: Set<URLError.Code> = [.cancelled, .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff]
    /// Links in `text` that don't open (up to ten are tried).
    static func deadLinks(in text: String) async -> [String] {
        let urls = Array(Set(text.matches(of: /https?:\/\/[^\s)\]>"|]+/).map { String($0.0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) })).prefix(10)
        var dead: [String] = []
        await withTaskGroup(of: String?.self) { g in
            for u in urls {
                g.addTask {
                    guard let url = URL(string: u) else { return nil }
                    var r = URLRequest(url: url, timeoutInterval: 8); r.httpMethod = "GET"; r.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    do {
                        let (_, resp) = try await URLSession.shared.data(for: r)
                        guard let code = (resp as? HTTPURLResponse)?.statusCode else { return nil }
                        // 403 and 429 are sites refusing a program, not a dead page
                        return code >= 400 && code != 403 && code != 429 ? "\(u) (\(code))" : nil
                    } catch let e as URLError where Self.offline.contains(e.code) {
                        return nil   // this Mac is offline or the check was cancelled: that says nothing about the link
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return "\(u) (no answer)"
                    }
                }
            }
            for await d in g { if let d { dead.append(d) } }
        }
        if Task.isCancelled { return [] }   // a cancelled check proves nothing, so it can't fail a job
        return dead.isEmpty ? [] : ["link\(dead.count == 1 ? "" : "s") that don't open: " + dead.prefix(3).joined(separator: ", ")]
    }

    /// The Analyst's answers, one per question, from the `**Answer:**` lines in the note.
    static func answers(in text: String) -> [String] { text.matches(of: /\*\*Answer:\*\*\s*(.+)/).map { String($0.1) } }
    /// Every number in an answer, without its question label (`Q2:`) or markdown, so "Q1: 1,000 units" gives 1000 and not 1.
    static func numbers(_ s: String) -> [Double] {
        let clean = s.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: #"^\s*Q\d+\s*[:.)]\s*"#, with: "", options: .regularExpression)
        return clean.matches(of: /-?\d+(\.\d+)?/).compactMap { Double(String($0.0)) }
    }
    static func firstNumber(_ s: String) -> Double? { numbers(s).first }
    private static func close(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= max(abs(x), abs(y), 1e-9) * 0.01 }
    /// The first run's answers against the independent second run (`Q<n>: …` lines): numbers must agree to within 1%.
    static func compare(first: [String], second: String) -> Verdict {
        var v = Verdict()
        let other = second.components(separatedBy: "\n").compactMap { l -> (Int, String)? in
            guard let m = l.firstMatch(of: /^\s*Q(\d+)\s*[:.)]\s*(.+)/), let n = Int(m.1) else { return nil }
            return (n, String(m.2))
        }
        if other.isEmpty || first.isEmpty { v.flags.append("the answers couldn't be compared (no second run to check against)"); return v }
        for (i, a) in first.enumerated() {
            guard let b = other.first(where: { $0.0 == i + 1 })?.1 else { continue }
            let x = numbers(a), y = numbers(b)
            if !x.isEmpty, !y.isEmpty {
                // every number in the shorter answer has to appear in the longer one (one may say more than the other)
                let (few, many) = x.count <= y.count ? (x, y) : (y, x)
                if !few.allSatisfy({ n in many.contains { close(n, $0) } }) { v.problems.append("question \(i + 1): the two independent solutions disagree (\(a.prefix(40)) against \(b.prefix(40)))") }
            } else if a.lowercased().filter(\.isLetter) != b.lowercased().filter(\.isLetter) { v.flags.append("question \(i + 1): answers differ in wording and have no number to compare") }
        }
        return v
    }

    /// One small question to the on-device model about a piece of text (it can't hold more). nil when the model isn't available.
    static func judge(_ rule: String, of text: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let prompt = "Text:\n\(text.prefix(1500))\n\nQuestion: \(rule)\nReply `ok` if yes, or `doubt:` followed by a few words if not."
        guard let reply = try? await LanguageModelSession().respond(to: prompt).content else { return nil }
        return reply.lowercased().hasPrefix("doubt") ? String(reply.prefix(120)) : nil
    }
}
