import SwiftUI

/// One open tab: the page it shows, and the pages it came from (for Back).
struct PageTab: Identifiable, Equatable {
    let id = UUID()
    var page: Page
    var back: [Page] = []
}

extension Store {
    var canGoBack: Bool { tabs.indices.contains(activeIndex) && !tabs[activeIndex].back.isEmpty }
    func goBack() {
        guard tabs.indices.contains(activeIndex), let p = tabs[activeIndex].back.popLast() else { return }
        tabs[activeIndex].page = p
    }
    func newTab(_ page: Page = .newTab) {
        tabs.append(PageTab(page: page))
        activeIndex = tabs.count - 1
        visited(page)
    }
    /// Home is a tab like the others: switch to it if it is open, otherwise open it.
    func openHome() {
        if let i = tabs.firstIndex(where: { $0.page == .overview }) { activeIndex = i } else { newTab(.overview) }
    }
    func selectTab(_ i: Int) { if tabs.indices.contains(i) { activeIndex = i } }
    /// Closing the last tab leaves a fresh Home tab.
    func closeTab(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count == 1 { tabs[0] = PageTab(page: .overview); activeIndex = 0; return }
        tabs.remove(at: i)
        if i < activeIndex { activeIndex -= 1 } else if i == activeIndex { activeIndex = min(i, tabs.count - 1) }
    }
    func closeOtherTabs(_ id: UUID) {
        guard let keep = tabs.first(where: { $0.id == id }) else { return }
        tabs = [keep]; activeIndex = 0
    }
    func duplicateTab(_ id: UUID) {
        guard let t = tabs.first(where: { $0.id == id }) else { return }
        newTab(t.page)
    }
    func closeCurrentTab() { if tabs.indices.contains(activeIndex) { closeTab(tabs[activeIndex].id) } }

    /// The name and icon a tab shows for a page.
    func tabInfo(_ p: Page) -> (title: String, icon: String) {
        switch p {
        case .newTab: ("New Tab", "plus.square.dashed")
        case .overview: ("Home", "house")
        case .messages: ("Messages", "message")
        case .inbox, .sortNow: ("Unsorted", "tray")
        case .week: ("Week", "chart.bar")
        case .month: ("Month", "calendar")
        case .semester: ("Semester", "graduationcap")
        case .course(let c): (c == "SM" ? "Strategy" : c, "graduationcap.fill")
        case .folder(let f): (SideNav.label(f), SideNav.folders.first { $0.name == f }?.icon ?? "folder")
        case .unsorted(let u): (Vault.label(u), "tray")
        case .search: ("Search", "magnifyingglass")
        case .agent(let id): (Agent.role(id).name, "sparkles")
        case .note(let u): (notes.first { $0.id == u }?.display ?? u.deletingPathExtension().lastPathComponent, "doc.text")
        case .file(let u): (u.deletingPathExtension().lastPathComponent, "doc.richtext")
        case .tags: ("Tags", "number")
        }
    }
}

/// The top strip of the window, laid out like Safari's toolbar. Over the sidebar: the window buttons and one glass group with the
/// sidebar, settings, notifications and Home. Then a divider, and over the pages the open tabs in a glass group of their own.
struct WindowTabBar: View {
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @State private var showNotices = false
    @State private var showUpdates = false

    var body: some View {
        let count = store.notices().count, update = Updater.shared.available
        HStack(spacing: 0) {
            // One glass pill the width of the sidebar pane below it: the window buttons, then the icons.
            HStack(spacing: 0) {
                Color.clear.frame(width: 76, height: 1)   // the window buttons sit here, inside the glass
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ChromeButton(icon: "sidebar.left", help: collapsed ? "Show Sidebar" : "Hide Sidebar") { withAnimation(.spring(duration: 0.45, bounce: 0.15)) { collapsed.toggle() } }
                    ChromeButton(icon: "gearshape", help: "Settings (⌘,)") { openSettings() }
                    ChromeButton(icon: update == nil ? "arrow.down.circle" : "arrow.down.circle.fill",
                                 help: update.map { "Update available: version \($0.version)" } ?? "Check for updates", on: update != nil, tint: update == nil ? nil : IM.blue) { showUpdates.toggle() }
                        .popover(isPresented: $showUpdates, arrowEdge: .bottom) { UpdatePanel() }
                    ChromeButton(icon: count > 0 ? "bell.badge" : "bell", help: count > 0 ? "Notifications, \(count)" : "Notifications") { showNotices.toggle() }
                        .popover(isPresented: $showNotices, arrowEdge: .bottom) { NoticeBox().padding(10).frame(width: 300, height: 380) }
                    ChromeButton(icon: "house", help: "Home", on: store.page == .overview) { store.openHome() }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(width: 240, height: 36)
            .glassEffect(.regular, in: .capsule)
            .padding(.leading, 12).padding(.trailing, 6)
            Rectangle().fill(Color.line.opacity(0.8)).frame(width: 1, height: 28)
            HStack(spacing: 0) { TabBar(); Spacer(minLength: 0) }.padding(.leading, 5).padding(.trailing, 12)
        }
        .frame(height: 36)
        .background(TrafficLights())
        .task { Updater.shared.startChecking() }
        .padding(.top, 12)        // the same room above the pill as at its left edge
    }
}

/// One round icon inside a glass group in the top strip. 28pt wide, so five fit beside the window buttons in the 240pt pill.
private struct ChromeButton: View {
    let icon: String
    let help: String
    var on = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint ?? (on ? Color.ink : Color.ink2))
                .frame(width: 28, height: 30).contentShape(.capsule)
                .background(Capsule().fill(Color.ink.opacity(on ? 0.1 : hover ? 0.06 : 0)))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help).accessibilityLabel(help)
    }
}

