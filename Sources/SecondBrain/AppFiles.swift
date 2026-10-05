import Foundation

/// The "University Brain App" folder (Templates and Agents) that ships inside the app. Each new version of the app copies it into the vault,
/// so the templates and the agents' instructions are whatever the installed version says they are.
enum AppFiles {
    static let folder = "University Brain App"
    /// Written to the vault root when an install finishes; holds the app version that did it.
    static let stamp = ".university-brain-app-version"

    /// The copy inside the app. Nil when running from `swift run` or a build without it.
    static var bundled: URL? {
        guard let u = Bundle.main.resourceURL?.appending(path: folder), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "0.0.0")+\(i?["CFBundleVersion"] as? String ?? "0")"
    }

    /// Copies the bundled folder into the vault when this app version hasn't done so yet. Returns the vault paths it wrote, or nil if nothing was due.
    /// A vault folder that doesn't exist yet is left alone (the app never creates one), and the install happens once it does.
    @discardableResult
    static func installIfNeeded(source: URL? = bundled, version: String = AppFiles.version, into root: URL = Vault.root) -> [String]? {
        guard let source, FileManager.default.fileExists(atPath: root.path),
              (try? String(contentsOf: root.appending(path: stamp), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) != version
        else { return nil }
        guard let written = try? install(from: source, into: root) else { return nil }   // no stamp, so the next launch tries again
        try? version.write(to: root.appending(path: stamp), atomically: true, encoding: .utf8)
        return written
    }

    /// Always overwrites: a file that differs is replaced, its old text kept in `.history/`. Files the app doesn't ship are never touched or deleted.
    static func install(from source: URL, into root: URL) throws -> [String] {
        let fm = FileManager.default, src = source.resolvingSymlinksInPath()
        var written: [String] = []
        for rel in (try fm.subpathsOfDirectory(atPath: src.path)).sorted() {
            let parts = rel.split(separator: "/")
            guard !parts.contains(where: { $0.hasPrefix(".") || $0 == ".." }) else { continue }   // .DS_Store and the like
            let from = src.appending(path: rel)
            guard (try? from.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let data = try Data(contentsOf: from), to = root.appending(path: rel)
            if let old = fm.contents(atPath: to.path) {
                if old == data { continue }
                try? Vault.snapshot(to, root: root)
            } else {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try data.write(to: to, options: .atomic)
            written.append(rel)
        }
        return written
    }

    static func check() {
        let fm = FileManager.default, box = fm.temporaryDirectory.appending(path: "sb-appfiles-check")
        try? fm.removeItem(at: box)
        let src = box.appending(path: "src/\(folder)"), vault = box.appending(path: "vault")
        for d in ["Templates/Claude", "Agents/Shared Agents"] { try! fm.createDirectory(at: src.appending(path: d), withIntermediateDirectories: true) }
        try! fm.createDirectory(at: vault.appending(path: "Agents/Shared Agents"), withIntermediateDirectories: true)
        try! "template v1".write(to: src.appending(path: "Templates/Claude/Lecture Template.md"), atomically: true, encoding: .utf8)
        try! "rules v1".write(to: src.appending(path: "Agents/Shared Agents/AGENTS.md"), atomically: true, encoding: .utf8)
        try! "hidden".write(to: src.appending(path: ".DS_Store"), atomically: true, encoding: .utf8)
        try! "mine".write(to: vault.appending(path: "Agents/Shared Agents/memory.md"), atomically: true, encoding: .utf8)   // not shipped: must survive
        try! "edited by hand".write(to: vault.appending(path: "Agents/Shared Agents/AGENTS.md"), atomically: true, encoding: .utf8)

        let first = installIfNeeded(source: src, version: "1.0.0+1", into: vault)
        precondition(first?.count == 2, "both shipped files installed: \(String(describing: first))")
        func read(_ p: String) -> String? { try? String(contentsOf: vault.appending(path: p), encoding: .utf8) }
        precondition(read("Templates/Claude/Lecture Template.md") == "template v1" && read("Agents/Shared Agents/AGENTS.md") == "rules v1", "shipped files overwrite the vault's")
        precondition(read("Agents/Shared Agents/memory.md") == "mine" && read(".DS_Store") == nil, "files the app doesn't ship are left alone")
        precondition(Vault.history(vault.appending(path: "Agents/Shared Agents/AGENTS.md"), root: vault).count == 1, "the replaced text is kept in .history")
        precondition(installIfNeeded(source: src, version: "1.0.0+1", into: vault) == nil, "the same version installs once")

        try! "template v2".write(to: src.appending(path: "Templates/Claude/Lecture Template.md"), atomically: true, encoding: .utf8)
        try! "my edit".write(to: vault.appending(path: "Templates/Claude/Lecture Template.md"), atomically: true, encoding: .utf8)
        precondition(installIfNeeded(source: src, version: "1.0.0+1", into: vault) == nil, "an edit between updates is left until the next version")
        precondition(installIfNeeded(source: src, version: "1.0.1+2", into: vault) == ["Templates/Claude/Lecture Template.md"], "a new version rewrites only what differs")
        precondition(read("Templates/Claude/Lecture Template.md") == "template v2", "new version overwrites the edit")
        precondition(installIfNeeded(source: src, version: "9.9.9+9", into: box.appending(path: "no-such-vault")) == nil, "a missing vault is not created")
        print("app files ok: shipped Templates and Agents overwrite once per version, old text kept, other files untouched")
    }
}
