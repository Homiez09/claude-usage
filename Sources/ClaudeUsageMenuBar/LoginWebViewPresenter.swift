import AppKit
import WebKit

@MainActor
final class LoginWebViewPresenter: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    static let shared = LoginWebViewPresenter()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var currentProvider: LoginProvider?
    private var onLoginSuccess: (() -> Void)?

    private override init() {
        super.init()
    }

    func startLogin(provider: LoginProvider, completion: @escaping () -> Void) {
        self.currentProvider = provider
        self.onLoginSuccess = completion

        if window == nil {
            let webConfiguration = WKWebViewConfiguration()
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 550, height: 700), configuration: webConfiguration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            
            // Set standard desktop user agent to avoid "disallowed_useragent" on Google/GitHub SSO logins
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
            
            self.webView = webView

            // Observe cookie store for changes
            webView.configuration.websiteDataStore.httpCookieStore.add(self)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 700),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "เข้าสู่ระบบ \(provider.displayName)"
            window.contentView = webView
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        } else {
            window?.title = "เข้าสู่ระบบ \(provider.displayName)"
        }

        // Load login page
        let request = URLRequest(url: provider.loginURL)
        webView?.load(request)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        window?.close()
        window = nil
        webView = nil
        currentProvider = nil
        onLoginSuccess = nil
    }

    private func checkAndProcessCookies(_ cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] allCookies in
            Task { @MainActor in
                guard let self = self,
                      let provider = self.currentProvider,
                      let successCallback = self.onLoginSuccess
                else { return }

                var capturedValues: [String: String] = [:]
                for cookie in allCookies {
                    if provider.cookieNames.contains(cookie.name) {
                        capturedValues[cookie.name] = cookie.value
                    }
                }

                // If all target cookies are captured, save them and close window
                if capturedValues.count == provider.cookieNames.count {
                    if provider.id == "claude", let sessionKey = capturedValues["sessionKey"] {
                        KeychainHelper.shared.saveSessionKey(sessionKey)
                        KeychainHelper.shared.deleteOrganizationId()
                        
                        // Close window and execute callback
                        self.close()
                        successCallback()
                    }
                    // Future login providers can be handled here
                }
            }
        }
    }

    // MARK: - WKHTTPCookieStoreObserver

    func cookieStore(_ cookieStore: WKHTTPCookieStore, didChange cookies: [HTTPCookie]?) {
        checkAndProcessCookies(cookieStore)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Also check cookies immediately when page loads to handle "already logged in" redirects
        checkAndProcessCookies(webView.configuration.websiteDataStore.httpCookieStore)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Force popups/SSO login links that target a new window to open in the same webview
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