/// The open tabs and the + after them, in one glass capsule.
struct TabBar: View {
    @Environment(Store.self) private var store
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { i, tab in TabPill(tab: tab, index: i) }
                Button { store.newTab() } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2).frame(width: 30, height: 30).contentShape(.circle)
                }.buttonStyle(.plain).help("New Tab (⌘T)").accessibilityLabel("New tab")
            }
            .padding(3).glassEffect(.regular, in: .capsule)
        }
    }
}

private struct TabPill: View {
    @Environment(Store.self) private var store
    let tab: PageTab
    let index: Int
    @State private var hover = false
    var body: some View {
        let info = store.tabInfo(tab.page), active = index == store.activeIndex
        HStack(spacing: 6) {
            Button { store.closeTab(tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16).contentShape(.rect)
            }.buttonStyle(.plain).opacity(active || hover ? 1 : 0).help("Close Tab (⌘W)").accessibilityLabel("Close tab")
            Button { store.selectTab(index) } label: {
                HStack(spacing: 6) {
                    Image(systemName: info.icon).font(.system(size: 11))
                    Text(info.title).font(.system(size: 12, weight: active ? .medium : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }.contentShape(.rect)
            }.buttonStyle(.plain)
        }
        .foregroundStyle(active ? Color.ink : Color.ink2)
        .padding(.horizontal, 10).frame(minWidth: 70, maxWidth: 200).frame(height: 30)
        .background { Capsule().fill(active ? Color.card : Color.ink.opacity(hover ? 0.05 : 0)).shadow(color: .black.opacity(active ? 0.08 : 0), radius: 3, y: 1) }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Duplicate Tab") { store.duplicateTab(tab.id) }
            Button("Close Tab") { store.closeTab(tab.id) }
            Button("Close Other Tabs") { store.closeOtherTabs(tab.id) }.disabled(store.tabs.count < 2)
        }
    }
}


/// What a new tab shows: ways to create something, Quick Open, and the notes opened lately.
struct NewTabPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        let recent = store.recentNotes.filter { FileManager.default.fileExists(atPath: $0.path) }.prefix(5)
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 4) {
                    Text("Create in").font(.system(size: 12)).foregroundStyle(Color.ink2)
                    Text(Vault.name).font(.system(size: 20, weight: .semibold))
                }
                HStack(spacing: 16) {
                    NewTabCard(title: "New Note", hint: "Starts in Unsorted", icon: "square.and.pencil", key: "⌘N") { store.newNote() }
                    NewTabCard(title: "From Template", hint: "Lecture, essay…", icon: "doc.badge.plus", key: "⇧⌘N") { store.newStructured = true }
                    NewTabCard(title: "Voice Memo", hint: "Speak a note", icon: "mic", key: "⇧⌘M") { store.voiceMemo = true }
                }
                Button { store.quickOpen = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.ink2)
                        Text("Quick Open").foregroundStyle(Color.ink2)
                        Spacer()
                        Text("⌘P").font(.system(size: 11)).foregroundStyle(Color.ink2)
                    }.font(.system(size: 13)).glassField(height: 38).contentShape(.capsule)
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Opened").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink2).padding(.horizontal, 10).padding(.bottom, 2)
                    if recent.isEmpty { Text("Notes you open will show up here.").font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.horizontal, 10) }
                    ForEach(Array(recent), id: \.self) { url in
                        let note = store.notes.first { $0.id == url }
                        let detail = [note?.course, note?.kind].compactMap { $0 }.joined(separator: " · ")
                        Button { store.page = .note(url) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text").foregroundStyle(Color.ink2).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note?.display ?? Vault.label(url)).font(.system(size: 13)).lineLimit(1)
                                    Text(detail.isEmpty ? url.deletingLastPathComponent().lastPathComponent : detail)
                                        .font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(.rect)
                        }.buttonStyle(.glassRow)
                    }
                }
            }
            .frame(maxWidth: 560).padding(.vertical, 56).padding(.horizontal, 24).frame(maxWidth: .infinity)
        }
    }
}

private struct NewTabCard: View {
    let title: String, hint: String, icon: String, key: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.ink2)
                Spacer(minLength: 0)
                Text(title).font(.system(size: 14, weight: .semibold, design: .serif))
                Text(hint).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1)
                Text(key).font(.system(size: 10)).foregroundStyle(Color.ink2.opacity(0.8))
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.card)
                    .shadow(color: .black.opacity(hover ? 0.16 : 0.09), radius: hover ? 12 : 8, y: 3)
            }
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(Color.line.opacity(0.9)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
