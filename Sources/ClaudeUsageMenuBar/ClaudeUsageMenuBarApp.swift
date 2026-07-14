import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore(enableLocalWebServer: true)

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store, activityMonitor: store.activityMonitor)
        } label: {
            MenuBarLabel(store: store, activityMonitor: store.activityMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var activityMonitor: ClaudeCodeActivityMonitor

    var body: some View {
        let hasError = store.errorMessage != nil && store.usage == nil
        Image(nsImage: MenuBarIconRenderer.render(
            sessionPercent: store.sessionPercent,
            weeklyPercent: store.weeklyPercent,
            countdownText: ResetDescriber.shortCountdown(store.sessionResetsAt),
            hasError: hasError,
            activityPhase: activityMonitor.isActive ? activityMonitor.animationPhase : nil,
            barWidth: store.barWidth,
            showSessionBar: store.showSessionBar,
            showWeeklyBar: store.showWeeklyBar
        ))
        .renderingMode(.original)
        // Listen for the global hotkey notification and simulate a click
        // on the status item button to open/close the popover.
        .onReceive(NotificationCenter.default.publisher(for: .toggleMenuBarExtra)) { _ in
            // NSStatusBar.system.statusItems is not exposed in Swift's public API;
            // KVC is the standard workaround for non-App-Store menu bar apps.
            if let items = NSStatusBar.system.value(forKey: "statusItems") as? [NSStatusItem] {
                items.first?.button?.performClick(nil)
            }
        }
    }
}
