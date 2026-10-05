import SwiftUI

/// How a list of notes is shown: big cards, small cards, or the sortable table. Remembered across pages.
enum ViewMode: String, CaseIterable {
    case gallery, grid, list
    var icon: String { switch self { case .gallery: "square.grid.2x2"; case .grid: "square.grid.3x3"; case .list: "list.bullet" } }
    var label: String { switch self { case .gallery: "Gallery"; case .grid: "Grid"; case .list: "List" } }
}

/// The three-icon switcher in a page header: one glass pill that slides between the views.
struct ViewModePicker: View {
    @Binding var mode: ViewMode
    @Namespace private var ns
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases, id: \.self) { m in
                    let on = mode == m
                    Button { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { mode = m } } label: {
                        Image(systemName: m.icon).font(.system(size: 14)).frame(width: 34, height: DS.Height.control)
                            .foregroundStyle(on ? Color.ink : Color.ink2)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(Color.ink.opacity(0.1)).interactive() : .identity, in: .capsule)
                    .glassEffectID(on ? "selected" : "option-\(m.rawValue)", in: ns)
                    .help(m.label).accessibilityLabel(m.label)
                }
            }
            .padding(4).glassEffect(.regular, in: .capsule)
        }
    }
}

/// The notification bell in a page header: the same notices as the sidebar's Notifications button.
struct NoticeBell: View {
    @Environment(Store.self) private var store
    @State private var open = false
    var body: some View {
        let n = store.notices().count
        Button { open.toggle() } label: { Image(systemName: n > 0 ? "bell.badge" : "bell").font(.system(size: 15)) }
            .buttonStyle(.glassIcon())
            .popover(isPresented: $open, arrowEdge: .bottom) { NoticeBox().padding(10).frame(width: 300, height: 380) }
            .help("Notifications").accessibilityLabel(n > 0 ? "Notifications, \(n)" : "Notifications")
    }
}

/// The right-hand side of a list page's header: view switcher, sort, more (filters and page settings), search, notifications.
/// `more` adds page-specific items to the top of the More menu.
struct PageToolbar<More: View>: View {
    let title: String
    var finder: URL? = nil
    var seasonal = false
    @Binding var mode: ViewMode
    @Binding var query: String
    let sortKeys: [String]
    @Binding var sortKey: String
    @Binding var ascending: Bool
    @ViewBuilder var more: More
    @State private var searching = false

    var body: some View {
        HStack(spacing: 10) {
            ViewModePicker(mode: $mode)
            Menu {
                Picker("Sort by", selection: $sortKey) { ForEach(sortKeys, id: \.self) { Text($0).tag($0) } }.pickerStyle(.inline)
                Picker("Order", selection: $ascending) { Text("Ascending").tag(true); Text("Descending").tag(false) }.pickerStyle(.inline)
            } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 15)) }
                .menuStyle(.button).buttonStyle(.glassIcon()).menuIndicator(.hidden).help("Sort")
            Menu {
                more
                Divider()
                if seasonal { AllDefaultToggle(title: title) }
                if SideNav.folders.contains(where: { $0.name == title }) { NavToggle(name: title, label: "Show in sidebar") }
                if let finder { Button("Show in Finder") { NSWorkspace.shared.open(finder) } }
            } label: { Image(systemName: "ellipsis").font(.system(size: 15)) }
                .menuStyle(.button).buttonStyle(.glassIcon()).menuIndicator(.hidden).help("More")
            Button { searching.toggle() } label: { Image(systemName: "magnifyingglass").font(.system(size: 15)) }
                .buttonStyle(.glassIcon(DS.Height.header, prominent: !query.isEmpty))
                .popover(isPresented: $searching, arrowEdge: .bottom) {
                    TextField("Filter", text: $query).textFieldStyle(.roundedBorder).frame(width: 220).padding(12)
                }
                .help("Filter").accessibilityLabel("Filter")
            NoticeBell()
        }
    }
}

/// One card in a gallery. The page decides what opening it and its right-click menu do.
struct GalleryItem: Identifiable {
    let id: URL
    let title: String
    let subtitle: String
    var code: String? = nil      // short course code: tints the card
    var done = false
    let open: () -> Void
    let menu: AnyView
}

