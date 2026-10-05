import Foundation
import FoundationModels
import PDFKit

/// Works out which course an Unsorted file belongs to.
enum Detect {
    static let codes = ["MSOA", "SM", "TEM"]

    /// Instant: course code or name in the filename. Codes must stand alone ("SM-week2", "TEM_L03"):
    /// a bare substring test filed "Assessment brief.pdf" under SM and "Systems.pdf" under TEM.
    static func fromName(_ url: URL) -> String? {
        let n = url.lastPathComponent.uppercased()
        if let c = codes.first(where: { n.range(of: "(^|[^A-Z])\($0)($|[^A-Z])", options: .regularExpression) != nil }) { return c }
        for (full, code) in Vault.courses where n.contains(full.uppercased()) { return code }
        return n.contains("STRATEG") ? "SM" : nil
    }

    static func excerpt(_ url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            return (0..<min(2, doc.pageCount)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n").prefix(1500).description
        }
        return ((try? String(contentsOf: url, encoding: .utf8)) ?? "").prefix(1500).description
    }

    /// On-device (Apple Intelligence), free and offline. Returns nil when unsure or unavailable.
    static func onDevice(_ url: URL) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let text = excerpt(url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let prompt = """
        Which university course is this file for? Courses:
        MSOA = Management Science and Operations Analytics (operations, queues, simulation, optimisation)
        SM = Strategic Management (strategy, competitive advantage, business models)
        TEM = The Entrepreneurial Manager (entrepreneurship, startups, opportunities, failure)
        Reply with exactly one word: MSOA, SM, TEM or NONE.

        Filename: \(url.lastPathComponent)
        Text: \(text)
        """
        guard let reply = try? await LanguageModelSession().respond(to: prompt).content.uppercased() else { return nil }
        return codes.first { reply.contains($0) }
    }
}
