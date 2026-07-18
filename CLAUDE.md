# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
swift build              # debug build
swift run                # build + launch directly (shows in the menu bar)
swift test                # run the full XCTest suite
swift test --filter ClaudeCodeActivityMonitorTests          # run one test target/class
swift test --filter ClaudeCodeActivityMonitorTests/testFoo  # run one test method
./build_app.sh            # release build + package as ClaudeUsageMenuBar.app (ad-hoc signed)
open ClaudeUsageMenuBar.app
```

There is no lint step configured. This is a pure Swift Package Manager project — no `.xcodeproj`, no Xcode-only build system.

**After every `./build_app.sh` rebuild**, macOS treats the app as a new identity (fresh ad-hoc signature each build), so Gatekeeper will re-prompt: Control-click → Open in Finder to confirm. This is expected and unavoidable without a paid Apple Developer ID — don't try to script around it.

**Released (downloaded) builds are a separate, worse problem from local rebuilds.** A locally-built copy never carries `com.apple.quarantine`, so only the Gatekeeper "Open Anyway" prompt above applies. A copy someone *downloads* (GitHub release zip, AirDrop, etc.) does carry that flag, and since the binary is neither Developer-ID-signed nor notarized, macOS's background `AppleSystemPolicy` re-evaluates it ~20–40s after launch and silently kills the whole process if it can't vouch for it — reproduced locally by copying the built `.app`, tagging it with a synthetic `com.apple.quarantine` xattr, and watching `log show --predicate 'eventMessage CONTAINS "ClaudeUsageMenuBar"'` for `ASP: Security policy would not allow process`. This happens regardless of what the app is doing; it just tends to get noticed mid-login because that's the window the user is looking at when the ~20–40s mark hits. `xattr -cr ClaudeUsageMenuBar.app` before first launch removes the flag and prevents the kill (documented in README's Installation section) — Control-clicking "Open" alone does *not* fix this half of the problem. The only permanent fix for every downloader is notarization via a paid Apple Developer ID.

## Architecture

**Data flow, two independent sources feeding one `UsageStore`:**
1. **Remote (claude.ai plan usage)** — `UsageService` hits claude.ai's undocumented internal `/api/organizations/{id}/usage` endpoint using a session cookie captured automatically by `LoginWebViewPresenter` (a `WKWebView` login window — see `SettingsView`'s "เข้าสู่ระบบด้วย Claude" button) rather than pasted manually. The cookie is stored by `SessionStore` as an **AES-GCM encrypted file** under `~/Library/Application Support/ClaudeUsageMenuBar/session.enc` (perms `0600`), with the key derived from the Mac's hardware UUID — deliberately *not* the macOS Keychain, because an ad-hoc-signed app gets a fresh signature every rebuild and Keychain ACLs would then pop a scary "another app wants your saved item" prompt each time. The cookie is never logged or exposed through the local web server — only already-computed percentages/timestamps cross that boundary. `UsageStore.refresh()` polls this on a timer.
2. **Local (Claude Code activity + history)** — `ClaudeCodeTranscriptScanner` reads `~/.claude/projects/**/*.jsonl` directly off disk, parsing only `type`, `id`, `model`, `usage`, and `timestamp` fields (never `message.content`, to avoid touching conversation text). Two consumers read this scanner's output:
   - `ClaudeCodeActivityMonitor` — determines which sessions are "working now" via file-mtime recency (default 45s window — long tool calls/thinking can leave a transcript untouched for a while even mid-turn, so an overly tight window falsely reports "idle" and rarely catches multiple concurrent sessions in the same instant), resolves human-readable names from `ai-title` transcript entries (cached once resolved), and drives the menu bar icon's bounce animation via a `Timer` while any session is active.
   - `ClaudeCodeHistoryStore` — deduplicates records by message ID (resumed/compacted transcripts repeat messages) and, via `ClaudeCodeUsageAggregator`, buckets them into day/month/year, using `ClaudeCodePricing`'s published-rate table to produce an **estimated equivalent-API-cost** (not a real bill, since Claude Code subscriptions are quota-based, not per-token).

`UsageStore` (`@MainActor`) is the single hub: it owns one `ClaudeCodeActivityMonitor` and one `ClaudeCodeHistoryStore` instance (both injectable via optional init params — required for test isolation, since tests always construct with `autoStart: false` to avoid starting real background timers), and optionally starts a `LocalWebServer`.

**Local web server (`LocalWebServer`, port 8765)** lets an iPhone on the same Wi-Fi view the same data in Safari with zero app install. It's a hand-rolled `NWListener`/`NWConnection` HTTP server (no dependencies). Routing logic (`LocalWebServer.route(path:snapshotJSON:historyJSON:)`) is a `nonisolated static` pure function so it's directly testable without spinning up real sockets. Two JSON endpoints:
- `/api/usage` → `UsageSnapshot` (plan percentages, active session names, countdown — never the session key)
- `/api/history?granularity=day|month|year` → `UsageHistorySnapshot` built from `ClaudeCodeHistoryStore.buckets(for:)`

The HTML/CSS/JS served at `/` is an inline template string (`LocalWebServer.htmlPage`) that polls `/api/usage` every 3s and `/api/history` every 20s.

**Menu bar icon rendering** — `MenuBarIconRenderer` builds a SwiftUI view (Claude logo + two progress bars + countdown text) and rasterizes it via `ImageRenderer`, then sets `isTemplate = false`. This is required: `NSStatusItem`/`MenuBarExtra` force-templates (monochrome-tints) any SwiftUI `Image`/`Shape` used directly, which is why a plain SwiftUI icon looks broken/invisible — going through `ImageRenderer` to a real bitmap is the only way to get color into the menu bar icon.

**Settings window** — `SettingsWindowPresenter` opens `SettingsView` in a real `NSWindow`/`NSWindowController`, not a SwiftUI `.sheet()`. A `.sheet()` attached to a `MenuBarExtra` causes an open/close bounce loop, because `MenuBarExtra` is a non-activating panel and the sheet stealing the key window makes it resign and dismiss itself.

**Swift concurrency conventions used throughout:**
- `UsageStore`, `ClaudeCodeActivityMonitor`, `ClaudeCodeHistoryStore`, `LocalWebServer` are all `@MainActor` classes.
- Pure/testable logic is factored out as `nonisolated static` functions (e.g. `ClaudeCodeActivityMonitor.scanSessions`, `LocalWebServer.route`) so tests can call them synchronously without actor hops.
- Background file scanning uses `Task.detached(priority: .utility)`.
- MainActor-isolated types must not be used as *default parameter values* in inits (Swift evaluates default-argument expressions in a non-isolated context) — use `Optional = nil` and construct the real default inside the init body instead.

## Testing conventions (must follow)

- **Never let a test touch `SessionStore.shared` or the real `~/.claude/projects` directory.** Always construct `SessionStore(directory:namespace:)` with a temp directory + distinct `namespace:` per test, and pass a temp directory into scanner/store initializers. A prior bug had a test share the production session storage, which leaked the user's real session key into a failed-assertion message — this must not regress. (The `namespace:` also isolates the derived encryption key, so distinct namespaces can't decrypt each other's files even in the same directory.)
- Prefer testing the `nonisolated static` pure functions directly over spinning up the real timers/servers.
