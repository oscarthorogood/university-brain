import SwiftUI
import UserNotifications
import ServiceManagement

/// Things that need you today, when the window is closed: a plan ready for your tick, a deadline today. Off until you turn it on.
enum Notify {
    static var on: Bool { UserDefaults.standard.bool(forKey: "notifyOn") }
    static func enable() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    /// `id` makes a repeat replace the earlier one instead of stacking.
    static func post(_ title: String, _ body: String, id: String) {
        guard on else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
    /// Open at login (Settings): only works for the app installed in /Applications.
    static var atLogin: Bool { SMAppService.mainApp.status == .enabled }
    static func setAtLogin(_ on: Bool) -> String? {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; return nil }
        catch { return error.localizedDescription }
    }
}

extension Store {
    /// Deadlines that fall today and aren't done: one notification each, once a day.
    func notifyDueToday() {
        guard Notify.on else { return }
        let today = Date.now.formatted(.iso8601.year().month().day())
        for n in notes where n.course != nil && !n.done && ["Essays", "Projects", "Readings"].contains(n.folder) {
            guard let w = n.when, Calendar.current.isDateInToday(w) else { continue }
            let key = "notified-\(n.path)-\(today)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            UserDefaults.standard.set(true, forKey: key)
            Notify.post("Due today", n.display, id: key)
        }
    }
}
