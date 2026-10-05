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

/// Notes as cards: a serif title, a faded preview of the text, a soft tint for the course.
struct NoteGallery: View {
    let items: [GalleryItem]
    let compact: Bool
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 230), spacing: 14)], spacing: 14) {
                ForEach(items) { GalleryCard(item: $0, compact: compact) }
            }.padding(14)
        }
    }
}

private struct GalleryCard: View {
    let item: GalleryItem
    let compact: Bool
    @State private var preview = ""
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        Button(action: item.open) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.system(size: compact ? 14 : 18, weight: .semibold, design: .serif))
                    .foregroundStyle(item.done ? Color.ink2 : Color.ink).lineLimit(compact ? 2 : 3).multilineTextAlignment(.leading)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 11)).foregroundStyle(Color.ink2).lineLimit(1) }
                if preview.isEmpty && item.id.pathExtension != "md" {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.id.path)).resizable().frame(width: 40, height: 40).padding(.top, 6)
                } else {
                    Text(preview).font(.system(size: compact ? 9 : 11)).foregroundStyle(Color.ink2)
                        .lineLimit(compact ? 5 : 9).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: compact ? 150 : 230)
            .background {
                shape.fill(Color.card)
                    .overlay { if item.code != nil { shape.fill(Color.course(item.code).opacity(0.14)) } }
                    .shadow(color: .black.opacity(hover ? 0.14 : 0.07), radius: hover ? 12 : 8, y: 3)
            }
            .overlay(shape.strokeBorder(Color.line.opacity(0.6)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .contextMenu { item.menu }
        .task(id: item.id) { preview = Self.text(item.id) }
    }

    /// The start of the note's text, without the frontmatter or Markdown marks.
    static func text(_ url: URL) -> String {
        guard url.pathExtension == "md", let t = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let body = Vault.body(t).replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "*", with: "")
        return String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(700))
    }
}
