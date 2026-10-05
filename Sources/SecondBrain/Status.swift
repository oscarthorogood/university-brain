import SwiftUI

/// The four states a task, class or assignment cycles through when you press its mark. Stored as the note's `status`.
enum TaskState: String, CaseIterable {
    case notStarted = "Not started", human = "In Progress", agent = "Agent In Progress", done = "Done"
    var next: TaskState { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    var label: String { ["Not started", "In progress (you)", "In progress (agent)", "Done"][Self.allCases.firstIndex(of: self)!] }
    var icon: String { ["circle", "circle.lefthalf.filled", "sparkles", "checkmark.circle.fill"][Self.allCases.firstIndex(of: self)!] }
    var color: Color { self == .agent ? Color(light: 0x7A56E0, dark: 0xA68CFF) : self == .notStarted ? .ink2 : .ink }
}

extension Note {
    /// Anything that isn't one of the four (a reading's "To Find", say) counts as not started until pressed.
    var state: TaskState { TaskState(rawValue: status) ?? .notStarted }
}

/// The round mark in front of a note: press it to go to the next state.
struct StatusButton: View {
    @Environment(Store.self) private var store
    let note: Note; var size: CGFloat = 14
    var body: some View {
        Button { withAnimation(.spring(duration: 0.3, bounce: 0.4)) { store.cycle(note) } } label: {
            Image(systemName: note.state.icon).font(.system(size: size)).foregroundStyle(note.state.color).contentTransition(.symbolEffect(.replace))
        }.buttonStyle(.pressScale).help("\(note.state.label). Press for \(note.state.next.label.lowercased()).").accessibilityLabel(note.state.label)
    }
}

extension Store {
    func cycle(_ n: Note) { set(n, n.state.next) }
    func set(_ n: Note, _ s: TaskState) {
        do { try Vault.setStatus(n, to: s.rawValue); reload() }
        catch { self.error = "Couldn’t update \(n.title): \(error.localizedDescription)" }
    }
}

/// While an agent has a job on a note, the note is marked "Agent In Progress"; what it was before is remembered (so it survives a relaunch) and put back when the job ends.
extension Store {
    var claims: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "agentClaims") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "agentClaims") }
    }
    func claim(_ rel: String, manual: Bool = false) {
        guard claims[rel] == nil, let n = notes.first(where: { Vault.rel($0.id) == rel }), n.state != .agent else { return }
        if manual { manualClaims.insert(rel) }
        claims[rel] = n.status
        set(n, .agent)
    }
    func release(_ rel: String?) {
        guard let rel, claims[rel] != nil else { return }
        manualClaims.remove(rel)
        if restore(rel) { reload() }
    }
    /// Puts the status back unless you changed it yourself in the meantime.
    @discardableResult private func restore(_ rel: String) -> Bool {
        guard let prev = claims[rel] else { return false }
        claims[rel] = nil
        guard let n = notes.first(where: { Vault.rel($0.id) == rel }), n.state == .agent else { return false }
        do { try Vault.setStatus(n, to: prev.isEmpty ? TaskState.notStarted.rawValue : prev); return true } catch { return false }
    }
    /// A job that no longer exists (the app was closed in the middle of it) must not leave its note marked.
    func releaseStaleClaims() {
        let live = Set(inbox.filter { [.planning, .consulting, .working, .checking].contains($0.state) }.flatMap(\.paths)).union(manualClaims)
        for rel in claims.keys where !live.contains(rel) { restore(rel) }
    }
}
