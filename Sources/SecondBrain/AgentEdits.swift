import Foundation

// When Oscar asks the agent to change his notes (or anything in the vault) it may (see `Agent.editRules`), the app keeps the old versions, finds what changed, puts back anything that lost its
// frontmatter and logs one Undo. A kind of work that can't do a request says `DELEGATE:`, and the app tries another; when none is left it is handled as general help.

extension Store {
    /// A snapshot of every Markdown file an edit can reach (the notes, and `Agents/` and `Templates/` too), so whatever the agent changes can be put back.
    /// Returns their vault paths, so a file that already existed is never mistaken for one the agent created.
    func snapshotNotes(_ root: URL) async -> Set<String> {
        let urls = notes.map(\.id)
        return await Task.detached(priority: .utility) {
            var all = Set(urls)
            for top in ["Agents", "Templates"] {
                guard let walk = FileManager.default.enumerator(at: root.appending(path: top), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for case let u as URL in walk where u.pathExtension == "md" { all.insert(u) }
            }
            for u in all { try? Vault.snapshot(u, root: root) }
            return Set(all.map { Vault.rel($0) })
        }.value
    }

    /// What an agent changed since `started`: logs it with an Undo, and puts back any existing note that lost its frontmatter. Returns a line for the chat, or nil if nothing changed.
    func recordEdits(since started: Date, existing: Set<String>, by code: String, root: URL) async -> String? {
        let touched = await Review.touchedInBackground(since: started, root: root).filter { $0.hasSuffix(".md") }
        guard !touched.isEmpty else { return nil }
        var changed: [String] = [], created: [String] = [], restored: [String] = [], snaps: [String: String] = [:]
        for rel in touched {
            let url = root.appending(path: rel)
            guard existing.contains(rel) else { created.append(rel); continue }
            guard let snap = Vault.history(url, root: root).first else { changed.append(rel); continue }
            if let old = try? String(contentsOf: snap.url, encoding: .utf8), let now = try? String(contentsOf: url, encoding: .utf8),
               Vault.split(old) != nil, Vault.split(now) == nil {   // the edit took the frontmatter off: that is never what was asked
                try? Vault.write(old, to: url, root: root); restored.append((rel as NSString).lastPathComponent); continue
            }
            changed.append(rel); snaps[rel] = snap.url.lastPathComponent
        }
        let kept = changed.count + created.count
        guard kept > 0 else { return restored.isEmpty ? nil : "I put back \(restored.joined(separator: ", ")): the edit had removed its frontmatter." }
        var item = InboxItem(kind: .work, agent: code, title: "Edited \(kept) note\(kept == 1 ? "" : "s") at your request", state: .done, key: "edit:\(UUID().uuidString)")
        item.undo = InboxItem.Undo(restore: changed, created: created, snapshots: snaps); item.verdict = "Checked: frontmatter intact"
        inbox.append(item); saveInbox()
        log(code, "Edited \(kept) note\(kept == 1 ? "" : "s") at your request.", undo: item.id)
        reload()
        let names = (changed + created).prefix(5).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        return "Changed \(kept) note\(kept == 1 ? "" : "s"): " + names.joined(separator: ", ") + (kept > 5 ? " and \(kept - 5) more" : "") + "."
            + (restored.isEmpty ? "" : " I put back \(restored.joined(separator: ", ")), because the edit had removed its frontmatter.") + " Undo is in the Activity Log."
    }

    /// `MOVE: a -> b` lines in the general agent's reply (renames and moves, which it can't do itself): the app copies, checks, and keeps the original in `.trash`.
    func performMoves(in reply: String, root: URL) -> String {
        let moves = Vault.moves(in: reply)
        guard !moves.isEmpty else { return "" }
        var done: [[String]] = [], failed: [String] = []
        for m in moves {
            do { try Vault.perform(m, in: root); done.append([m.from, m.to]) } catch { failed.append(error.localizedDescription) }
        }
        if !done.isEmpty {
            var item = InboxItem(kind: .filing, agent: Agent.manager.id, title: "Moved \(done.count) file\(done.count == 1 ? "" : "s") at your request", state: .done, key: "move:\(UUID().uuidString)")
            item.undo = InboxItem.Undo(moves: done); item.verdict = "Originals kept in .trash"
            inbox.append(item); saveInbox()
            log(Agent.manager.id, "Moved \(done.count) file\(done.count == 1 ? "" : "s") at your request.", undo: item.id)
            reload()
        }
        return "\n\nMoved \(done.count) of \(moves.count) file\(moves.count == 1 ? "" : "s")." + (failed.isEmpty ? "" : " " + failed.prefix(2).joined(separator: " "))
    }

    /// The work said it couldn't do the request as that kind of work (`DELEGATE:`): the app tries another kind, up to three times; when none fits, it is handled as general help.
    /// The chat is already marked busy by whoever is calling.
    func passOn(_ text: String, tried: Set<String>, why: String, course: String?, tier: Manager.Tier?) async {
        var tried = tried, why = why
        let m = Agent.manager.id
        for _ in 0..<3 {
            guard !Task.isCancelled else { return }
            let route = await Manager.decide(text, previous: nil, excluding: tried)
            let from = tried.map { Agent.label($0) }.sorted().joined(separator: ", ")
            let general = route.agent == m
            chats[m, default: []].append(Message(fromAgent: true, text: "→ not \(from) work (\(why.prefix(120))) · **\(Agent.label(route.agent))** · \(route.reason)"))
            log(m, "Tried “\(text.prefix(50))” as \(Agent.label(route.agent)) instead: \(from) didn’t fit (\(why.prefix(80)))")
            let reply = await converse(route.agent, shown: text, prompt: text, tier: tier ?? route.tier, course: course ?? route.course, echo: false)
            guard let next = reply.delegation else { return }
            if general { break }
            tried.insert(route.agent); why = next
        }
        chats[m, default: []].append(Message(fromAgent: true, text: "I couldn’t do this: " + why.prefix(160)))
    }
}
