import Foundation
import CoreServices

/// Calls `onChange` (on the main queue, coalesced to ~0.5s) whenever anything under `path` changes,
/// except inside dot-folders (`.history`, `.trash`, `.pdf-text`, `.obsidian`…). Those are the app's own bookkeeping and Obsidian's
/// window state; reloading the whole vault on the main thread for them (Obsidian rewrites workspace.json on every click) bought nothing.
final class VaultWatcher {
    private final class Box {
        let f: () -> Void, root: String
        init(_ f: @escaping () -> Void, root: String) { self.f = f; self.root = root }
        func changed(_ paths: [String]) {
            // no paths (or an unexpected shape) is treated as a real change, so a vault edit is never missed
            if paths.isEmpty || paths.contains(where: { !Self.hidden($0, under: root) }) { f() }
        }
        static func hidden(_ path: String, under root: String) -> Bool {
            guard path.hasPrefix(root + "/") else { return false }
            return path.dropFirst(root.count + 1).split(separator: "/").contains { $0.hasPrefix(".") }
        }
    }
    private var stream: FSEventStreamRef?
    private let box: Box

    init(path: String, onChange: @escaping () -> Void) {
        // FSEvents reports real paths (/private/tmp for /tmp), so compare against the resolved root
        box = Box(onChange, root: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, paths, _, _ in
            guard let info else { return }
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []   // a CFArray of CFStrings, because of UseCFTypes
            Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().changed(list)
        }, &ctx, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}
