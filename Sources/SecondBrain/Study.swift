import SwiftUI

/// Revision was split into these note types, each with its own folder in Apps/, template, page and preview.
enum Study {
    struct Kind { let folder: String; let noun: String; let icon: String }
    static let kinds: [Kind] = [
        .init(folder: "MCQ", noun: "MCQ", icon: "checklist"),
        .init(folder: "Flashcards", noun: "Flashcards", icon: "rectangle.on.rectangle"),
        .init(folder: "Past Papers", noun: "Past Paper", icon: "doc.text.magnifyingglass"),
        .init(folder: "Summaries", noun: "Summary", icon: "list.bullet.rectangle"),
        .init(folder: "Mind Maps", noun: "Mind Map", icon: "point.3.connected.trianglepath.dotted"),
        .init(folder: "Glossary", noun: "Glossary", icon: "character.book.closed"),
        .init(folder: "Podcast", noun: "Podcast", icon: "waveform"),
    ]
    static let folders = kinds.map(\.folder)
    static func isStudy(_ folder: String) -> Bool { folders.contains(folder) }
    static func kind(_ folder: String) -> Kind? { kinds.first { $0.folder == folder } }
}
