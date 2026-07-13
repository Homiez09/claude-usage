import AppKit
import SwiftUI

/// Presents SettingsView in a real NSWindow instead of a SwiftUI `.sheet`.
///
/// MenuBarExtra's `.window` style content lives in a borderless, non-activating
/// panel: presenting a `.sheet` on top of it steals key-window status, which makes
/// the panel resign key and auto-dismiss, which in turn dismisses the sheet —
/// producing a rapid open/close flicker loop. A standalone window sidesteps this
/// entirely because it isn't a child of the menu bar panel.
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
