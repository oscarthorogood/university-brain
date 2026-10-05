import SwiftUI
import AppKit
import FoundationModels

/// Safari-style settings: a window with icon tabs, labels right-aligned beside their controls.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            SyncSettings().tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            ManagerSettings().tabItem { Label("Manager", systemImage: "person.badge.clock") }
            AgentSettings().tabItem { Label("Agents", systemImage: "person.2") }
            RulesSettings().tabItem { Label("Rules", systemImage: "doc.text") }
        }
        .buttonStyle(.glassAction(.compact))   // the same glass buttons as the rest of the app
        .frame(width: 560)
    }
}

struct GeneralSettings: View {
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @State private var path = Vault.root.path
    var body: some View {
        Form {
            LabeledContent("Vault folder:") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(path).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    HStack {
                        Button("Choose…") { choose() }
                        Button("Show in Finder") { NSWorkspace.shared.open(Vault.root) }
                    }
                    Text("A new folder takes effect the next time University Brain opens.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Collapse the sidebar to icons", isOn: $collapsed)
                .padding(.top, 8)
                .formLabel("Sidebar:")
            VStack(alignment: .leading) { ForEach(SideNav.folders, id: \.name) { NavToggle(name: $0.name, label: SideNav.label($0.name)) } }
                .padding(.top, 8)
                .formLabel("Sidebar pages:")
        }
        .formStyle(.columns).padding(24)
    }
    func choose() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.directoryURL = Vault.root
        if p.runModal() == .OK, let u = p.url { UserDefaults.standard.set(u.path, forKey: "vaultPath"); path = u.path }
    }
}

struct AgentSettings: View {
    @Environment(Store.self) private var store
    @State private var status = ""
    @State private var ok: Bool?
    @State private var testing = false
    @State private var managerOn = Manager.on
    @State private var managerMax = Manager.ceiling
    @State private var briefOn = UserDefaults.standard.object(forKey: "briefOn") as? Bool ?? true
    @State private var notifyOn = Notify.on
    @State private var loginOn = Notify.atLogin
    @State private var loginError: String?
    @AppStorage("menuBarOn") private var menuBarOn = false
    var onDevice: Bool { if case .available = SystemLanguageModel.default.availability { true } else { false } }
    var body: some View {
        Form {
            LabeledContent("Claude Code:") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Agent.cli).textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button(testing ? "Testing…" : "Test Connection") { test() }.disabled(testing)
                        if let ok {
                            Label(status, systemImage: "circle.fill").labelStyle(.titleAndIcon).font(.caption)
                                .foregroundStyle(ok ? Color.green : Color.red).lineLimit(2)
                        }
                    }
                    Text("Runs on your Claude subscription. No API key.").font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("On-device model:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(onDevice ? "Available" : "Not available")
                    Text(onDevice ? "Detects which course an Unsorted file belongs to, offline." : "Course detection uses filenames only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 8)
            LabeledContent("Reaching you:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Morning brief the first time you open the app each day", isOn: Binding(get: { briefOn }, set: { briefOn = $0; UserDefaults.standard.set($0, forKey: "briefOn") }))
                    Toggle("Notify me about things that need me today", isOn: Binding(get: { notifyOn }, set: { on in
                        if on { Task { let ok = await Notify.enable(); notifyOn = ok; UserDefaults.standard.set(ok, forKey: "notifyOn") } }
                        else { notifyOn = false; UserDefaults.standard.set(false, forKey: "notifyOn") }
                    }))
                    Toggle("Show in the menu bar", isOn: $menuBarOn)
                    Toggle("Open at login", isOn: Binding(get: { loginOn }, set: { on in loginError = Notify.setAtLogin(on); loginOn = Notify.atLogin }))
                    if let e = loginError { Text(e).font(.caption).foregroundStyle(Color.redFG) }
                    Text("Notifications are only for a deadline today or at risk. With the menu bar item and open at login on, the Manager keeps looking for work after you close the window. Nothing here sorts on a schedule.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8)
            LabeledContent("Permissions:") {
                Text("Chat never edits your notes: an agent may only write in its own folder (notes to itself, rules it has learned). A job lets a helper edit just the one note it is given, or add the one new note it is told to. Agents never delete; originals go to .trash. Helpers never ask for approval: the Manager checks the work and undoes it if it fails.")
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 8)
        }
        .formStyle(.columns).padding(24)
    }
    func test() {
        testing = true; ok = nil
        Task {
            let r = await Agent.run("Reply with just OK.", system: "Reply briefly.", session: nil, canEdit: false, root: Vault.root)
            ok = r.session != nil
            status = ok == true ? "Connected" : r.text
            testing = false
        }
    }
}

struct RulesSettings: View {
    @State private var installed = AppFiles.statusLine()
    var body: some View {
        Form {
            LabeledContent("Templates and Agents:") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(installed).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Button("Reinstall Now") { installed = AppFiles.reinstall() }
                    Text("Each new version of the app copies its templates and the agents’ instructions into your vault. This does it again now; the old text of anything replaced stays in the vault’s .history folder.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.bottom, 8)
            LabeledContent("Vault rules:") {
                VStack(alignment: .leading, spacing: 6) {
                    open("Open AGENTS.md", "Agents/Shared Agents/AGENTS.md")
                    open("Open Decision Log", "Agents/Shared Agents/memory.md")
                    open("Open Open Items", "Agents/Shared Agents/open-items.md")
                    Text("Every agent follows these. They live in the vault’s Agents folder.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.columns).padding(24)
    }
    func open(_ title: String, _ path: String) -> some View {
        Button(title) { NSWorkspace.shared.open(Vault.root.appending(path: path)) }
    }
}

private extension View {
    /// A right-aligned label for a control that has its own text (like Safari's checkboxes).
    func formLabel(_ label: String) -> some View { LabeledContent(label) { self } }
}
