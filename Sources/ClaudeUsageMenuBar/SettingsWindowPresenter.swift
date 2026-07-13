import AppKit
import SwiftUI

/// Presents SettingsView in a real NSWindow instead of a SwiftUI `.sheet`.
///
/// Historically `MenuContentView` lived inside `MenuBarExtra`'s borderless,
/// non-activating panel, where a `.sheet` stealing key-window status made the
/// panel resign key and auto-dismiss, dismissing the sheet with it (a rapid
/// open/close flicker loop). `MenuContentView` now lives in its own standalone
/// window (see `MainWindowPresenter`), but Settings stays a separate window
/// rather than a sheet for the same reason: it keeps working independently of
/// whether the main window is focused, and is simpler than reasoning about
/// sheet-vs-key-window interactions each time either window changes.
@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?

    private init() {}

    func show(store: UsageStore) {
        if windowController == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "ตั้งค่า Claude Usage"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}
