import SwiftUI
import AppKit
import CryptoKit

/// A release on GitHub that this app can update to.
struct AppRelease: Equatable, Sendable {
    let version: String
    let notes: String
    let page: URL        // the release on github.com
    let dmg: URL
    let checksum: URL?   // `<dmg name>.sha256`, written by make-dmg.sh
}

enum UpdateError: LocalizedError {
    case noRelease, noDMG, download, checksum, noApp, tool(String)
    var errorDescription: String? {
        switch self {
        case .noRelease: "There’s no published release yet."
        case .noDMG: "The latest release has no disk image."
        case .download: "The download didn’t finish."
        case .checksum: "The download didn’t match its checksum, so it wasn’t installed."
        case .noApp: "The disk image doesn’t contain University Brain."
        case .tool(let t): "Installing failed (\(t)). If the app is in /Applications, check you can write there."
        }
    }
}

/// Updates from GitHub Releases. The app checks shortly after launch and every six hours; installing downloads the DMG,
/// checks its SHA-256, copies the app out next to this one, then a small shell script waits for this app to quit,
/// swaps the bundles (the old one goes to the Trash) and opens the new one.
/// Downloads made by the app aren't quarantined, so Gatekeeper doesn't stop the updated app the way it stops a browser download.
@MainActor @Observable final class Updater {
    static let shared = Updater()
    nonisolated static let repo = "oscarthorogood/university-brain"

    enum State: Equatable { case idle, checking, upToDate(Date), available(AppRelease), downloading(AppRelease), installing, failed(String) }
    var state = State.idle

    /// The version in Info.plist (set by bundle.sh from the git tag). A build without one counts as 0.0.0, so every release is newer.
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    /// Only an installed .app can replace itself; `swift run` and the command-line modes open the release page instead.
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var available: AppRelease? { if case .available(let r) = state { r } else { nil } }
    var busy: Bool { switch state { case .checking, .downloading, .installing: true; default: false } }

    @ObservationIgnored private var loop: Task<Void, Never>?
    private init() {}

    /// Starts the background checks (once; later calls do nothing).
    func startChecking() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                await self?.check(quietly: true)
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    /// `quietly`: a background check that fails (offline, say) says nothing and keeps what was known.
    func check(quietly: Bool = false) async {
        guard !busy else { return }
        let before = state
        state = .checking
        do {
            let r = try await Self.latest()
            state = Self.isNewer(r.version, than: current) ? .available(r) : .upToDate(.now)
        } catch {
            state = quietly ? before : .failed("Couldn’t check for updates: \(error.localizedDescription)")
        }
    }

