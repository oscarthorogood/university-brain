import AppKit

/// Whether the window can be seen at all (not minimised, hidden, or on another Space). Animations pause while it can't:
/// nobody is watching, and a line-art agent redrawing 24 times a second costs a good part of a CPU core for nothing.
@MainActor @Observable final class Visibility {
    static let shared = Visibility()
    var visible = true
    var active = true   // the app is frontmost; when it isn't, animations only tick over slowly
    private init() {
        active = NSApplication.shared.isActive
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in MainActor.assumeIsolated { Visibility.shared.active = NSApp.isActive } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Visibility.shared.visible = NSApp.occlusionState.contains(.visible) }
        }
    }
}
