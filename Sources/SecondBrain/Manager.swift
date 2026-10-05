import Foundation
import FoundationModels
import SwiftUI

/// The front door: decides which agent takes a request and how much effort it deserves.
/// Keyword rules first (instant, free), the on-device model when the rules are unsure, then a safe default.
/// It only routes and sets effort; what an agent may do (read-only chat, edits after a tick) is unchanged.
enum Manager {
    /// quick = lookups; standard = explaining, planning, write-ups; deep = writing help and rubric checks.
    enum Tier: String, Sendable, Comparable, CaseIterable {
        case quick, standard, careful, deep   // careful: Sonnet at high effort, for the Analyst
        static func < (a: Tier, b: Tier) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
        static func clamp(_ t: Tier, max m: Tier) -> Tier { Swift.min(t, m) }
        var args: [String] {
            switch self {
            case .quick: ["--model", "haiku", "--effort", "low"]
            case .standard: ["--model", "sonnet", "--effort", "medium"]
            case .careful: ["--model", "sonnet", "--effort", "high"]   // always explicit: a resumed session otherwise keeps the model it last ran on
            case .deep: ["--model", "opus", "--effort", "high"]
            }
        }
    }
    struct Route: Sendable { let agent: String; let tier: Tier; let reason: String; let by: String }

    /// Settings → Agents. Off: every run is plain `claude -p`, as before.
    static var on: Bool { UserDefaults.standard.object(forKey: "managerOn") as? Bool ?? true }
    /// Settings → Agents: the highest effort the Manager may pick on its own.
    static var ceiling: Tier { Tier(rawValue: UserDefaults.standard.string(forKey: "managerMax") ?? "") ?? .deep }
    /// Flags for a run; also counts it, so Settings can show how the week was spent.
    static func args(_ tier: Tier) -> [String] {
        guard on else { return [] }
        let t = Tier.clamp(tier, max: ceiling), key = "tierCount-" + Date.now.formatted(.iso8601.year().month().day()) + "-" + t.rawValue
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        return t.args
    }
    /// Runs this week by tier, for Settings.
    static func weekCounts() -> [Tier: Int] {
        var out: [Tier: Int] = [:]
        for d in 0..<7 {
            let day = Date.now.addingTimeInterval(Double(-d) * 86400).formatted(.iso8601.year().month().day())
            for t in Tier.allCases { out[t, default: 0] += UserDefaults.standard.integer(forKey: "tierCount-\(day)-\(t.rawValue)") }
        }
        return out
    }

    /// Effort for a request to an agent the person already chose.
    static func tier(_ text: String, role: String) -> Tier {
        let t = text.lowercased()
        if role == "analyst" { return .careful }   // maths: accuracy over speed
        if role == "researcher" { return .standard }   // web research is costly whatever the question
        if role == "writer" || ["rubric", "draft", "compare", "synthes"].contains(where: t.contains) { return .deep }
        return isLookup(t) ? .quick : .standard
    }
    /// Effort for a job an agent plans on a note: only essay and project help needs the big model.
    static func workTier(_ role: String) -> Tier { role == "writer" ? .deep : role == "analyst" ? .careful : .standard }

    // Most specific first: this is also the tie-break when the on-device model isn't available.
    static let groups: [(agent: String, words: [String])] = [
        ("analyst", ["calculate", "solve", "worked solution", "formula", "probability", "regression", "forecast", "optimis", "linear programming", "queueing", "break-even", "breakeven", "check my working", "check my answers"]),
        ("researcher", ["research", "evidence for", "find out", "look into", "background on", "background for", "industry", "market data", "statistics", "competitor", "literature", "latest data"]),
        ("writer", ["essay", "report", "draft", "outline", "rubric", "word count", "word limit", "thesis", "proposal", "poster", "write my", "case study", "assessment", "reference list", "bibliography"]),
        ("tutor", ["podcast", "quiz", "mcq", "revise", "revision", "flashcard", "test me", "past paper", "practice question", "explain"]),
        ("librarian", ["reading", "citation", "cite", "source", "to find", "title to confirm"]),
        ("sorter", ["unsorted", "inbox", "sort now", "file this", "file now"]),
        ("scribe", ["write up", "write-up", "lecture notes", "slides"]),
        ("planner", ["due", "deadline", "schedule", "clash", "prep me", "calendar", "key date", "what's next", "whats next"]),
    ]
    /// Date words alone point at Planner, but next to another job ("MCQs from this week's lectures") they don't.
    static let weakPlanner = ["today", "tomorrow", "this week", "next week"]
    /// A short single question that is just a lookup. "Where are we…" and compound questions need real synthesis, so they aren't.
    static func isLookup(_ t: String) -> Bool {
        t.count < 120 && !t.contains(" and ") && !t.contains(",") && ["what", "which", "when", "list", "any", "how many", "is ", "are "].contains { t.hasPrefix($0) }
    }

