#!/usr/bin/env bash
# Build Anchr and launch it as a real .app bundle.
#
# SwiftPM produces a bare executable. macOS only grants Accessibility, a menu bar
# item and a global hotkey to a bundle with a stable identity, so the bundle is
# assembled here rather than in an Xcode project the plan deliberately avoids.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$REPO_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$REPO_ROOT/.build/swiftpm-module-cache"

CONFIGURATION="${ANCHR_CONFIGURATION:-debug}"
BUNDLE_ID="com.anchr.app"
APP_DIR="$REPO_ROOT/.build/Anchr.app"

echo "[run-app] building"
xcrun swift build --disable-sandbox -c "$CONFIGURATION" --product AnchrApp
BINARY="$(xcrun swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)/AnchrApp"
[[ -x "$BINARY" ]] || { echo "[run-app] no binary at $BINARY" >&2; exit 1; }

# Replacing the executable of a running bundle confuses the Accessibility grant.
pkill -x Anchr 2>/dev/null || true

echo "[run-app] assembling $APP_DIR"
case "$APP_DIR" in
    "$REPO_ROOT"/.build/*.app) /bin/rm -rf "$APP_DIR" ;;
    *) echo "[run-app] refusing to delete $APP_DIR" >&2; exit 1 ;;
esac
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/Anchr"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Anchr</string>
    <key>CFBundleDisplayName</key><string>Anchr</string>
    <key>CFBundleExecutable</key><string>Anchr</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu bar only: no Dock icon, no main window. -->
    <key>LSUIElement</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Anchr reads the text of the window in front to tell whether it matches your current task. It never takes pictures of your screen.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Ad-hoc signing keeps the Accessibility grant stable across rebuilds. It never
# touches the keychain, so it cannot block an unattended run.
echo "[run-app] signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null

if [[ "${1:-}" == "--build-only" ]]; then
    echo "[run-app] built $APP_DIR"
    exit 0
fi

echo "[run-app] launching"
open "$APP_DIR"
echo "[run-app] running. Menu bar dot, or press option-space. Quit from the menu bar."
