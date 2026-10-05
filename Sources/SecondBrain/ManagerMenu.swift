import SwiftUI

/// The Manager's controls, in one dropdown at the top right of the Agents page: pause, scan, what it is doing, undo, what it looks for, which agents are on,
/// the background budget, quiet hours, and records.
struct ManagerMenu: View {
    @Environment(Store.self) private var store
    @State private var showQueue = false
    @State private var showLog = false
    @AppStorage("managerMax") private var managerMax = Manager.Tier.deep.rawValue

    var body: some View {
        let _ = store.revision   // the menu reads UserDefaults, so it redraws when a setting changes
        let blocked = store.blockedReason()
        Menu {
            Text(blocked ?? (store.activeJobs.first.map { "\(Agent.role($0.agent).name): \($0.title)" } ?? "Idle: looking for work"))
            if store.pausedUntil == nil { Button("Pause the Manager", systemImage: "pause.fill") { store.pause(for: nil) } }
            else { Button("Resume the Manager", systemImage: "play.fill") { store.resume() } }
            Menu("Pause for…", systemImage: "clock") {
                Button("An hour") { store.pause(for: 3600) }
                Button("Four hours") { store.pause(for: 4 * 3600) }
                Button("Until tomorrow morning") { store.pauseUntilTomorrow() }
            }
            if !store.activeJobs.isEmpty { Button("Stop the current job", systemImage: "stop.fill") { store.stopCurrentJob() } }
            Button("Run a scan now", systemImage: "arrow.clockwise") { store.scheduleAutopilot(after: 1) }
            Button("What it’s doing…", systemImage: "list.bullet") { showQueue = true }
            Button(store.lastUndoable.map { "Undo last job: \($0.title)" } ?? "Undo last job", systemImage: "arrow.uturn.backward") { if let j = store.lastUndoable { store.undoJob(j.id) } }
                .disabled(store.lastUndoable == nil)
            Divider()
            Button("Sort Now", systemImage: "sparkles") { store.page = .sortNow }
            Menu("What it looks for", systemImage: "binoculars") {
                ForEach(["Jobs", "Checks"], id: \.self) { group in
                    Section(group) {
                        ForEach(Store.jobKinds.filter { $0.group == group }, id: \.id) { k in
                            Toggle(k.title, isOn: Binding(get: { store.jobOn(k.id) }, set: { store.setJob(k.id, $0) }))
                        }
                    }
                }
            }
            Menu("Agents", systemImage: "person.2") {
                ForEach(Agent.roles + Agent.courseRoles) { r in
                    Toggle(r.name + (store.agentFree(r.id) || !store.agentOn(r.id) ? "" : " (paused or at its daily limit)"), isOn: Binding(get: { store.agentOn(r.id) }, set: { store.setAgentOn(r.id, $0) }))
                }
            }
            Divider()
            Menu("Background budget: \(Store.budgets.first { $0.id == store.budgetPreset }?.title ?? "Balanced")", systemImage: "gauge.with.dots.needle.50percent") {
                Text(PlanUsage.summary.replacingOccurrences(of: " Press to refresh.", with: ""))
                Picker("Budget", selection: Binding(get: { store.budgetPreset }, set: { store.setBudget($0) })) {
                    ForEach(Store.budgets, id: \.id) { Text("\($0.title): stop at \(Int($0.five * 100))% of the 5-hour window").tag($0.id) }
                }.pickerStyle(.inline)
            }
            Menu("Effort ceiling", systemImage: "speedometer") {
                Picker("Highest effort it may choose", selection: $managerMax) {
                    Text("Quick (Haiku)").tag(Manager.Tier.quick.rawValue)
                    Text("Standard (Sonnet)").tag(Manager.Tier.standard.rawValue)
                    Text("Careful (Sonnet, high)").tag(Manager.Tier.careful.rawValue)
                    Text("Deep (Opus)").tag(Manager.Tier.deep.rawValue)
                }.pickerStyle(.inline)
            }
            Toggle("Pause on battery or Low Power Mode", isOn: Binding(get: { store.pauseOnBattery }, set: { store.setPauseOnBattery($0) }))
            Menu("Quiet hours", systemImage: "moon") {
                Toggle("Don’t start jobs overnight", isOn: Binding(get: { store.quietOn }, set: { store.setQuiet(on: $0) }))
                Picker("From", selection: Binding(get: { store.quietFrom }, set: { store.setQuiet(from: $0) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker("Until", selection: Binding(get: { store.quietTo }, set: { store.setQuiet(to: $0) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            }
            Menu("Daily limits and usage", systemImage: "chart.bar") {
                ForEach(store.usageByAgent(), id: \.agent) { u in Text("\(Agent.role(u.agent).name): \(u.today) of \(store.dailyCap(u.agent)) today · \(u.week) this week") }
            }
            Divider()
            Button("Activity Log", systemImage: "list.bullet.rectangle") { showLog = true }
            Button("Agent Roster", systemImage: "tablecells") { store.page = .note(Vault.root.appending(path: "Agents/Shared Agents/Agent Roster.md")) }
            Button("The Manager’s own file", systemImage: "doc.text") { store.page = .note(Vault.root.appending(path: Agent.file(Agent.manager.id))) }
            SettingsLink { Text("Settings…") }
        } label: {
            Label("Manager", systemImage: blocked == nil ? "person.badge.clock" : "pause.circle")
        }
        .menuStyle(.button).buttonStyle(.glassAction(.header)).fixedSize().help(blocked ?? "The Manager: pause, budget, what it looks for")
        .popover(isPresented: $showQueue, arrowEdge: .bottom) { ManagerQueue().environment(store) }
        .popover(isPresented: $showLog, arrowEdge: .bottom) { ActivityLog().environment(store) }
    }
}

/// What the Manager is doing now, and what it would do next.
struct ManagerQueue: View {
    @Environment(Store.self) private var store
    @State private var next: [(score: Double, job: Store.Job)] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Doing now").font(.headline)
            if store.activeJobs.isEmpty { Text("Nothing. It looks again whenever the vault changes.").font(.system(size: 12)).foregroundStyle(Color.ink2) }
            ForEach(store.activeJobs) { j in
                HStack(spacing: 8) {
                    AgentPortrait(id: j.agent, size: 22)
                    VStack(alignment: .leading, spacing: 1) { Text(j.title).font(.system(size: 12)); Text(store.jobLine(j)).font(.system(size: 11)).foregroundStyle(Color.ink2) }
                }
            }
            Divider()
            Text("Next").font(.headline)
            if next.isEmpty { Text("Nothing waiting.").font(.system(size: 12)).foregroundStyle(Color.ink2) }
            ForEach(Array(next.prefix(8).enumerated()), id: \.offset) { _, n in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(Int(n.score))").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 26, alignment: .trailing).foregroundStyle(Color.ink2)
                    Text(n.job.label).font(.system(size: 12)).lineLimit(2)
                }
            }
        }
        .padding(16).frame(width: 380, alignment: .leading)
        .onAppear { next = store.scan() }
    }
}
