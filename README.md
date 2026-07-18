# Claude Usage — macOS Menu Bar App

A Swift menu bar app that mirrors claude.ai's "Plan usage limits" panel (current
session + weekly progress), plus:

- **Burn Rate & Projection:** Tracks your session quota consumption pace (% per hour) and predicts the exact time your quota will reset/hit 100% based on your usage.
- **Threshold Notifications:** Sends macOS local notifications when current session utilization or weekly model limits cross critical thresholds (80% and 95%), and again when the quota resets after having been near-full.
- **Session-End Notifications:** Notifies you when a Claude Code session that has been working continuously (≥2 minutes) goes idle — so you can switch away while long agentic tasks run.
- **Launch at Login:** Configurable option to automatically start the app on macOS startup.
- **Local Web Server & QR Code:** Minimal local HTTP server with inline QR Code in the dropdown for easily scanning and viewing usage stats on a mobile Safari browser on the same Wi-Fi network.
- **Claude Code History UI:** Computes usage and cost locally from `~/.claude/projects/**/*.jsonl` (never sent over the network).
- **Live Activity Detection:** Bounces the menu bar icon and highlights active Claude Code sessions in the dropdown.

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
│   │                                     # local web server + activity monitor, evaluates alerts
│   ├── UsageService.swift               # HTTP client for claude.ai's usage API
│   ├── UsageModels.swift                # Codable models for the usage API response
│   ├── SessionStore.swift               # Session key storage (AES-GCM encrypted file, not Keychain)
│   ├── DateParsing.swift                # ISO8601 parsing + "resets in Xh Ym" formatting
│   │
│   ├── MenuContentView.swift            # The dropdown UI (Usage / History tabs + QR code)
│   ├── UsageHistoryView.swift           # History tab UI with granular chart visualization
│   ├── SettingsView.swift               # Session key entry & notification / launch settings screen
│   ├── SettingsWindowPresenter.swift    # Hosts SettingsView in a real NSWindow
│   │                                     # (not a SwiftUI .sheet — see inline comment
│   │                                     # for why that broke MenuBarExtra)
│   ├── MenuBarProgressIcon.swift        # Renders the colored menu bar icon as a bitmap
│   ├── ClaudeLogo.swift                 # Base64-embedded logo (see note below)
│   │
│   ├── BurnRateEstimator.swift          # Session burn rate (%/hr) and reset projection estimator
│   ├── SessionEndPlanner.swift          # Detects "session just finished" transitions
│   │                                     # from the activity monitor's poll results
│   ├── LaunchAtLogin.swift              # Helper for configuring launch at login
│   ├── ModelDisplayName.swift           # Display names mapping for Anthropic models
│   ├── Palette.swift                    # Standard colors & theme utilities for views
│   ├── QRCodeGenerator.swift            # Generates a QR Code for scanning to view usage
│   ├── UsageAlerts.swift                # Triggers OS notification alerts at 80% / 95% usage
│   │
│   ├── LocalWebServer.swift             # Minimal HTTP server for the iPhone page & endpoints
│   ├── LocalNetwork.swift               # Finds the Mac's LAN IP to display/copy
│   ├── UsageSnapshot.swift              # JSON payload served at /api/usage
│   ├── UsageHistorySnapshot.swift       # History payload served at /api/history
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
account, so it's neither Developer-ID-signed nor notarized), a fresh download
carries the `com.apple.quarantine` flag macOS attaches to anything downloaded
via a browser. Two separate things happen because of that flag, and both need
handling or the app **will get silently killed by macOS partway through the
first launch** — commonly right around the time you're using the login
window, which looks like "the window flashes open and closes itself":

1. **Gatekeeper's launch block** — Finder refuses a plain double-click
   ("cannot verify developer"). **Control-click → Open**, then confirm in the
   dialog, works around this part.
2. **The deferred kill** — even after step 1, macOS's background security
   policy (`AppleSystemPolicy`) re-evaluates a quarantined, unnotarized app a
   short time (roughly 20–40s) after it actually starts running, and kills
   the whole process if it can't vouch for it — independent of anything the
   app itself is doing. Control-clicking "Open" does **not** prevent this;
   only removing the quarantine flag does:
   ```sh
   xattr -cr /path/to/ClaudeUsageMenuBar.app   # e.g. ~/Applications/ClaudeUsageMenuBar.app
   ```
   Run this once, before first launch (or after re-downloading a new
   release — the quarantine flag comes back on every fresh download).

Both quirks reset if you rebuild locally too (a new build gets a new ad-hoc
signature), so expect to repeat them after `./build_app.sh` during
development — though a locally-built copy never has the quarantine flag in
the first place (only browser/AirDrop/Mail downloads get it), so in practice
only the Gatekeeper "Open Anyway" prompt applies during local dev, not the
`xattr` step.

The only way to remove this friction for everyone permanently is enrolling in
the Apple Developer Program ($99/yr) and notarizing CI release builds — not
done here since this is a personal-use utility.

### First-time setup inside the app

1. Click the menu bar icon → **ตั้งค่า...** (Settings)
2. Click **เข้าสู่ระบบ Claude** and log in with your claude.ai account in the
   window that opens — the app captures the `sessionKey` cookie automatically
   once login succeeds
3. The session key is stored as an encrypted file in this Mac's Application
   Support folder (see `SessionStore.swift`) — never written anywhere else or
   sent anywhere but claude.ai

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
