import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: never show a Dock icon, even when launched
        // without a proper .app bundle (e.g. via `swift run`).
        NSApp.setActivationPolicy(.accessory)

        // Register global keyboard shortcut to toggle the menu bar popover.
        // Default: ⌃⌥C — does not conflict with common app shortcuts.
        GlobalHotkeyMonitor.shared.onActivate = {
            // Find the first status item button and simulate a click to toggle the menu.
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .toggleMenuBarExtra, object: nil)
        }
        GlobalHotkeyMonitor.shared.register()
    }
}

extension Notification.Name {
    static let toggleMenuBarExtra = Notification.Name("ClaudeUsageToggleMenuBarExtra")
}
