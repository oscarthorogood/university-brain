import EventKit
import Foundation

/// Two-way sync between the vault's task notes and one list in Apple Reminders, through EventKit: it all happens on this Mac, and iCloud carries
/// the Reminders list to the phone.
/// Notes → Reminders: every task note (classes, tutorials, essays, projects, assignments) becomes a reminder with its due date, done or not.
/// Reminders → notes: ticking a reminder sets the note to Done (unticking sets it back to Not started), a changed due date goes into a note that
/// has a `due:` line, and a new reminder in the list becomes a note in Unsorted for the Sorter to file. A note's text and title never change from Reminders.
/// Deletes never sync, either way. If both sides changed the same task since the last sync the note wins.
/// What each side looked like at the last sync is kept in Application Support (`reminders.json`), so the sync can tell who changed.

/// The parts that need no EventKit, so `--check` can test them.
enum ReminderKeys {
    /// A due date as one comparable string: "2026-10-20" for a day, "2026-10-20 15:10" when it has a time.
    static func due(_ c: DateComponents?) -> String {
        guard let c, let y = c.year, let m = c.month, let d = c.day else { return "" }
        let day = String(format: "%04d-%02d-%02d", y, m, d)
        if let h = c.hour, let mi = c.minute, h != 0 || mi != 0 { return day + String(format: " %02d:%02d", h, mi) }
        return day
    }
    static func due(_ date: Date?) -> String {
        guard let date else { return "" }
        return due(Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date))
    }
    /// The other way: a key (or a note's `2026-10-20T15:10`) back to date components. Nil for an empty or unreadable one.
    static func components(_ key: String) -> DateComponents? {
        let parts = key.split(whereSeparator: { $0 == " " || $0 == "T" })
        guard let day = parts.first else { return nil }
        let d = day.split(separator: "-").compactMap { Int($0) }
        guard d.count == 3 else { return nil }
        var c = DateComponents(); c.year = d[0]; c.month = d[1]; c.day = d[2]
        if parts.count > 1 { let t = parts[1].split(separator: ":").compactMap { Int($0) }; if t.count >= 2 { c.hour = t[0]; c.minute = t[1] } }
        return c
    }
    /// A title to compare: lower case, one space between words.
    static func normal(_ s: String) -> String { s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    static func check() {
        precondition(due(DateComponents(year: 2026, month: 10, day: 20)) == "2026-10-20", "reminders: a day")
        precondition(due(DateComponents(year: 2026, month: 10, day: 20, hour: 15, minute: 10)) == "2026-10-20 15:10", "reminders: a time")
        precondition(due(DateComponents(year: 2026, month: 10, day: 20, hour: 0, minute: 0)) == "2026-10-20", "reminders: midnight is a whole day")
        precondition(due(nil as DateComponents?) == "" && due(nil as Date?) == "", "reminders: no date")
        let t = components("2026-10-20 15:10"), u = components("2026-10-20T15:10"), v = components("2026-10-20")
        precondition(t?.hour == 15 && t?.minute == 10 && u?.hour == 15 && v?.day == 20 && v?.hour == nil && components("") == nil && components("soon") == nil, "reminders: components")
        precondition(due(components("2026-10-20 15:10")) == "2026-10-20 15:10", "reminders: round trip")
        precondition(normal("  Essay   Outline ") == "essay outline", "reminders: titles compare without case or extra spaces")
        print("reminders keys ok")
    }
}

/// What both sides held for one note at the last sync.
struct ReminderLink: Codable {
    var rid: String        // the reminder's identifier
    var due: String
    var done: Bool
    var gone = false       // the reminder was deleted in Reminders: left alone from then on
}
struct ReminderState: Codable {
    var notes: [String: ReminderLink] = [:]   // note path (vault-relative, no .md) → link
    var imported: [String: String] = [:]      // reminder id → title, for reminders that were turned into Unsorted notes
    static var file: URL { Support.dir.appending(path: "reminders.json") }
    static func load() -> ReminderState { (try? JSONDecoder().decode(ReminderState.self, from: Data(contentsOf: file))) ?? ReminderState() }
    func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }
}
/// A reminder as read from the list, in a form that can leave EventKit's queue.
struct ReminderItem: Sendable { let id: String, title: String, due: String, done: Bool, notes: String }

