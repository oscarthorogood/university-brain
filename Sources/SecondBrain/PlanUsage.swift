import Foundation

/// How much of the Claude plan is used, from the rate-limit events Claude Code prints with every run (five-hour and weekly windows).
/// Every agent run updates it; the Manager asks with a tiny haiku call when the figures are old.
enum PlanUsage {
    struct Window: Codable, Equatable { var used: Double; var resets: Date }   // used: 0...1
    struct Snapshot: Codable, Equatable {
        var five: Window?
        var week: Window?
        var at: Date
        /// A window that has reset since is empty again.
        func used(_ w: Window?) -> Double? { w.map { $0.resets < .now ? 0 : min(max($0.used, 0), 1) } }
    }
    private static let key = "planUsage", lock = NSLock()
    nonisolated(unsafe) private static var cache: Snapshot? = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    static var current: Snapshot? { lock.lock(); defer { lock.unlock() }; return cache }
    static var stale: Bool { current.map { $0.at < .now.addingTimeInterval(-20 * 60) } ?? true }

    /// A `rate_limit_event` line from `--output-format stream-json`.
    static func record(_ event: [String: Any]) {
        guard let info = event["rate_limit_info"] as? [String: Any], let w = info["unifiedWindows"] as? [String: Any] else { return }
        func window(_ k: String) -> Window? {
            guard let d = w[k] as? [String: Any], let u = d["utilization"] as? Double, let r = d["resetsAt"] as? Double else { return nil }
            return Window(used: u, resets: Date(timeIntervalSince1970: r))
        }
        let snap = Snapshot(five: window("five_hour"), week: window("seven_day"), at: .now)
        lock.lock(); cache = snap; lock.unlock()
        UserDefaults.standard.set(try? JSONEncoder().encode(snap), forKey: key)
    }

    /// One tiny call, only to read the figures.
    static func refresh() async { _ = await Agent.run("Reply with the single word ok.", system: "Reply with one word.", session: nil, canEdit: false, root: Vault.root, tier: .quick) }

    /// "1h 20m", "3d 4h"
    static func left(until d: Date) -> String {
        let m = max(Int(d.timeIntervalSinceNow / 60), 0)
        return m >= 1440 ? "\(m / 1440)d \(m % 1440 / 60)h" : m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    static var summary: String {
        guard let s = current else { return "Claude usage: not read yet. Press to check." }
        func part(_ n: String, _ w: Window?) -> String? { s.used(w).map { "\(Int(($0 * 100).rounded()))% of the \(n) (resets in \(left(until: w!.resets)))" } }
        return "Claude plan: " + [part("5-hour window", s.five), part("week", s.week)].compactMap { $0 }.joined(separator: " · ") + ". Press to refresh."
    }
}
