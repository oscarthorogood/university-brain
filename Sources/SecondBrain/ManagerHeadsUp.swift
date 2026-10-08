import Foundation
import FoundationModels

/// What the Manager notices without spending a token: plain rules over the vault, shown as bubbles on the stage.
extension Store {
    func whenText(_ d: Date) -> String {
        (Calendar.current.isDateInToday(d) ? "today" : d.formatted(.dateTime.weekday(.wide))) + " at " + d.formatted(.dateTime.hour().minute())
    }

    // MARK: "Got it" (hides a heads-up for a day)
    private var gotItDates: [String: Date] { (UserDefaults.standard.dictionary(forKey: "gotIt") as? [String: Date]) ?? [:] }
    func gotIt(_ key: String) {
        var d = gotItDates.filter { $0.value > .now.addingTimeInterval(-86400) }
        d[key] = .now
        UserDefaults.standard.set(d, forKey: "gotIt")
        revision += 1
    }
    private func hidden(_ key: String) -> Bool { (gotItDates[key] ?? .distantPast) > .now.addingTimeInterval(-86400) }

    /// Things worth a nudge now. `course` limits them to one course (for a course agent's stage).
    func headsUps(course c: String? = nil) -> [Say] {
        var out: [Say] = []
        let current = notes.filter { $0.course != nil && (c == nil || $0.course == c) }
        func add(_ key: String, _ text: String, go: Page? = nil, role: String? = nil, prompt: String? = nil) {
            if !hidden(key) { out.append(Say(text: text, go: go, gotIt: key, askRole: role, askPrompt: prompt)) }
        }
        // a class starting within a day with no slides linked
        for n in current where ["Lectures", "Tutorials"].contains(n.folder) && !n.done {
            guard let w = n.when, w > .now, w < .now.addingTimeInterval(86400) else { continue }
            let text = (try? String(contentsOf: n.id, encoding: .utf8)) ?? ""
            if Vault.rawItems(text, "resources").allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                add("slides:\(n.path)", "\(n.display) is \(whenText(w)) and has no slides linked yet.", go: .note(n.id))
            }
        }
        // a class that has happened, isn't written up and has no slides to write it up from
        let slideless = current.filter { n in
            guard ["Lectures", "Tutorials"].contains(n.folder), n.unfilled, let w = n.when, (-7...(-1)).contains(days(w)) else { return false }
            let text = (try? String(contentsOf: n.id, encoding: .utf8)) ?? ""
            return Vault.rawItems(text, "resources").allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }.sorted { $0.whenOrFar > $1.whenOrFar }
        for n in slideless.prefix(2) {
            add("noslides:\(n.path)", "\(n.display) was \(-days(n.whenOrFar)) day\(days(n.whenOrFar) == -1 ? "" : "s") ago and still has no slides. Drop them in Unsorted and Scribe will write it up.", go: .note(n.id))
        }
        // an agent the loop breaker has paused (it is easy to miss, and nothing else says why its jobs stopped)
        if c == nil {
            for r in Agent.roles { if let until = breakerUntil(r.id) { add("paused:\(r.id)", "\(r.name) is paused until \(whenText(until)) after failing the Manager’s review three times. Resume it in Settings → Agents.") } }
        }
        // essays and projects due within a week that haven't been started
        for n in current where ["Essays", "Projects"].contains(n.folder) && !n.done && n.status == "Not started" {
            guard let w = n.when, (0...7).contains(days(w)) else { continue }
            add("due:\(n.path)", "\(n.display) is due in \(days(w)) day\(days(w) == 1 ? "" : "s") and hasn’t been started.", go: .note(n.id))
        }
        // a reading due tomorrow (or just missed) that still has no source
        for n in current where n.folder == "Readings" && !n.done && (n.status == "To Find" || n.title.contains("Title To Confirm")) {
            guard let w = n.when, (-3...1).contains(days(w)) else { continue }
            add("read:\(n.path)", "“\(n.title)” is due \(days(w) <= 0 ? "now" : "tomorrow") and still needs its source.", go: .note(n.id))
        }
        // a lecture was written up in the last few days: offer MCQs
        // (only the latest one, so these don't crowd out everything else)
        let fresh = current.filter { $0.folder == "Lectures" && $0.done && !$0.unfilled && ($0.when.map { $0 < .now && $0 > .now.addingTimeInterval(-3 * 86400) } ?? false) }
        for n in fresh.sorted(by: { $0.whenOrFar > $1.whenOrFar }).prefix(1) {
            add("mcq:\(n.path)", "\(n.display) is written up. Want 5 MCQs on it?", role: "tutor", prompt: "Make 5 MCQs with answers from \(n.title), quoting the slides.")
        }
        return out
    }

    // MARK: Morning brief (the first time the app is open each day; Mondays add one line per course)
    var briefOn: Bool { UserDefaults.standard.object(forKey: "briefOn") as? Bool ?? true }
    func maybeBrief() {
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard briefOn, UserDefaults.standard.string(forKey: "lastBrief") != today, !thinking.contains(Agent.manager.id), !notes.isEmpty else { return }
        UserDefaults.standard.set(today, forKey: "lastBrief")
        chats[Agent.manager.id, default: []].append(Message(fromAgent: false, text: "Morning brief"))
        chats[Agent.manager.id, default: []].append(Message(fromAgent: true, text: composeBrief() + (briefTeamLine().map { "\n\n" + $0 } ?? "")))
    }
    /// The day in plain facts, written on this Mac: no model, no cost.
    func composeBrief() -> String {
        let cal = Calendar.current, end = cal.date(byAdding: .day, value: 7, to: self.today)!
        func at(_ d: Date) -> String { cal.component(.hour, from: d) == 0 ? d.formatted(.dateTime.weekday(.abbreviated)) : d.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        let classes = notes.filter { $0.course != nil && ["Lectures", "Tutorials"].contains($0.folder) && !$0.done && ($0.when.map { cal.isDateInToday($0) } ?? false) }.sorted { $0.whenOrFar < $1.whenOrFar }
        let due = notes.filter { ["Essays", "Projects", "TaskNotes/Tasks"].contains($0.folder) && !$0.done && ($0.when.map { $0 >= self.today && $0 < end } ?? false) }.sorted { $0.whenOrFar < $1.whenOrFar }
        var out = ["**Today:** " + (classes.isEmpty ? "no classes." : classes.map { "\($0.whenOrFar.formatted(.dateTime.hour().minute())) \($0.display)" }.joined(separator: ", ") + ".")]
        out.append("**Due this week:** " + (due.isEmpty ? "nothing." : due.prefix(5).map { "\($0.display) (\(at($0.whenOrFar)))" }.joined(separator: ", ") + (due.count > 5 ? " and \(due.count - 5) more." : ".")))
        if let first = due.first(where: { $0.state == .notStarted }), let w = first.when { out.append("**Start with:** \(first.display), due in \(days(w)) day\(days(w) == 1 ? "" : "s") and not started.") }
        else if let w = due.first?.when, let n = due.first { out.append("**Next up:** \(n.display), \(at(w)).") }
        return out.joined(separator: "\n\n")
    }
}

/// Is a file waiting in Unsorted worth a Claude run? Decided on this Mac, so skipping costs nothing.
enum Triage {
    @Generable struct Verdict {
        @Guide(description: "file if it looks like study material or a student's own note, skip if it is empty, junk, an installer or unrelated to university study", .anyOf(["file", "skip"]))
        var verdict: String
    }
    static var available: Bool { if case .available = SystemLanguageModel.default.availability { true } else { false } }

    /// True unless the on-device model is sure every file is junk. When it can't tell, the file is worth a look.
    static func worthIt(_ files: [URL]) async -> Bool {
        guard available else { return true }
        for f in files {
            let text = Detect.excerpt(f)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }   // can't read it (a PDF scan, audio): let Sorter judge
            let prompt = "A student dropped this file into their university inbox. Filename: \(f.lastPathComponent)\nStart of it: \(text.prefix(800))"
            guard let v = try? await LanguageModelSession().respond(to: prompt, generating: Verdict.self).content.verdict else { return true }
            if v == "file" { return true }
        }
        return false
    }
}