    func install() async {
        guard let r = available else { return }
        guard canInstall else { NSWorkspace.shared.open(r.page); return }
        state = .downloading(r)
        do {
            let app = Bundle.main.bundleURL, id = Bundle.main.bundleIdentifier ?? ""
            let staged = try await Self.download(r, nextTo: app, bundleID: id)
            state = .installing
            try Self.relaunch(replacing: app, with: staged)
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: GitHub

    nonisolated static func latest() async throws -> AppRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("UniversityBrain-Updater", forHTTPHeaderField: "User-Agent")   // GitHub's API refuses requests without one
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.noRelease }
        struct GH: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String; let body: String?; let html_url: URL; let assets: [Asset]
        }
        let gh = try JSONDecoder().decode(GH.self, from: data)
        guard let dmg = gh.assets.first(where: { $0.name.hasSuffix(".dmg") }) else { throw UpdateError.noDMG }
        return AppRelease(version: String(gh.tag_name.drop(while: { $0 == "v" })), notes: gh.body ?? "", page: gh.html_url,
                          dmg: dmg.browser_download_url, checksum: gh.assets.first { $0.name == dmg.name + ".sha256" }?.browser_download_url)
    }

    /// "1.10.0" is newer than "1.9.2". Anything after a "-" (a pre-release tag) is ignored.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { (s.split(separator: "-").first ?? "").split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Installing

    /// Downloads and checks the image, then copies the app out of it next to `app`. Returns the copy.
    nonisolated static func download(_ r: AppRelease, nextTo app: URL, bundleID: String) async throws -> URL {
        let (temp, resp) = try await URLSession.shared.download(for: URLRequest(url: r.dmg, timeoutInterval: 120))
        guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { throw UpdateError.download }
        let dmg = FileManager.default.temporaryDirectory.appending(path: "UniversityBrain-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: temp, to: dmg)
        if let sumURL = r.checksum {
            let (d, _) = try await URLSession.shared.data(for: URLRequest(url: sumURL, timeoutInterval: 30))
            let want = String(decoding: d, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() }
            let have = try await Task.detached {
                let bytes = try Data(contentsOf: dmg, options: .mappedIfSafe)
                return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            }.value
            guard want == have else { try? FileManager.default.removeItem(at: dmg); throw UpdateError.checksum }
        }
        return try await Task.detached { try stage(dmg: dmg, nextTo: app, bundleID: bundleID) }.value
    }

    /// Mounts the image read-only, copies the app beside the running one (same volume, so the swap is a rename), unmounts.
    nonisolated static func stage(dmg: URL, nextTo app: URL, bundleID: String) throws -> URL {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appending(path: "UniversityBrain-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dmg); try? fm.removeItem(at: mount) }
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        // the image must hold this app, not something else
        guard let found = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              Bundle(url: found)?.bundleIdentifier == bundleID else { throw UpdateError.noApp }
        let staged = app.deletingLastPathComponent().appending(path: ".University Brain update.app")
        try? fm.removeItem(at: staged)
        try run("/usr/bin/ditto", [found.path, staged.path])
        return staged
    }

    nonisolated static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.tool((tool as NSString).lastPathComponent) }
    }

    /// Waits for this app to quit, moves it to the Trash, puts the new one in its place (or the old one back if that fails) and opens it.
    static func relaunch(replacing app: URL, with staged: URL) throws {
        let script = #"""
        while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
        old="$HOME/.Trash/University Brain (replaced $(date +%Y%m%d-%H%M%S)).app"
        if mv "$2" "$old"; then
          if mv "$3" "$2"; then xattr -cr "$2" 2>/dev/null; else mv "$old" "$2"; fi
        fi
        open "$2"
        """#
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "updater", String(ProcessInfo.processInfo.processIdentifier), app.path, staged.path]
        try p.run()
    }
}

/// The popover behind the update icon in the top strip.
struct UpdatePanel: View {
    var body: some View {
        let u = Updater.shared
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates").font(.headline)
            Text("This version: \(u.current)").font(.caption).foregroundStyle(Color.ink2)
            switch u.state {
            case .idle:
                Text("Not checked yet.").foregroundStyle(Color.ink2)
            case .checking:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…") }
            case .upToDate(let d):
                Text("You’re up to date. Checked \(d.formatted(.relative(presentation: .named))).").foregroundStyle(Color.ink2)
            case .available(let r):
                Text("Version \(r.version) is available.").fontWeight(.semibold)
                if !r.notes.isEmpty {
                    ScrollView { Text(LocalizedStringKey(r.notes)).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                }
                Button(u.canInstall ? "Install and Relaunch" : "Open the Download Page") { Task { await u.install() } }
                    .buttonStyle(.glassAction(.control, prominent: true))
                Link("Release notes on GitHub", destination: r.page).font(.caption)
            case .downloading(let r):
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Downloading \(r.version)…") }
            case .installing:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing. The app will reopen.") }
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(Color.redFG).fixedSize(horizontal: false, vertical: true)
            }
            if !u.busy && u.available == nil {
                Button("Check Now") { Task { await u.check() } }.buttonStyle(.glassAction(.control))
            }
        }
        .font(.system(size: 13)).padding(16).frame(width: 300, alignment: .leading)
    }
}
