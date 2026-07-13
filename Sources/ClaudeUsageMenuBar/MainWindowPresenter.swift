import AppKit
import SwiftUI

/// Presents `MenuContentView` in a real, standalone `NSWindow` instead of the
/// menu-bar-anchored popover `MenuBarExtra` used to show. Clicking the status
/// item toggles this window open/closed — it behaves like any other Mac app
/// window (can be moved, doesn't disappear when a different app is focused).
@MainActor
final class MainWindowPresenter {
    static let shared = MainWindowPresenter()

    private var windowController: NSWindowController?

    private init() {}

    func toggle(store: UsageStore) {
        if let window = windowController?.window, window.isVisible {
            window.orderOut(nil)
        } else {
            show(store: store)
        }
    }

    func show(store: UsageStore) {
        if windowController == nil {
            let hosting = NSHostingController(
                rootView: MenuContentView(store: store, activityMonitor: store.activityMonitor)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Claude Usage"
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
