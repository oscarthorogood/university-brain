import SwiftUI
import IOKit.ps

/// Everything the Manager menu switches: pausing, quiet hours, the background budget, which jobs and agents are on, daily caps, and the loop breaker.
extension Store {
    /// The jobs and checks the Manager looks for, each with a switch.
    nonisolated static let jobKinds: [(id: String, title: String, group: String)] = [
        ("unsorted", "Files in Unsorted", "Jobs"), ("brief", "Blank essay or project brief", "Jobs"), ("research", "Missing outside research", "Jobs"),
        ("outline", "Essay or project with no outline", "Jobs"), ("solutions", "Worked solutions for tutorials", "Jobs"), ("writeup", "Classes to write up", "Jobs"),
        ("source", "Readings with no source", "Jobs"), ("readingnotes", "Readings a lecture needs", "Jobs"), ("examplan", "Exam revision plan", "Jobs"),
        ("revisionset", "MCQ sets", "Jobs"), ("citation", "Citations to confirm", "Jobs"), ("checkanswers", "Check your tutorial answers", "Jobs"),
        ("weekahead", "Week ahead per course", "Jobs"), ("learn", "Learn from your edits", "Jobs"), ("docsfix", "Fix docs that name missing paths", "Jobs"),
        ("vaulthealth", "Vault health", "Checks"), ("links", "Broken links", "Checks"), ("calendardrift", "Calendar drift", "Checks"),
        ("deadlines", "Deadline consistency", "Checks"), ("atrisk", "At-risk deadlines", "Checks"), ("slides", "Missing slides", "Checks"),
        ("quality", "Quality sweep", "Checks"), ("status", "Status hygiene", "Checks"),
        ("index", "Vault index counts", "Checks"), ("docs", "Docs naming missing paths", "Checks"), ("verifier", "Vault verifier", "Checks"),
    ]
    private var d: UserDefaults { .standard }

    // MARK: Switches
    func jobOn(_ id: String) -> Bool { d.object(forKey: "job-\(id)") as? Bool ?? true }
    func setJob(_ id: String, _ on: Bool) { d.set(on, forKey: "job-\(id)"); revision += 1 }
    func agentOn(_ id: String) -> Bool { d.object(forKey: "agentOn-\(id)") as? Bool ?? true }
    func setAgentOn(_ id: String, _ on: Bool) { d.set(on, forKey: "agentOn-\(id)"); revision += 1 }

    // MARK: Pausing
    var pausedUntil: Date? { (d.object(forKey: "pausedUntil") as? Date).flatMap { $0 > .now ? $0 : nil } }
    /// Pausing also ends what the Manager has running now: a job under way is stopped and put back, not left to finish.
    func pause(for seconds: TimeInterval?) { d.set(seconds.map { Date.now.addingTimeInterval($0) } ?? Date.distantFuture, forKey: "pausedUntil"); revision += 1; Agent.stopBackgroundRuns() }
    func pauseUntilTomorrow() { pause(for: Calendar.current.date(byAdding: .day, value: 1, to: today)!.addingTimeInterval(6 * 3600).timeIntervalSinceNow) }
    /// Ends the job that is running now, whoever started it, and puts back what it had changed.
    func stopCurrentJob() { Agent.stopJobs() }
    func resume() { d.removeObject(forKey: "pausedUntil"); revision += 1; scheduleAutopilot(after: 2) }

    var quietOn: Bool { d.bool(forKey: "quietOn") }
    var quietFrom: Int { d.object(forKey: "quietFrom") as? Int ?? 22 }
    var quietTo: Int { d.object(forKey: "quietTo") as? Int ?? 7 }
    func setQuiet(on: Bool? = nil, from: Int? = nil, to: Int? = nil) {
        if let on { d.set(on, forKey: "quietOn") }; if let from { d.set(from, forKey: "quietFrom") }; if let to { d.set(to, forKey: "quietTo") }
        revision += 1
    }
    var pauseOnBattery: Bool { d.object(forKey: "pauseOnBattery") as? Bool ?? false }
    func setPauseOnBattery(_ on: Bool) { d.set(on, forKey: "pauseOnBattery"); revision += 1 }

