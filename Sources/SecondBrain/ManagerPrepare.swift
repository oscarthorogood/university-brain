import Foundation

extension Manager {
    /// "Get me ready for Thursday's SM lecture", "catch me up on TEM": a request for the whole team's help on a course (or on everything), not for one agent.
    static func isPrepare(_ text: String) -> Bool {
        text.lowercased().range(of: #"\b(get me (ready|prepared|caught up)|catch me up|set me up|prep(are)? me|get ready for|prepare for|prep for|get (everything|things) ready|do everything (for|needed))\b"#, options: .regularExpression) != nil
    }
}

extension Store {
    /// The Manager lines up everything the team could usefully do right now (for one course, if the request names it), then works through it, a job at a time.
    /// Every job goes through the same consult, work and review as the Manager's own, so each is checked and can be undone from the Activity Log.
    func prepare(_ text: String) {
        let m = Agent.manager.id
        guard !thinking.contains(m) else { return }
        chats[m, default: []].append(Message(fromAgent: false, text: text))
        thinking.insert(m)
        let course = Manager.course(text.lowercased())
        let scope = course.map { Agent.role($0).name } ?? "everything"
        chatTasks[m] = Task { [weak self] in
            guard let self else { return }
            defer { self.chatTasks[m] = nil; self.thinking.remove(m) }
            let jobs = self.scan().filter { found in
                switch found.job {
                case .work(let n, _, _, _): return course == nil || n.course == course
                case .sorting: return true
                case .learn: return false
                }
            }.prefix(5).map { $0.job }
            guard !jobs.isEmpty else {
                self.chats[m, default: []].append(Message(fromAgent: true, text: "Nothing for the team to do for \(scope) right now: what has happened is written up, the briefs are filled and nothing is waiting in Unsorted.\n\n" + self.composeBrief()))
                return
            }
            self.log(m, "Getting Oscar ready for \(scope): \(jobs.count) job\(jobs.count == 1 ? "" : "s")")
            self.chats[m, default: []].append(Message(fromAgent: true, text: "**Getting you ready for \(scope).** \(jobs.count) job\(jobs.count == 1 ? "" : "s"), one after another:\n" + jobs.enumerated().map { "\($0.offset + 1). \($0.element.label)" }.joined(separator: "\n")))
            var lines: [String] = []
            for job in jobs {
                if Task.isCancelled { lines.append("Stopped before the rest."); break }
                await self.manualJob(job)
                let key: String
                switch job {
                case .work(_, _, let k, _), .sorting(_, let k), .learn(_, _, let k): key = k
                }
                guard let item = self.inbox.last(where: { $0.key == key }) else { lines.append("\(job.label): skipped"); continue }
                let name = Agent.role(item.agent).name
                switch item.state {
                case .done: lines.append("\(name): \(item.title): done (\(item.verdict ?? "checked"))")
                case .rejected: lines.append("\(name): \(item.title): put back (\(self.clipped(item.verdict ?? "", 120)))")
                case .dismissed: lines.append("\(name): \(item.title): stopped")
                default: lines.append("\(name): \(item.title): didn’t finish (\(self.clipped(item.result ?? "", 120)))")
                }
            }
            self.chats[m, default: []].append(Message(fromAgent: true, text: "**Ready.**\n" + lines.map { "- " + $0 }.joined(separator: "\n") + "\n\nEverything is in the Activity Log, and each job has an Undo."))
        }
    }

    /// One line for the morning brief: what the team has waiting, and whether it is starting on it.
    func briefTeamLine() -> String? {
        let jobs = scan(allowDeep: false)
        guard !jobs.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for j in jobs { counts[Agent.role(j.job.agent).name, default: 0] += 1 }
        let list = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let state = blockedReason().map { "On hold (\($0.lowercased())). Say “get me ready” to run them anyway." } ?? "Starting now, one at a time; each is checked and has an Undo."
        return "**Waiting on the team:** \(jobs.count) job\(jobs.count == 1 ? "" : "s") (\(list)). \(state)"
    }
}
