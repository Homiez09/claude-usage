import Foundation

struct LoginProvider: Identifiable {
    let id: String
    let displayName: String
    let loginURL: URL
    let cookieNames: [String]
    let logoSystemName: String
}

extension LoginProvider {
    static let claude = LoginProvider(
        id: "claude",
        displayName: "Claude",
        loginURL: URL(string: "https://claude.ai/login")!,
        cookieNames: ["sessionKey"],
        logoSystemName: "sparkles"
    )

    // Future providers can be added here, for example:
    // static let chatgpt = LoginProvider(...)
}
