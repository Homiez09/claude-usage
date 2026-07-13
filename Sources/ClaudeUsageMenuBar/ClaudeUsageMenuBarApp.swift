import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore(enableLocalWebServer: true)

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let hasError = store.errorMessage != nil && store.usage == nil
        Image(nsImage: MenuBarIconRenderer.render(
            sessionPercent: store.sessionPercent,
            weeklyPercent: store.weeklyPercent,
            countdownText: ResetDescriber.shortCountdown(store.sessionResetsAt),
            hasError: hasError
        ))
        .renderingMode(.original)
    }
}
