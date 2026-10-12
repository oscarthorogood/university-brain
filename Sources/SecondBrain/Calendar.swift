import Foundation

/// Does what Obsidian's Calendar Importer does, without Obsidian: reads the plugin's feeds (URLs stay in its
/// data.json, never copied or logged) and rewrites `## My Calendar Events` in Agents/Helper Agents/Planner/Calendar Sync.md.
enum CalendarSync {
    struct Event: Equatable { let title: String, start: Date, end: Date, allDay: Bool, location: String, color: String }
    static let file = "Agents/Helper Agents/Planner/Calendar Sync.md"
    static let heading = "## My Calendar Events", completed = "## Completed Calendar Tasks"
    static let london = TimeZone(identifier: "Europe/London")!

    // MARK: ICS parsing
    static func unfold(_ ics: String) -> [String] {
        var out: [String] = []
        for l in ics.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if (l.hasPrefix(" ") || l.hasPrefix("\t")), !out.isEmpty { out[out.count - 1] += l.dropFirst() } else { out.append(String(l)) }
        }
        return out
    }
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "&", with: "&amp;")
    }
    /// `DTSTART;TZID=GMT Standard Time:20251001T121000` → (date, allDay). Windows zone names are treated as London.
    static func parseDate(_ key: String, _ value: String) -> (Date, Bool)? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        if key.contains("VALUE=DATE") && !key.contains("DATE-TIME") || value.count == 8 {
            f.timeZone = london; f.dateFormat = "yyyyMMdd"; return f.date(from: value).map { ($0, true) }
        }
        let utc = value.hasSuffix("Z")
        // `.first`, not `[0]`: a feed line ending in a bare `TZID=` would otherwise crash the app
        let tz = key.contains("TZID=") ? key.components(separatedBy: "TZID=").last?.split(separator: ";").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) } : nil   // some feeds quote the zone
        f.timeZone = utc ? .gmt : (tz.flatMap { TimeZone(identifier: $0) } ?? london)
        f.dateFormat = utc ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return f.date(from: value).map { ($0, false) }
    }

    /// Events (with simple RRULE expansion: DAILY/WEEKLY(+BYDAY)/MONTHLY, INTERVAL, COUNT, UNTIL, EXDATE) inside `window`.
    static func events(_ ics: String, color: String, window: Range<Date>) -> [Event] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = london
        var out: [Event] = []
        var cur: [String: (String, String)]? = nil, exdates: [Date] = []
        // A moved or cancelled single class of a repeating series arrives as its own VEVENT with a RECURRENCE-ID. The series must skip that slot, or the
        // class shows twice (once where it was, once where it went) and a cancelled one stays on the list.
        var replaced: [String: [Date]] = [:]
        var found: [(props: [String: (String, String)], skip: [Date])] = []
        for line in unfold(ics) {
            if line == "BEGIN:VEVENT" { cur = [:]; exdates = []; continue }
            if line == "END:VEVENT", let p = cur {
                cur = nil
                if let r = p["RECURRENCE-ID"], let uid = p["UID"]?.1, let was = parseDate(r.0, r.1)?.0 { replaced[uid, default: []].append(was) }
                found.append((p, exdates))
                continue
            }
            guard cur != nil, let c = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<c]), val = String(line[line.index(after: c)...])
            guard let name = key.split(separator: ";").first.map(String.init) else { continue }   // a malformed line starting with ":" has no name
            if name == "EXDATE" { for v in val.split(separator: ",") { if let d = parseDate(key, String(v))?.0 { exdates.append(d) } } }
            else { cur?[name] = (key, val) }
        }
        for (p, exdates) in found {
            guard let s = p["DTSTART"], let (start, allDay) = parseDate(s.0, s.1), p["STATUS"]?.1 != "CANCELLED" else { continue }
            let end = p["DTEND"].flatMap { parseDate($0.0, $0.1)?.0 } ?? start
            let dur = end.timeIntervalSince(start)
            var starts = [start]
            if let r = p["RRULE"]?.1 { starts = expand(start, rule: r, window: window, cal: cal) }
            let skipped = exdates + (p["RECURRENCE-ID"] == nil ? p["UID"].flatMap { replaced[$0.1] } ?? [] : [])
            for st in starts where window.contains(st) && !skipped.contains(st) {
                out.append(Event(title: unescape(p["SUMMARY"]?.1 ?? "Untitled"), start: st, end: st.addingTimeInterval(dur), allDay: allDay,
                                 location: unescape(p["LOCATION"]?.1 ?? ""), color: color))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func expand(_ start: Date, rule: String, window: Range<Date>, cal: Calendar) -> [Date] {
        let r = Dictionary(rule.split(separator: ";").compactMap { p -> (String, String)? in
            let kv = p.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil }, uniquingKeysWith: { a, _ in a })
        let interval = max(Int(r["INTERVAL"] ?? "") ?? 1, 1), count = Int(r["COUNT"] ?? "") ?? .max   // INTERVAL=0 would repeat the first date 2000 times
        let until = r["UNTIL"].flatMap { parseDate("", $0.count == 8 ? $0 + "T235959" : $0)?.0 } ?? window.upperBound
        let limit = min(until, window.upperBound)
        let codes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let days = (r["BYDAY"] ?? "").split(separator: ",").compactMap { codes[String($0.suffix(2))] }
        var out: [Date] = [], n = 0, step = 0
        while n < count && step < 2000 {
            var cands: [Date]
            switch r["FREQ"] {
            case "DAILY": cands = [cal.date(byAdding: .day, value: step * interval, to: start)].compactMap { $0 }
            case "WEEKLY":
                guard let wk = cal.date(byAdding: .weekOfYear, value: step * interval, to: start) else { return out }
                let wd = cal.component(.weekday, from: wk)
                cands = (days.isEmpty ? [wd] : days.sorted()).compactMap { cal.date(byAdding: .day, value: $0 - wd, to: wk) }.filter { $0 >= start }
            case "MONTHLY": cands = [cal.date(byAdding: .month, value: step * interval, to: start)].compactMap { $0 }
            default: return [start]   // ponytail: YEARLY/other rules fall back to the first occurrence
            }
            if !cands.isEmpty, cands.allSatisfy({ $0 > limit }) { break }   // none left this week (before the start) is not the end of the series
            for c in cands where c <= limit && n < count { out.append(c); n += 1 }
            step += 1
        }
        return out
    }

    // MARK: Markdown
    static func line(_ e: Event) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = london
        f.dateFormat = "EEEE"; let weekday = f.string(from: e.start)
        f.dateFormat = "HH:mm"; let a = f.string(from: e.start), b = f.string(from: e.end)
        let time = e.allDay ? "" : " - " + (e.end.timeIntervalSince(e.start) <= 60 ? a : "\(a)-\(b)")
        f.dateFormat = "yyyy-MM-dd"
        return "- [ ] <span class=\"calendar-importer-swatch\" style=\"color:\(e.color)\">■</span> \(e.title) - \(weekday)\(time)\(e.location.isEmpty ? "" : " - " + e.location) 📅 \(f.string(from: e.start))"
    }

    /// Replaces the `## My Calendar Events` section. Ticked lines move to Completed; events already ticked are not re-added.
    static func merge(_ doc: String, events: [Event]) -> String {
        var lines = doc.components(separatedBy: "\n")
        guard let h = lines.firstIndex(of: heading) else { return doc }
        let end = lines[(h + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
        let ticked = lines[(h + 1)..<end].filter { $0.hasPrefix("- [x]") }
        let known = (lines[end...] + ticked).filter { $0.hasPrefix("- [x]") }
        let fresh = events.map(line).filter { l in !known.contains { $0.dropFirst(5) == l.dropFirst(5) } }
        lines.replaceSubrange((h + 1)..<end, with: [""] + fresh + [""])
        if !ticked.isEmpty {
            // a note without the Completed heading would otherwise lose every tick the section held
            if !lines.contains(completed) { lines += [completed, ""] }
            if let c = lines.firstIndex(of: completed) { lines.insert(contentsOf: ticked, at: c + 1) }
        }
        return lines.joined(separator: "\n")
    }

    /// Fetches every enabled feed in Settings → Sync and rewrites the note. Returns a one-line result.
    static func sync(root: URL = Vault.root) async -> String {
        let cfg = SyncConfig.load(root: root)
        let feeds = cfg.feeds.filter(\.enabled)
        guard !feeds.isEmpty else { return "No calendars to sync. Add one in Settings → Sync." }
        let now = Date.now, window = now.addingTimeInterval(-86400 * Double(cfg.pastDays))..<now.addingTimeInterval(86400 * Double(cfg.futureDays))
        var all: [Event] = [], failed = 0
        for feed in feeds {
            // A feed that doesn't answer keeps its last good copy (up to a week old) instead of its events vanishing from the note until it comes back.
            let fresh = await fetch(feed.url)
            if let fresh { SyncConfig.keep(fresh, for: feed) }
            if fresh == nil { failed += 1 }
            guard let ics = fresh ?? SyncConfig.kept(for: feed) else { continue }
            all += events(ics, color: feed.color, window: window)
        }
        if all.isEmpty && failed > 0 { return "Couldn’t reach the calendar feeds, so the note was left as it was." }
        let path = root.appending(path: file)
        guard let doc = try? String(contentsOf: path, encoding: .utf8) else { return "\(file) is missing." }
        let new = merge(doc, events: all)
        if new != doc { do { try Vault.write(new, to: path, root: root) } catch { return "Couldn’t write \(file): \(error.localizedDescription)" } }
        let made = makeNotes(root: root)
        return "Synced \(all.count) calendar item\(all.count == 1 ? "" : "s")" + (made.isEmpty ? "" : " · added \(made.count) note\(made.count == 1 ? "" : "s")") + (failed > 0 ? "; \(failed) feed\(failed == 1 ? "" : "s") unreachable" : "")
    }

    /// The feed's text if it is a calendar. `webcal://` is the same address over https.
    static func fetch(_ address: String) async -> String? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "webcal://", with: "https://")
        guard let url = URL(string: a), url.scheme?.hasPrefix("http") == true else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)   // a feed that hangs mustn't hold up the Manager's tick
        request.cachePolicy = .reloadIgnoringLocalCacheData        // a sync that was answered from the cache would show last hour's calendar
        guard let (d, r) = try? await URLSession.shared.data(for: request), (r as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        let ics = String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)   // one stray byte shouldn't make a whole calendar "unreachable"
        return ics.contains("BEGIN:VCALENDAR") ? ics : nil
    }

    /// Self-check on fixed input (called from `--check`).
    static func check() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:Strategic Management - Lecture/01
        DTSTART;TZID=GMT Standard Time:20261005T151000
        DTEND;TZID=GMT Standard Time:20261005T160000
        RRULE:FREQ=WEEKLY;COUNT=3
        LOCATION:Lecture Theatre 1B
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Essay due
        DTSTART;TZID=Europe/London:20261008T140000
        DTEND;TZID=Europe/London:20261008T140001
        END:VEVENT
        END:VCALENDAR
        """
        let w = Date(timeIntervalSince1970: 1_790_000_000)..<Date(timeIntervalSince1970: 1_800_000_000)   // Sep 2026 – Jan 2027
        let ev = events(ics, color: "#64748b", window: w)
        precondition(ev.count == 4, "rrule expansion: \(ev.map(line))")
        precondition(line(ev[0]).hasSuffix("Lecture/01 - Monday - 15:10-16:00 - Lecture Theatre 1B 📅 2026-10-05"), line(ev[0]))
        precondition(line(ev[1]).hasSuffix("Essay due - Thursday - 14:00 📅 2026-10-08"), line(ev[1]))
        let doc = "## My Calendar Events\n- [x] old\n\n## Completed Calendar Tasks\n" + line(ev[1]).replacingOccurrences(of: "[ ]", with: "[x]") + "\n"
        let m = merge(doc, events: ev)
        precondition(m.contains("\n- [x] old") && m.components(separatedBy: "Essay due").count == 2 && m.components(separatedBy: "Lecture/01").count == 4, "merge: \(m)")
        // a moved class takes its slot in the series instead of showing twice, and a cancelled one disappears
        let series = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:abc
        SUMMARY:Operations - Lecture/01
        DTSTART;TZID=Europe/London:20261005T090000
        DTEND;TZID=Europe/London:20261005T095000
        RRULE:FREQ=WEEKLY;COUNT=3
        END:VEVENT
        BEGIN:VEVENT
        UID:abc
        RECURRENCE-ID;TZID=Europe/London:20261012T090000
        SUMMARY:Operations - Lecture/01
        DTSTART;TZID=Europe/London:20261013T110000
        DTEND;TZID=Europe/London:20261013T115000
        END:VEVENT
        BEGIN:VEVENT
        UID:abc
        RECURRENCE-ID;TZID=Europe/London:20261019T090000
        STATUS:CANCELLED
        SUMMARY:Operations - Lecture/01
        DTSTART;TZID=Europe/London:20261019T090000
        DTEND;TZID=Europe/London:20261019T095000
        END:VEVENT
        END:VCALENDAR
        """
        let moved = events(series, color: "#64748b", window: w).map(line)
        precondition(moved.count == 2 && moved[0].contains("Monday - 09:00-09:50") && moved[1].contains("Tuesday - 11:00-11:50"), "moved and cancelled classes: \(moved)")
        let bare = merge("## My Calendar Events\n- [x] kept\n", events: [])
        precondition(bare.contains(completed) && bare.contains("- [x] kept"), "ticks survive a note with no Completed heading: \(bare)")
        // feeds imported from Obsidian's Calendar Importer, once
        let box = FileManager.default.temporaryDirectory.appending(path: "sb-sync-check")
        try? FileManager.default.removeItem(at: box)
        try! FileManager.default.createDirectory(at: box.appending(path: ".obsidian/plugins/calendar-importer"), withIntermediateDirectories: true)
        try! ##"{"feeds":[{"name":"Timetable","url":"https://example.com/a.ics","color":"#f59e0b","enabled":true},{"url":"https://example.com/b.ics","enabled":false}],"pastDays":14,"futureDays":45}"##
            .write(to: SyncConfig.obsidianFile(box), atomically: true, encoding: .utf8)
        var cfg = SyncConfig()
        precondition(cfg.importFromObsidian(root: box) == 2 && cfg.feeds[0].color == "#f59e0b" && !cfg.feeds[1].enabled && cfg.pastDays == 14 && cfg.futureDays == 45, "import feeds")
        precondition(cfg.importFromObsidian(root: box) == 0 && cfg.feeds.count == 2, "import is not repeated")
        precondition((try? JSONDecoder().decode(SyncConfig.self, from: JSONEncoder().encode(cfg))) == cfg, "settings round trip")
        print("calendar sync ok: recurrence, formatting, ticked items kept")
    }
}

