# Claude Usage — macOS Menu Bar App

A Swift menu bar app that mirrors claude.ai's "Plan usage limits" panel (current
session + weekly progress), plus:

- a local web server so an iPhone on the same Wi-Fi can view the same numbers
  in Safari with no app to install
- a Claude Code usage/cost history tab, computed locally from
  `~/.claude/projects/**/*.jsonl` (never sent over the network)
- live detection of which Claude Code sessions are actively working right
  now, shown on the menu bar icon (bounce animation) and in the dropdown

## Project structure

```
claude_usage/
├── Package.swift              # Swift Package Manager manifest
├── build_app.sh               # Builds release + packages ClaudeUsageMenuBar.app
├── Resources/
│   ├── Info.plist             # Bundle metadata for the packaged .app (LSUIElement, etc.)
│   └── claude-logo.png        # Source asset for the embedded menu bar logo
├── Sources/ClaudeUsageMenuBar/
│   ├── ClaudeUsageMenuBarApp.swift      # @main entry point, MenuBarExtra scene
│   ├── AppDelegate.swift                # Forces accessory (no Dock icon) activation policy
│   │
│   ├── UsageStore.swift                 # Central state: polls claude.ai, owns the
│   │                                     # local web server + activity monitor
│   ├── UsageService.swift               # HTTP client for claude.ai's usage API
│   ├── UsageModels.swift                # Codable models for the usage API response
│   ├── KeychainHelper.swift             # Session key storage (macOS Keychain)
│   ├── DateParsing.swift                # ISO8601 parsing + "resets in Xh Ym" formatting
│   │
│   ├── MenuContentView.swift            # The dropdown UI (Usage / History tabs)
│   ├── UsageHistoryView.swift           # History tab UI
│   ├── SettingsView.swift               # Session key entry screen
│   ├── SettingsWindowPresenter.swift    # Hosts SettingsView in a real NSWindow
│   │                                     # (not a SwiftUI .sheet — see inline comment
│   │                                     # for why that broke MenuBarExtra)
│   ├── MenuBarProgressIcon.swift        # Renders the colored menu bar icon as a bitmap
│   ├── ClaudeLogo.swift                 # Base64-embedded logo (see note below)
│   │
│   ├── LocalWebServer.swift             # Minimal HTTP server for the iPhone page
│   ├── LocalNetwork.swift               # Finds the Mac's LAN IP to display/copy
│   ├── UsageSnapshot.swift              # JSON payload served at /api/usage
│   │
│   ├── ClaudeCodeTranscriptScanner.swift    # Parses ~/.claude/projects/**/*.jsonl
│   ├── ClaudeCodeUsageRecord.swift          # One assistant turn's token usage
│   ├── ClaudeCodePricing.swift              # Published Anthropic API pricing table
│   ├── ClaudeCodeUsageAggregator.swift      # Buckets records by day/month/year
│   ├── ClaudeCodeHistoryStore.swift         # Background scan + publish for the History tab
│   └── ClaudeCodeActivityMonitor.swift      # Detects which sessions are "working now"
│                                             # by watching transcript modification times
│
└── Tests/ClaudeUsageMenuBarTests/       # XCTest suite (pure-logic tests only —
                                          # no test touches the real Keychain or
                                          # ~/.claude/projects; everything uses
                                          # isolated namespaces/temp directories)
```

### Why `.app` packaging is a custom script, not Xcode

This is a pure Swift Package (no `.xcodeproj`), so there's no built-in "make a
double-clickable app" step. `build_app.sh` does it by hand: `swift build -c
release`, then copies the binary + `Resources/Info.plist` into a
`ClaudeUsageMenuBar.app/Contents/{MacOS,}` bundle and ad-hoc code-signs it.

## Build and run

**Requirements:** macOS 13+, Swift 5.9+ (ships with Xcode 15+ / Command Line Tools).

### Quick iteration (no packaging)

```sh
swift build              # debug build
swift run                # build + launch directly (shows in the menu bar)
```

### Run the test suite

```sh
swift test
```

### Build the double-clickable app

```sh
./build_app.sh
open ClaudeUsageMenuBar.app
```

**First launch only:** since the binary is ad-hoc signed (no Apple Developer
account), macOS Gatekeeper blocks a plain double-click the first time. In
Finder, **Control-click → Open**, then confirm in the dialog — after that,
double-clicking works normally. You'll also see one Keychain prompt the first
time the app reads/writes the session key; choose **Always Allow** so it
doesn't ask again. Both of these reset if you rebuild the app (a new build
gets a new ad-hoc signature), so expect to repeat them after `./build_app.sh`
during development.

### First-time setup inside the app

1. Click the menu bar icon → **ตั้งค่า...** (Settings)
2. In Chrome, open claude.ai while logged in → DevTools (⌘⌥I) → Application →
   Cookies → copy the `sessionKey` cookie value
3. Paste it into the settings window and save — it's stored in macOS Keychain
   only, never written to disk elsewhere or sent anywhere but claude.ai

## Notes on the data sources

- **Plan usage limits** — fetched from claude.ai's own (undocumented,
  internal) `/api/organizations/{id}/usage` endpoint using the pasted session
  cookie. Not a public API; it can change without notice.
- **History tab costs** — computed locally from Claude Code's own transcript
  logs using published Anthropic API per-token pricing. This is an
  **equivalent-API-cost estimate**, not an actual bill — Claude Code on a
  Pro/Max subscription draws from a flat quota, not per-token billing.
- **"Working now" detection** — inferred from transcript file modification
  times (no official status API exists), so it's a heuristic, not a guarantee.
