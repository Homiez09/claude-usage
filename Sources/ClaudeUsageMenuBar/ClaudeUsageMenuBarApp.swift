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
    }
}
