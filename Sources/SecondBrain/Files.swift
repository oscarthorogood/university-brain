import SwiftUI
import PDFKit

/// Notes and PDFs open inside the app; anything else goes to its own app.
extension Store {
    func openFile(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "pdf": page = .file(url)
        case "md": page = .note(url)
        default: NSWorkspace.shared.open(url)
        }
    }
}

struct PDFViewer: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePageContinuous; v.displaysPageBreaks = true
        v.document = PDFDocument(url: url); return v
    }
    func updateNSView(_ v: PDFView, context: Context) { if v.document?.documentURL != url { v.document = PDFDocument(url: url) } }
}

struct FilePage: View {
    let url: URL
    @State private var pages: Int?   // counted once per file, off the main thread (opening the PDF in `body` re-read it on every redraw)
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: url.deletingPathExtension().lastPathComponent,
                       subtitle: [url.pathExtension.uppercased(), pages.map { "\($0) pages" }, url.deletingLastPathComponent().lastPathComponent].compactMap { $0 }.joined(separator: " · ")) {
                HStack(spacing: 10) {
                    RoundButton(icon: "arrow.up.forward.app", label: "Open in Preview") { NSWorkspace.shared.open(url) }
                    RoundButton(icon: "folder", label: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            Card { PDFViewer(url: url).clipShape(.rect(cornerRadius: DS.Radius.card)) }.padding([.horizontal, .bottom], 12)
        }.id(url)
        .task(id: url) {
            pages = nil
            let file = url
            pages = await Task.detached { PDFDocument(url: file)?.pageCount }.value
        }
    }
}