@MainActor enum RemindersSync {
    static let taskFolders: Set<String> = ["Lectures", "Tutorials", "Essays", "Projects", "TaskNotes/Tasks"]
    /// Notes that carry a `due:` line, which a changed due date in Reminders may rewrite. A class's date comes from the calendar sync instead.
    static let dueFolders: Set<String> = ["Essays", "Projects", "TaskNotes/Tasks"]
    static let defaultList = "University"
    static var on: Bool { UserDefaults.standard.bool(forKey: "remindersOn") }
    static var listName: String {
        let n = (UserDefaults.standard.string(forKey: "remindersList") ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? defaultList : n
    }
    private static let store = EKEventStore()

    /// The list, made if it isn't there yet.
    private static func calendar(named name: String) -> EKCalendar? {
        if let c = store.calendars(for: .reminder).first(where: { $0.title == name && $0.allowsContentModifications }) { return c }
        let c = EKCalendar(for: .reminder, eventStore: store)
        c.title = name
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else { return nil }
        c.source = source
        do { try store.saveCalendar(c, commit: true) } catch { return nil }
        return c
    }

    private static func fetch(_ cal: EKCalendar) async -> [ReminderItem] {
        let predicate = store.predicateForReminders(in: [cal])
        return await withCheckedContinuation { (cont: CheckedContinuation<[ReminderItem], Never>) in
            // EventKit answers on its own queue. A closure made here would count as main-actor code and the runtime stops the app when it is called from another queue
            // (that was the crash), so it is marked `@Sendable` and touches nothing of this type.
            store.fetchReminders(matching: predicate) { @Sendable list in
                cont.resume(returning: (list ?? []).map {
                    ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: ReminderKeys.due($0.dueDateComponents), done: $0.isCompleted, notes: $0.notes ?? "")
                })
            }
        }
    }

    /// One pass, both ways. `notes` is the vault as the app last loaded it.
    static func sync(_ notes: [Note]) async -> (text: String, changed: Bool) {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: break
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            guard granted else { return ("Reminders access wasn’t given. Allow University Brain in System Settings → Privacy & Security → Reminders.", false) }
        default:
            return ("Reminders access is off. Allow University Brain in System Settings → Privacy & Security → Reminders.", false)
        }
        let name = listName
        guard let cal = calendar(named: name) else { return ("Couldn’t find or make a “\(name)” list in Reminders.", false) }
        let items = await fetch(cal)
        var st = ReminderState.load()
        var pool = items.filter { item in !st.notes.values.contains { $0.rid == item.id } }   // not linked to a note yet: adopt it for a note with the same title, or import it
        var fresh: [(path: String, ek: EKReminder, due: String, done: Bool)] = []
        var made = 0, pushed = 0, pulled = 0, imported = 0
        var problems: [String] = []

        for n in notes where taskFolders.contains(n.folder) {
            let nDue = ReminderKeys.due(n.when)
            if var link = st.notes[n.path] {
                guard !link.gone else { continue }
                guard let ek = store.calendarItem(withIdentifier: link.rid) as? EKReminder else { link.gone = true; st.notes[n.path] = link; continue }   // deleted in Reminders: left alone
                let rDue = ReminderKeys.due(ek.dueDateComponents), rDone = ek.isCompleted
                let noteChanged = nDue != link.due || n.done != link.done
                let remChanged = rDue != link.due || rDone != link.done
                var doneNow = n.done, dueNow = nDue
                if remChanged && !noteChanged {   // only Reminders changed: bring the note along
                    do {
                        if rDone != n.done { try Vault.setStatus(n, to: rDone ? "Done" : "Not started"); doneNow = rDone; pulled += 1 }
                        if rDue != nDue, !rDue.isEmpty, dueFolders.contains(n.folder) {
                            let text = try String(contentsOf: n.id, encoding: .utf8)
                            if Vault.split(text)?.head.contains(where: { $0.hasPrefix("due:") }) == true {
                                try Vault.write(Vault.setField(text, "due", to: rDue.replacingOccurrences(of: " ", with: "T")), to: n.id)
                                dueNow = rDue; pulled += 1
                            }
                        }
                    } catch { problems.append("\(n.display): \(error.localizedDescription)") }
                }
                // now the reminder follows the note: a note change, or a Reminders edit the note can't take (a class date, a cleared due date)
                var dirty = false
                if ek.title != n.display { ek.title = n.display; dirty = true }
                if rDue != dueNow { ek.dueDateComponents = ReminderKeys.components(dueNow); dirty = true }
                if rDone != doneNow { ek.isCompleted = doneNow; dirty = true }
                if dirty {
                    do { try store.save(ek, commit: false); pushed += 1 } catch { problems.append("\(n.display): \(error.localizedDescription)") }
                }
                link.due = dueNow; link.done = doneNow
                st.notes[n.path] = link
            } else {
                let key = ReminderKeys.normal(n.display)
                let ek: EKReminder
                if let i = pool.firstIndex(where: { ReminderKeys.normal($0.title) == key }), let existing = store.calendarItem(withIdentifier: pool[i].id) as? EKReminder {
                    ek = existing; pool.remove(at: i)   // a reminder with this title is already there: it becomes this note's
                } else {
                    ek = EKReminder(eventStore: store); ek.calendar = cal; made += 1
                }
                ek.title = n.display
                ek.dueDateComponents = ReminderKeys.components(nDue)
                ek.isCompleted = n.done
                ek.url = Vault.obsidianURL(n)
                if (ek.notes ?? "").isEmpty { ek.notes = "From University Brain: \(n.path)" }
                do { try store.save(ek, commit: false); fresh.append((n.path, ek, nDue, n.done)) } catch { problems.append("\(n.display): \(error.localizedDescription)") }
            }
        }

