import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: never show a Dock icon, even when launched
        // without a proper .app bundle (e.g. via `swift run`).
        NSApp.setActivationPolicy(.accessory)
    }
}
