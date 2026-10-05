import SwiftUI
import FoundationModels

/// Settings → Manager: everything in the Manager menu on the Agents page, in one place.
struct ManagerSettings: View {
    @Environment(Store.self) private var store
    @State private var managerOn = Manager.on
    @State private var managerMax = Manager.ceiling
    @State private var briefOn = UserDefaults.standard.object(forKey: "briefOn") as? Bool ?? true
    var onDevice: Bool { if case .available = SystemLanguageModel.default.availability { true } else { false } }

    var body: some View {
        let _ = store.revision   // settings live in UserDefaults, so the form redraws when one changes
        ScrollView { Form {
            LabeledContent("Manager:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Looks for work and hands it to helpers", isOn: Binding(get: { store.autopilotOn }, set: { store.setAutopilot($0) }))
                    Text(store.blockedReason().map { $0.replacingOccurrences(of: "switched off in Settings", with: "switched off") } ?? (store.activeJobs.first.map { "Working: \(Agent.role($0.agent).name), \($0.title)" } ?? "Idle, looking for work")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if store.pausedUntil == nil { Button("Pause") { store.pause(for: nil) } } else { Button("Resume") { store.resume() } }
                        Button("Pause for an hour") { store.pause(for: 3600) }
                        Button("Until tomorrow") { store.pauseUntilTomorrow() }
                    }
                    Text("The Manager is the only agent that looks for work, and it runs on your Mac. It picks a helper for each job and asks the relevant course agent what matters first; the helper does it without waiting for you, and the Manager checks the result and puts it back if it fails. Everything shows in the Activity Log with an Undo.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(onDevice ? "Apple’s on-device model is available, so routing and review use it." : "Apple’s on-device model isn’t available, so the Manager uses rules and code checks only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Budget:") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: Binding(get: { store.budgetPreset }, set: { store.setBudget($0) })) {
                        ForEach(Store.budgets, id: \.id) { Text($0.title).tag($0.id) }
                    }.pickerStyle(.segmented).labelsHidden()
                    let b = Store.budgets.first { $0.id == store.budgetPreset } ?? Store.budgets[1]
                    Text("Background jobs stop at \(Int(b.five * 100))% of your 5-hour Claude window (\(Int(b.week * 100))% of the week); Opus jobs at \(Int(b.deepFive * 100))%. The rest is left for your own use. \(PlanUsage.summary.replacingOccurrences(of: " Press to refresh.", with: ""))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8)
            LabeledContent("Effort:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Choose model and effort per job", isOn: Binding(get: { managerOn }, set: { managerOn = $0; UserDefaults.standard.set($0, forKey: "managerOn") }))
                    Picker("Highest effort it may choose", selection: Binding(get: { managerMax }, set: { managerMax = $0; UserDefaults.standard.set($0.rawValue, forKey: "managerMax") })) {
                        Text("Quick (small model only)").tag(Manager.Tier.quick)
                        Text("Standard (Sonnet)").tag(Manager.Tier.standard)
                        Text("Careful (Sonnet, high effort)").tag(Manager.Tier.careful)
                        Text("Deep (Opus for essay help)").tag(Manager.Tier.deep)
                    }.disabled(!managerOn)
                    let c = Manager.weekCounts()
                    Text("Last 7 days: \(c[.quick] ?? 0) quick · \(c[.standard] ?? 0) standard · \(c[.careful] ?? 0) careful · \(c[.deep] ?? 0) deep. Off: every agent run uses Claude Code’s own defaults.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8)
            LabeledContent("When:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Pause on battery or in Low Power Mode", isOn: Binding(get: { store.pauseOnBattery }, set: { store.setPauseOnBattery($0) }))
                    Toggle("Quiet hours: don’t start jobs", isOn: Binding(get: { store.quietOn }, set: { store.setQuiet(on: $0) }))
                    HStack(spacing: 8) {
                        Picker("From", selection: Binding(get: { store.quietFrom }, set: { store.setQuiet(from: $0) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }.fixedSize()
                        Picker("Until", selection: Binding(get: { store.quietTo }, set: { store.setQuiet(to: $0) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }.fixedSize()
                    }.disabled(!store.quietOn)
                    Toggle("Morning brief the first time you open the app each day", isOn: Binding(get: { briefOn }, set: { briefOn = $0; UserDefaults.standard.set($0, forKey: "briefOn") }))
                    Text("The calendar keeps syncing while the Manager is paused. A note you changed in the last five minutes, or have open, is left alone.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 8)
            LabeledContent("Looks for:") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Jobs", "Checks"], id: \.self) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group == "Jobs" ? "Jobs (a helper does the work)" : "Checks (on your Mac, free)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Store.jobKinds.filter { $0.group == group }, id: \.id) { k in
                                Toggle(k.title, isOn: Binding(get: { store.jobOn(k.id) }, set: { store.setJob(k.id, $0) }))
                            }
                        }
                    }
                }
            }.padding(.top, 8)
            LabeledContent("Agents:") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Agent.roles + Agent.courseRoles) { r in
                        let u = store.usageByAgent().first { $0.agent == r.id }
                        Toggle(r.name + (u.map { "  ·  \($0.today) of \(store.dailyCap(r.id)) today, \($0.week) this week" } ?? ""), isOn: Binding(get: { store.agentOn(r.id) }, set: { store.setAgentOn(r.id, $0) }))
                    }
                    Text("A helper that fails the Manager’s review three times in a row is paused for a day.").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            }.padding(.top, 8)
        }
        .formStyle(.columns).padding(24) }
        .frame(height: 560)
    }
}