    static var onBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        return (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
    }
    /// Why the Manager isn't starting jobs right now, or nil if it is free to.
    func blockedReason() -> String? {
        if !autopilotOn { return "The Manager is switched off in Settings" }
        if let p = pausedUntil { return p == .distantFuture ? "Paused" : "Paused until " + p.formatted(date: .omitted, time: .shortened) }
        if quietOn {
            let h = Calendar.current.component(.hour, from: .now)
            if quietFrom > quietTo ? (h >= quietFrom || h < quietTo) : (h >= quietFrom && h < quietTo) { return "Quiet hours (\(quietFrom):00 to \(quietTo):00)" }
        }
        if pauseOnBattery && Store.onBattery { return "On battery" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled && pauseOnBattery { return "Low Power Mode" }
        return nil
    }

    // MARK: Budget
    /// How much of the Claude plan background work may use. The rest is left for your own use.
    var budgetPreset: String { d.string(forKey: "budgetPreset") ?? "balanced" }
    func setBudget(_ p: String) { d.set(p, forKey: "budgetPreset"); revision += 1 }
    nonisolated static let budgets: [(id: String, title: String, five: Double, week: Double, deepFive: Double, deepWeek: Double)] = [
        ("cautious", "Cautious", 0.50, 0.60, 0.30, 0.45), ("balanced", "Balanced", 0.60, 0.70, 0.40, 0.55), ("generous", "Generous", 0.75, 0.85, 0.55, 0.70),
    ]

    // MARK: Daily caps and the loop breaker
    func dailyCap(_ agent: String) -> Int { ["writer": 5, "researcher": 5, "analyst": 10, "sorter": 20][agent] ?? 30 }
    private func dayKey(_ agent: String) -> String { "jobsToday-\(agent)-" + Date.now.formatted(.iso8601.year().month().day()) }
    func jobsToday(_ agent: String) -> Int { d.integer(forKey: dayKey(agent)) }
    func spendJob(_ agent: String) { d.set(jobsToday(agent) + 1, forKey: dayKey(agent)) }
    /// Whether this agent can take another job now: switched on, under its daily cap, and not paused by the breaker.
    func agentFree(_ agent: String) -> Bool {
        agentOn(agent) && jobsToday(agent) < dailyCap(agent) && ((d.object(forKey: "breaker-\(agent)") as? Date) ?? .distantPast) < .now
    }
    /// Three failed reviews in a row pause that agent for a day.
    func recordReview(_ agent: String, passed: Bool) {
        let k = "rejects-\(agent)", n = passed ? 0 : d.integer(forKey: k) + 1
        d.set(n, forKey: k)
        if n >= 3 { d.set(Date.now.addingTimeInterval(86400), forKey: "breaker-\(agent)"); d.set(0, forKey: k); log(Agent.manager.id, "\(Agent.role(agent).name) failed my review three times in a row, so I'm pausing its jobs for a day.") }
    }
    /// The same agent isn't put on the same note again for six hours, whatever happened.
    func cooling(_ role: String, _ path: String) -> Bool { ((d.object(forKey: "cool-\(role)|\(path)") as? Date) ?? .distantPast) > .now }
    func startCooling(_ role: String, _ path: String) { d.set(Date.now.addingTimeInterval(6 * 3600), forKey: "cool-\(role)|\(path)") }
    /// A note you changed in the last five minutes, or have open, is left alone.
    func inUse(_ url: URL) -> Bool {
        if case .note(let open) = page, open == url { return true }
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return m > .now.addingTimeInterval(-300)
    }

    /// Jobs used per agent this week, for the menu.
    func usageByAgent() -> [(agent: String, today: Int, week: Int)] {
        (Agent.roles).map { r in
            let week = (0..<7).reduce(0) { acc, i in
                let day = Date.now.addingTimeInterval(Double(-i) * 86400).formatted(.iso8601.year().month().day())
                return acc + d.integer(forKey: "jobsToday-\(r.id)-\(day)")
            }
            return (r.id, jobsToday(r.id), week)
        }
    }
}
