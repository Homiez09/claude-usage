import AppKit
import Combine

/// Owns the status bar icon and the app's single `UsageStore`. Replaces
/// SwiftUI's `MenuBarExtra` (which only ever shows a popover anchored under
/// the icon) with a manual `NSStatusItem` whose click opens a real, freely
/// movable window via `MainWindowPresenter`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore(enableLocalWebServer: true)

    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: never show a Dock icon, even when launched
        // without a proper .app bundle (e.g. via `swift run`).
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        updateIcon()

        // The icon (bars, countdown, bounce) depends on both the remote usage
        // poll and the local activity monitor; re-render on either change
        // since there's no SwiftUI view doing this automatically anymore.
        store.objectWillChange
            .merge(with: store.activityMonitor.objectWillChange)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        let hasError = store.errorMessage != nil && store.usage == nil
        statusItem?.button?.image = MenuBarIconRenderer.render(
            sessionPercent: store.sessionPercent,
            weeklyPercent: store.weeklyPercent,
            countdownText: ResetDescriber.shortCountdown(store.sessionResetsAt),
            hasError: hasError,
            activityPhase: store.activityMonitor.isActive ? store.activityMonitor.animationPhase : nil
        )
    }

    @objc private func statusItemClicked() {
        MainWindowPresenter.shared.toggle(store: store)
    }
}