/// What to sync and how often. Calendar addresses are private, so this lives in Application Support (owner-only), not in the vault.
struct SyncConfig: Codable, Equatable {
    struct Feed: Codable, Identifiable, Equatable {
        var id = UUID(); var name: String; var url: String; var color = "#64748b"; var enabled = true
    }
    var feeds: [Feed] = []
    var pastDays = 30, futureDays = 30
    var everyMinutes = 60          // 0: only when you press Sync Now
    static let colors = ["#64748b", "#f59e0b", "#f43f5e", "#10b981", "#3b82f6", "#8b5cf6"]
    static let file = URL.applicationSupportDirectory.appending(path: "SecondBrain/sync.json")

    /// The saved settings; the first time, the feeds already set up in Obsidian's Calendar Importer are copied in.
    static func load(root: URL = Vault.root) -> SyncConfig {
        if let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(SyncConfig.self, from: d) { return c }
        var c = SyncConfig()
        c.importFromObsidian(root: root)
        c.save()
        return c
    }
    func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }
    /// The last good copy of each feed, private like the settings (calendar contents can be as sensitive as their links).
    private static func copy(_ feed: Feed) -> URL { file.deletingLastPathComponent().appending(path: "feeds/\(feed.id.uuidString).ics") }
    static func keep(_ ics: String, for feed: Feed) {
        let f = copy(feed)
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ics.write(to: f, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
    }
    static func kept(for feed: Feed, maxAge: TimeInterval = 7 * 86400) -> String? {
        let f = copy(feed)
        guard let made = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, Date.now.timeIntervalSince(made) < maxAge else { return nil }
        return try? String(contentsOf: f, encoding: .utf8)
    }
    static func forget(_ feed: Feed) { try? FileManager.default.removeItem(at: copy(feed)) }
    static func obsidianFile(_ root: URL) -> URL { root.appending(path: ".obsidian/plugins/calendar-importer/data.json") }
    var canImport: Bool { FileManager.default.fileExists(atPath: Self.obsidianFile(Vault.root).path) }

    /// Adds feeds from Calendar Importer's settings that aren't here yet. Returns how many were added.
    @discardableResult mutating func importFromObsidian(root: URL = Vault.root) -> Int {
        struct Plugin: Decodable { struct F: Decodable { let name: String?; let url: String; let color: String?; let enabled: Bool? }; let feeds: [F]; let pastDays: Int?; let futureDays: Int? }
        guard let d = try? Data(contentsOf: Self.obsidianFile(root)), let p = try? JSONDecoder().decode(Plugin.self, from: d) else { return 0 }
        let new = p.feeds.filter { f in !feeds.contains { $0.url == f.url } }
        feeds += new.map { Feed(name: $0.name ?? "Calendar", url: $0.url, color: $0.color ?? "#64748b", enabled: $0.enabled ?? true) }
        if feeds.count == new.count { pastDays = p.pastDays ?? pastDays; futureDays = p.futureDays ?? futureDays }
        return new.count
    }
}