    static func course(_ t: String) -> String? {
        func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        if has(#"\bmsoa\b|management science|operations analytics"#) { return "MSOA" }
        if has(#"\bsm\b|strateg"#) { return "SM" }
        if has(#"\btem\b|entrepreneur"#) { return "TEM" }
        return nil
    }

    /// Background jobs only start while the Claude plan has room: Opus work needs more of it than the rest.
    static func hasRoom(five: Double, week: Double, deep: Bool, preset: String = "balanced") -> Bool {
        let b = Store.budgets.first { $0.id == preset } ?? Store.budgets[1]
        return deep ? five < b.deepFive && week < b.deepWeek : five < b.five && week < b.week
    }
    /// An essay or project whose Brief, Question and Marking criteria are still the template: Planner's job before Writer's.
    static func needsBrief(_ text: String) -> Bool { text.contains("Paste the exact essay question") || text.contains("Paste the exact task, case question") }

    /// An essay or project worth planning now: Planner's question and criteria are in, the outline is still the blank template.
    /// (Projects made before the template gained a Report outline section don't have one, so they stay on demand.)
    static func writerReady(_ n: Note, _ text: String) -> Bool {
        ["Essays", "Projects"].contains(n.folder) && !n.done && text.contains("| Introduction |  |")
            && !text.contains("Paste the exact essay question") && !text.contains("Paste the exact task, case question")
    }

    static func route(_ agent: String, _ text: String, why: String, by: String) -> Route {
        Route(agent: agent, tier: tier(text, role: agent), reason: why, by: by)
    }

    /// The rules alone: a route when they settle it, nil when the request is unclear or fits several agents.
    /// The agent groups a request matches.
    private static func hits(_ t: String) -> [(agent: String, words: [String])] {
        var hits = groups.filter { g in g.words.contains { t.contains($0) } }
        if hits.isEmpty, weakPlanner.contains(where: t.contains) { hits = groups.filter { $0.agent == "planner" } }
        // "what's due for my essay" is a deadline lookup, not essay help
        if hits.count > 1, hits.contains(where: { $0.agent == "planner" }), isLookup(t), t.contains("due") || t.contains("deadline") { hits = groups.filter { $0.agent == "planner" } }
        return hits
    }

    /// Pairs where the first agent finds or checks what the second needs. Keywords can't tell "from the slides" (a source) from
    /// "write up the slides" (a task), so only real dependencies are chained, and only when nothing else matched.
    static let pairs = [("librarian", "tutor"), ("researcher", "writer"), ("analyst", "tutor"), ("planner", "writer")]
    /// A request that needs agents working one after another: three at most, finishers (Tutor, Writer) last. Naming two or more agents does it too.
    static func chain(_ text: String) -> [Route]? {
        let t = text.lowercased()
        var agents: [String] = []
        for m in t.matches(of: /\b(sorter|scribe|librarian|planner|tutor|writer|researcher|analyst)\b/) where !agents.contains(String(m.1)) { agents.append(String(m.1)) }
        if agents.count < 2 {
            let h = hits(t).map(\.agent)
            guard h.count == 2, let p = pairs.first(where: { h.contains($0.0) && h.contains($0.1) }) else { return nil }
            agents = [p.0, p.1]
        }
        let ordered = (agents.filter { !["tutor", "writer"].contains($0) } + agents.filter { ["tutor", "writer"].contains($0) }).prefix(3)
        return ordered.map { route($0, text, why: Agent.role($0).job + ".", by: "rules") }
    }

    static func byRules(_ text: String) -> Route? {
        let t = text.lowercased()
        // Naming an agent ("hand off to the tutor", "ask the writer") settles it
        // (a bare "tutor", "writer" or "planner" is often a person, so those need a verb; the other names are only ever the agent)
        if let m = t.firstMatch(of: /\b(?:hand|pass|send|give|ask|tell|get|over to)\b.*?\b(sorter|scribe|librarian|planner|tutor|writer|researcher|analyst)\b/) ?? t.firstMatch(of: /\b(sorter|scribe|librarian|researcher|analyst)\b/) {
            return route(String(m.1), text, why: "You asked for \(Agent.role(String(m.1)).name).", by: "rules")
        }
        let found = hits(t)
        if found.count == 1 { return route(found[0].agent, text, why: Agent.role(found[0].agent).job + ".", by: "rules") }
        if found.isEmpty, let c = course(t) { return route(c, text, why: "It’s about \(Agent.role(c).name).", by: "rules") }
        return nil
    }
    /// When neither the rules nor the on-device model can say: the closest rule match, the course agent, or Planner.
    static func fallback(_ text: String) -> Route {
        let t = text.lowercased()
        if let first = groups.first(where: { g in g.words.contains { t.contains($0) } }) { return route(first.agent, text, why: "Fits several agents; \(Agent.role(first.agent).name) is the closest.", by: "rules") }
        if let c = course(t) { return route(c, text, why: "It’s about \(Agent.role(c).name).", by: "rules") }
        return route("planner", text, why: "Couldn’t tell, so Planner will look at it.", by: "default")
    }
    /// `previous` is who last answered in this chat: a short message with no clues ("start with what you know") is a follow-up to them.
    static func decide(_ text: String, previous: String? = nil) async -> Route {
        if let r = byRules(text) { return r }
        if let previous, text.count < 80 { return route(previous, text, why: "Following on from \(Agent.role(previous).name).", by: "follow-up") }
        if let r = await onDevice(text) { return r }
        return fallback(text)
    }

    /// Part of `--check`: routing the rules settle must keep going where it should, at the effort it should.
    static func check() {
        let cases: [(String, String, Tier)] = [
            ("What's due this week?", "planner", .quick), ("Plan my Strategy individual report from its brief", "writer", .deep),
            ("Make 5 MCQs from this week's lectures", "tutor", .standard), ("Which readings still need finding?", "librarian", .quick),
            ("What's in Unsorted?", "sorter", .quick), ("Where are we in TEM?", "TEM", .standard),
            ("Check my draft against the rubric", "writer", .deep), ("what's due for my essay", "planner", .quick),
            ("Where are we in Strategy, and what's coming up?", "SM", .standard), ("What's due and what should I start on?", "planner", .standard),
            ("quiz me on MSOA L04", "tutor", .standard), ("Write up lecture 3 from the slides", "scribe", .standard), ("Look into the market data for electric vehicles", "researcher", .standard), ("Solve question 3 on the queueing sheet", "analyst", .careful)]
        for (text, agent, tier) in cases {
            guard let r = byRules(text) else { preconditionFailure("rules should settle “\(text)”") }
            precondition(r.agent == agent && r.tier == tier, "“\(text)” went to \(r.agent)/\(r.tier.rawValue), expected \(agent)/\(tier.rawValue)")
        }
        for (text, agent) in [("hand off to the tutor then", "tutor"), ("make me a podcast on lecture 3", "tutor"), ("ask the writer to check my draft", "writer")] {
            precondition(byRules(text)?.agent == agent, "“\(text)” should go to \(agent)")
        }
        for (text, team) in [("Can you make a podcast for all of my readings for next week", ["librarian", "tutor"]), ("Make flashcards from this week's readings", ["librarian", "tutor"]),
                             ("Find evidence for my essay", ["researcher", "writer"]), ("have the writer use what the researcher finds", ["researcher", "writer"]),
                             ("Make 5 MCQs with answers from L04, quoting the slides", [])] {
            precondition((chain(text)?.map(\.agent) ?? []) == team, "“\(text)” should be the team \(team), not \(chain(text)?.map(\.agent) ?? [])")
        }
        let log = Agent.teamLog([Activity(time: .now, agent: "manager", text: "Sent x"), Activity(time: .now, agent: "tutor", text: "Made an MCQ set")])
        precondition(log.contains("Tutor") && log.contains("MCQ") && !log.contains("Sent x") && Agent.teamLog([]) == "", "team log: \(log)")
        precondition(byRules("hello there") == nil, "an unclear request is left to the on-device model")
        precondition(Manager.hasRoom(five: 0.3, week: 0.3, deep: true) && !Manager.hasRoom(five: 0.5, week: 0.3, deep: true) && Manager.hasRoom(five: 0.5, week: 0.3, deep: false) && !Manager.hasRoom(five: 0.7, week: 0.1, deep: false) && !Manager.hasRoom(five: 0.1, week: 0.8, deep: false) && Manager.hasRoom(five: 0.7, week: 0.3, deep: false, preset: "generous"), "budget thresholds")
        precondition(Manager.needsBrief("Paste the exact essay question") && !Manager.needsBrief("The question: why?"), "blank brief")
        precondition(Store.lineDiff("a\nb\nc", "a\nx\nc") == "- b\n+ x", "diff of what you changed: \(Store.lineDiff("a\nb\nc", "a\nx\nc"))")
        precondition(Tier.quick < Tier.deep && Tier.clamp(.deep, max: .standard) == .standard, "tier ceiling")
        print("routing ok: \(cases.count) requests go where they should")
    }

    @Generable struct Choice {
        @Guide(description: "The agent best placed to handle the request", .anyOf(["sorter", "scribe", "librarian", "planner", "tutor", "writer", "researcher", "analyst", "MSOA", "SM", "TEM"]))
        var agent: String
        @Guide(description: "quick for a simple lookup, standard for explaining, planning or summarising, deep for essay or project writing help, marking against a rubric or combining many notes", .anyOf(["quick", "standard", "deep"]))
        var effort: String
        @Guide(description: "Why, in under twelve words")
        var reason: String
    }

    /// Free and offline (Apple Intelligence). nil when it isn't available or fails.
    static func onDevice(_ text: String) async -> Route? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let team = (Agent.roles + Agent.courseRoles).map { "\($0.course ?? $0.id) = \($0.name): \($0.job)" }.joined(separator: "\n")
        let prompt = """
        You route requests from a university student to one agent. Agents:
        \(team)
        Course agents (MSOA, SM, TEM) answer questions about one course only. Pick a helper when the request is about a kind of work, a course agent when it is only about that course.
        Request: \(text)
        """
        guard let c = try? await LanguageModelSession().respond(to: prompt, generating: Choice.self).content,
              Agent.all.contains(where: { $0.id == c.agent }) else { return nil }
        return Route(agent: c.agent, tier: tier(text, role: c.agent), reason: c.reason.trimmingCharacters(in: .whitespaces), by: "on-device")
    }
}

/// On the Manager's page: how it decides, and what it sent where lately.
struct ManagerCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        let recent = Array(store.activity.filter { $0.agent == Agent.manager.id }.prefix(5))
        Card(title: "How I decide", trailing: Manager.on ? "On" : "Off in Settings") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keywords first, then your Mac’s own model when I’m unsure, so most requests cost nothing to route. Lookups run quick, explaining and planning standard, essay and project help deep. I also scan the vault myself and hand out work: Unsorted files, essays nearing a deadline, write-ups, readings.")
                    .foregroundStyle(Color.ink2)
                if recent.isEmpty { Text("Nothing sent yet.").foregroundStyle(Color.ink2) }
                ForEach(recent) { Text($0.text).lineLimit(2) }
            }.font(.system(size: 12)).padding(.horizontal, 16).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

extension Store {
    /// All work an agent is given is handed out by the Manager. This records who got what, at which effort, and why.
    func assign(_ agent: String, _ what: String, why: String) {
        log(Agent.manager.id, "Assigned to \(Agent.role(agent).name) (\(Manager.workTier(agent).rawValue)): \(what) — \(why)")
    }
}