        // reminders added in Reminders (and not ticked) land in Unsorted, where the Sorter files them
        for r in pool where !r.done && !r.title.isEmpty && st.imported[r.id] == nil {
            if importNote(r) { st.imported[r.id] = r.title; imported += 1 } else { problems.append("couldn’t add “\(r.title)” to Unsorted") }
        }

        do { try store.commit() } catch {
            store.reset()   // nothing is recorded, so the next pass starts from what both sides really hold
            return ("Couldn’t save to Reminders: \(error.localizedDescription)", false)
        }
        for f in fresh { st.notes[f.path] = ReminderLink(rid: f.ek.calendarItemIdentifier, due: f.due, done: f.done) }   // identifiers settle once saved
        st.save()

        pushed += fresh.count
        var parts: [String] = []
        if made > 0 { parts.append("\(made) new in Reminders") }
        if pushed - made > 0 { parts.append("\(pushed - made) updated in Reminders") }
        if pulled > 0 { parts.append("\(pulled) change\(pulled == 1 ? "" : "s") brought into notes") }
        if imported > 0 { parts.append("\(imported) new reminder\(imported == 1 ? "" : "s") added to Unsorted") }
        var text = parts.isEmpty ? "Reminders: everything matches." : "Reminders: " + parts.joined(separator: ", ") + "."
        if !problems.isEmpty { text += " \(problems.count) problem\(problems.count == 1 ? "" : "s"), first: \(problems[0])" }
        return (text, pushed + pulled + imported > 0)
    }

    /// A reminder becomes a note in Unsorted, named by its title. Its first line is the title, which is how Unsorted lists it.
    private static func importNote(_ r: ReminderItem) -> Bool {
        let dir = Vault.root.appending(path: "Unsorted")
        let clean = String(r.title.map { "/:\\".contains($0) ? "-" : $0 }.prefix(60))
        let stamp = Date.now.formatted(.iso8601.year().month().day()) + " " + Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).replacingOccurrences(of: ":", with: "")
        let file = dir.appending(path: "Reminder - \(clean) - \(stamp).md")
        var body = "\(r.title)\n\nAdded from Apple Reminders on \(Date.now.formatted(date: .abbreviated, time: .omitted))."
        if !r.due.isEmpty { body += " Due \(r.due)." }
        if !r.notes.isEmpty { body += "\n\n" + r.notes }
        guard !FileManager.default.fileExists(atPath: file.path) else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try body.write(to: file, atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }
}

extension Store {
    /// Runs one sync and remembers how it went (Settings → Sync shows it).
    @discardableResult func syncReminders() async -> (text: String, changed: Bool) {
        guard !remindersSyncing else { return ("Already syncing.", false) }
        remindersSyncing = true; defer { remindersSyncing = false }
        let r = await RemindersSync.sync(notes)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastRemindersSync")
        UserDefaults.standard.set(r.text, forKey: "lastRemindersResult")
        if r.changed { reload() }
        return r
    }
}