/// The start of each note's text, cached by file and modified date, so the gallery can size its cards without re-reading files.
@MainActor enum GalleryPreview {
    private static var cache: [URL: (modified: Date?, text: String)] = [:]
    static func text(_ url: URL) -> String {
        guard url.pathExtension == "md" else { return "" }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let hit = cache[url], hit.modified == modified { return hit.text }
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let text = String(Vault.body(raw).trimmingCharacters(in: .whitespacesAndNewlines).prefix(1200))
        cache[url] = (modified, text)
        return text
    }
    /// Longer notes get taller cards, so the columns are uneven like a pinboard.
    static func height(_ text: String, compact: Bool) -> CGFloat {
        let lines = min(text.split(separator: "\n", omittingEmptySubsequences: true).count, 18)
        let lo: CGFloat = compact ? 130 : 190, hi: CGFloat = compact ? 210 : 330
        return lo + (hi - lo) * CGFloat(lines) / 18
    }
}

/// Notes as cards in masonry columns: a serif title and a tiny rendered thumbnail of the note.
struct NoteGallery: View {
    let items: [GalleryItem]
    let compact: Bool

    private struct Placed: Identifiable { let item: GalleryItem; let text: String; let height: CGFloat; var id: URL { item.id } }

    /// Deals the cards, in order, into whichever column is currently shortest.
    private func columns(_ n: Int) -> [[Placed]] {
        var cols = Array(repeating: [Placed](), count: n)
        var heights = Array(repeating: CGFloat(0), count: n)
        for item in items {
            let text = GalleryPreview.text(item.id)
            let h = GalleryPreview.height(text, compact: compact)
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            cols[i].append(Placed(item: item, text: text, height: h))
            heights[i] += h + 16
        }
        return cols
    }

    var body: some View {
        GeometryReader { g in
            let inner = max(g.size.width - 40, 100)
            let minWidth: CGFloat = compact ? 150 : 240
            let n = max(1, Int((inner + 16) / (minWidth + 16)))
            let w = (inner - CGFloat(n - 1) * 16) / CGFloat(n)
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(columns(n).enumerated()), id: \.offset) { _, col in
                        LazyVStack(spacing: 16) {
                            ForEach(col) { GalleryCard(item: $0.item, text: $0.text, width: w, height: $0.height, compact: compact) }
                        }
                    }
                }.padding(20)
            }
        }
    }
}

private struct GalleryCard: View {
    let item: GalleryItem
    let text: String
    let width: CGFloat
    let height: CGFloat
    let compact: Bool
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        let pad: CGFloat = compact ? 12 : 16
        Button(action: item.open) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: compact ? 14 : 19, weight: .semibold, design: .serif))
                    .foregroundStyle(item.done ? Color.ink2 : Color.ink).lineLimit(2).multilineTextAlignment(.leading)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 10)).foregroundStyle(Color.ink2).lineLimit(1) }
                thumbnail(inner: width - 2 * pad).padding(.top, 8)
            }
            .padding(pad)
            .frame(width: width, height: height, alignment: .topLeading)
            .background {
                shape.fill(Color.card)
                    .overlay { if item.code != nil { shape.fill(Color.course(item.code).opacity(0.3)) } }
                    .shadow(color: .black.opacity(hover ? 0.18 : 0.1), radius: hover ? 14 : 9, y: 3)
            }
            .overlay(shape.strokeBorder(Color.line.opacity(0.9)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .contextMenu { item.menu }
    }

    /// The note rendered at full size, then shrunk, like the page thumbnails in Craft. Fades out at the bottom.
    @ViewBuilder func thumbnail(inner: CGFloat) -> some View {
        let scale: CGFloat = compact ? 0.3 : 0.38
        Color.clear.frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    if item.id.pathExtension != "md" {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.id.path)).resizable().frame(width: 40, height: 40)
                    }
                } else {
                    MarkdownBlocks(blocks: MD.parse(text.components(separatedBy: "\n")))
                        .frame(width: inner / scale, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(scale, anchor: .topLeading)
                }
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}
