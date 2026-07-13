#!/bin/bash
# Builds ClaudeUsageMenuBar in release mode and packages it as a
# double-clickable ClaudeUsageMenuBar.app in the project root.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsageMenuBar"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building release binary..."
swift build -c release

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"

cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Ad-hoc code sign so Gatekeeper/Keychain treat this as a stable, consistent
# identity across rebuilds (otherwise every rebuild looks like a new app to
# the Keychain ACL prompt).
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: $(pwd)/${APP_BUNDLE}"
echo "    Double-click it in Finder, or run: open ${APP_BUNDLE}"
