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
    func newTab(_ page: Page = .overview) {
        tabs.append(PageTab(page: page))
        activeIndex = tabs.count - 1
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

/// The strip of open tabs along the top of the main panel.
struct TabBar: View {
    @Environment(Store.self) private var store
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(store.tabs.enumerated()), id: \.element.id) { i, tab in TabPill(tab: tab, index: i) }
            Button { store.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2).frame(width: 28, height: 28).contentShape(.circle)
            }.buttonStyle(.plain).help("New Tab (⌘T)").accessibilityLabel("New tab")
            Spacer(minLength: 0)
        }.frame(height: 34)
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
