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

/// The whole top strip of the window: window buttons, sidebar and settings buttons, Home, the open tabs, a + for a new one, and notifications.
struct WindowTabBar: View {
    @Environment(Store.self) private var store
    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 82, height: 1)   // room for the window buttons
            CollapseButton()
            SettingsButton()
            Button { store.openHome() } label: {
                Image(systemName: "house.fill").font(.system(size: 13)).foregroundStyle(store.page == .overview ? Color.ink : Color.ink2).frame(width: 28, height: 28).contentShape(.circle)
            }.buttonStyle(.plain).help("Home").accessibilityLabel("Home")
            TabBar()
            Spacer(minLength: 0)
            NoticeBell(size: DS.Height.icon)
        }
        .frame(height: 44).padding(.horizontal, 12)
        .background(TrafficLights())
    }
}

/// The open tabs and the + after them.
struct TabBar: View {
    @Environment(Store.self) private var store
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(store.tabs.enumerated()), id: \.element.id) { i, tab in TabPill(tab: tab, index: i) }
            Button { store.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2).frame(width: 28, height: 28).contentShape(.circle)
            }.buttonStyle(.plain).help("New Tab (⌘T)").accessibilityLabel("New tab")
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
