import Foundation

// When Oscar asks an agent to change his notes it may (see `Agent.editRules`), the app keeps the old versions, finds what changed, puts back anything that lost its
// frontmatter and logs one Undo. An agent that can't do a request says `DELEGATE:`, and the Manager picks another; when no other agent is left the Manager does it itself.

extension Store {
    /// A snapshot of every note, so whatever an agent edits can be put back (the notes are the only thing a chat edit can reach).
    func snapshotNotes(_ root: URL) async {
        let urls = notes.map(\.id)
        await Task.detached(priority: .utility) { for u in urls { try? Vault.snapshot(u, root: root) } }.value
    }

    /// What an agent changed since `started`: logs it with an Undo, and puts back any existing note that lost its frontmatter. Returns a line for the chat, or nil if nothing changed.
    func recordEdits(since started: Date, existing: Set<String>, by code: String, root: URL) async -> String? {
        let touched = await Review.touchedInBackground(since: started, root: root).filter { $0.hasSuffix(".md") && !$0.hasPrefix("Agents/") && !$0.hasPrefix("Templates/") }
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

    /// An agent said it couldn't do the request (`DELEGATE:`): the Manager picks another, up to three times; when no other agent fits, the Manager does it itself.
    func passOn(_ text: String, tried: Set<String>, why: String, in chat: String, tier: Manager.Tier?) async {
        var tried = tried, why = why
        thinking.insert(chat)
        defer { thinking.remove(chat) }
        for _ in 0..<3 {
            guard !Task.isCancelled else { return }
            let route = await Manager.decide(text, previous: nil, excluding: tried)
            let from = tried.map { Agent.role($0).name }.sorted().joined(separator: ", ")
            chats[chat, default: []].append(Message(fromAgent: true, text: "→ \(from) can’t do this (\(why.prefix(120))) · **\(Agent.role(route.agent).name)** · \(route.reason)"))
            log(Agent.manager.id, "Passed “\(text.prefix(50))” on to \(Agent.role(route.agent).name): \(from) couldn’t (\(why.prefix(80)))")
            let general = route.agent == Agent.manager.id
            let reply = await converse(route.agent, shown: text, prompt: text, tier: tier ?? route.tier, mirror: chat == route.agent ? nil : chat, echo: route.agent != chat && !general)
            guard let next = reply.delegation else { return }
            if general { break }
            tried.insert(route.agent); why = next
        }
        chats[chat, default: []].append(Message(fromAgent: true, text: "Nothing could do this: " + why.prefix(160)))
    }
}
