import Foundation
import CoreServices

/// Calls `onChange` (on the main queue, coalesced to ~0.5s) whenever anything under `path` changes.
final class VaultWatcher {
    private final class Box { let f: () -> Void; init(_ f: @escaping () -> Void) { self.f = f } }
    private var stream: FSEventStreamRef?
    private let box: Box

    init(path: String, onChange: @escaping () -> Void) {
        box = Box(onChange)
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().f()
        }, &ctx, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}
