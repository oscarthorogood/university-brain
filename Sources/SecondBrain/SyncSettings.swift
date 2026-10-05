import SwiftUI
import AppKit

/// Settings → Sync: which calendars to read, how often, and how far around today.
struct SyncSettings: View {
    @Environment(Store.self) private var store
    @State private var cfg = SyncConfig.load()
    @State private var adding = false
    @State private var syncing = false
    @AppStorage("lastCalendarSync") private var last: Double = 0
    @AppStorage("lastCalendarResult") private var result = ""
    @State private var note = ""

    static let every: [(Int, String)] = [(15, "15 minutes"), (30, "30 minutes"), (60, "hour"), (180, "3 hours"), (0, "Only when I press Sync Now")]

    var body: some View {
        Form {
            LabeledContent("Calendars:") {
                VStack(alignment: .leading, spacing: 8) {
                    if cfg.feeds.isEmpty { Text("None yet. Add a calendar link to read events and deadlines from it.").foregroundStyle(.secondary) }
                    ForEach($cfg.feeds) { $feed in FeedRow(feed: $feed) { cfg.feeds.removeAll { $0.id == feed.id } } }
                    HStack {
                        Button("Add Calendar…") { adding = true }
                        if cfg.canImport { Button("Import from Obsidian") { let n = cfg.importFromObsidian(); note = n == 0 ? "Nothing new in Calendar Importer." : "Added \(n) calendar\(n == 1 ? "" : "s")." } }
                    }
                    if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                    Text("Paste the private link (ICS or webcal://) from Outlook, Google Calendar, iCloud or Learn. It stays on this Mac, outside your vault.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker("Sync every", selection: $cfg.everyMinutes) { ForEach(Self.every, id: \.0) { Text($0.1).tag($0.0) } }
                .formLabelHidden().labeled("Automatically:")
            LabeledContent("Look at:") {
                HStack(spacing: 14) {
                    Stepper("\(cfg.pastDays) days back", value: $cfg.pastDays, in: 0...365, step: 7)
                    Stepper("\(cfg.futureDays) days ahead", value: $cfg.futureDays, in: 7...365, step: 7)
                }
            }.padding(.top, 8)
            LabeledContent("Writes to:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CalendarSync.file).textSelection(.enabled)
                    Text("Only the “My Calendar Events” part is rewritten. Ticked items are kept, and the old version stays in the note’s history.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Note") { NSWorkspace.shared.open(Vault.root.appending(path: CalendarSync.file)) }
                }
            }.padding(.top, 8)
            LabeledContent("Status:") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button(syncing ? "Syncing…" : "Sync Now") { sync() }.disabled(syncing || !cfg.feeds.contains(where: \.enabled))
                        if syncing { ProgressView().controlSize(.small) }
                    }
                    Text(last == 0 ? "Not synced yet." : "\(result) · \(Date(timeIntervalSince1970: last).formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8)
        }
        .formStyle(.columns).padding(24)
        .onChange(of: cfg) { cfg.save() }
        .sheet(isPresented: $adding) { AddCalendar { cfg.feeds.append($0) } }
    }

    func sync() {
        syncing = true
        Task { _ = await store.syncCalendar(); syncing = false }
    }
}

private struct FeedRow: View {
    @Binding var feed: SyncConfig.Feed
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $feed.enabled).labelsHidden()
            Button { let i = SyncConfig.colors.firstIndex(of: feed.color) ?? 0; feed.color = SyncConfig.colors[(i + 1) % SyncConfig.colors.count] } label: {
                Circle().fill(Color(hex: feed.color)).frame(width: 13, height: 13).padding(3)
            }.buttonStyle(.plain).help("Click to change the colour").accessibilityLabel("Change colour")
            TextField("", text: $feed.name, prompt: Text("Name")).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 130)
            Text(URL(string: feed.url.replacingOccurrences(of: "webcal://", with: "https://"))?.host ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove").accessibilityLabel("Remove \(feed.name)")
        }
    }
}

private struct AddCalendar: View {
    @Environment(\.dismiss) private var dismiss
    let add: (SyncConfig.Feed) -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var color = SyncConfig.colors[0]
    @State private var status = ""
    @State private var checking = false
    var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && url.contains("://") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Calendar").font(.headline)
            TextField("Name (e.g. Timetable)", text: $name)
            TextField("Calendar link (https:// or webcal://)", text: $url)
            HStack(spacing: 8) {
                Text("Colour").foregroundStyle(.secondary)
                ForEach(SyncConfig.colors, id: \.self) { hex in
                    Button { color = hex } label: { Circle().fill(Color(hex: hex)).frame(width: 18, height: 18).overlay(Circle().stroke(Color.primary, lineWidth: color == hex ? 2 : 0)) }.buttonStyle(.plain)
                        .accessibilityLabel("Colour \((SyncConfig.colors.firstIndex(of: hex) ?? 0) + 1)").accessibilityAddTraits(color == hex ? .isSelected : [])
                }
            }
            HStack {
                Button(checking ? "Checking…" : "Test") { test() }.disabled(!valid || checking)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { add(.init(name: name.trimmingCharacters(in: .whitespaces), url: url.trimmingCharacters(in: .whitespacesAndNewlines), color: color)); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(20).frame(width: 420)
    }

    func test() {
        checking = true; status = ""
        Task {
            if let ics = await CalendarSync.fetch(url) {
                let now = Date.now
                let n = CalendarSync.events(ics, color: color, window: now.addingTimeInterval(-30 * 86400)..<now.addingTimeInterval(30 * 86400)).count
                status = "Works: \(n) event\(n == 1 ? "" : "s") in the next 30 days."
            } else { status = "Couldn’t read a calendar from that link." }
            checking = false
        }
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0x64748b
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

private extension View {
    func formLabelHidden() -> some View { self.labelsHidden() }
    func labeled(_ label: String) -> some View { LabeledContent(label) { self }.padding(.top, 8) }
}
