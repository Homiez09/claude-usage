import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The status item + its window are managed entirely by AppDelegate /
        // MainWindowPresenter; this empty Settings scene just satisfies
        // SwiftUI's requirement that an App have at least one Scene.
        Settings {
            EmptyView()
        }
    }
}
