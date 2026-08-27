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

# macOS keys the Accessibility grant to a bundle at a stable location. A bundle that
# lives in .build looks like a different app after every `swift build`, so the real
# install target is /Applications and .build is only the staging area.
INSTALL_DIR="${ANCHR_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/Anchr.app"

MODE="run"
for arg in "$@"; do
    case "$arg" in
        --build-only) MODE="build-only" ;;
        --no-install) MODE="run-from-build" ;;
        *) echo "usage: scripts/run-app.sh [--build-only|--no-install]" >&2; exit 2 ;;
    esac
done

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

# Signing decides whether the Accessibility grant survives a rebuild. macOS keys the
# grant to the code signature, so an ad-hoc signature — whose hash changes on every
# build — makes the grant dead on arrival and forces the user to re-add the app by hand
# every single time. A real identity is stable, so the grant is granted once.
#
# Set ANCHR_SIGN_IDENTITY to override. Ad-hoc stays the fallback so a checkout without
# a certificate still builds.
if [[ -z "${ANCHR_SIGN_IDENTITY:-}" ]]; then
    ANCHR_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -m1 "Developer ID Application" \
        | sed -E 's/.*"(.*)".*/\1/')"
fi

if [[ -n "$ANCHR_SIGN_IDENTITY" ]]; then
    echo "[run-app] signing as $ANCHR_SIGN_IDENTITY"
    codesign --force --sign "$ANCHR_SIGN_IDENTITY" --identifier "$BUNDLE_ID" \
        --options runtime --timestamp=none "$APP_DIR" >/dev/null
else
    echo "[run-app] no Developer ID found; signing ad-hoc (the Accessibility grant will" >&2
    echo "[run-app] not survive rebuilds — see ANCHR_SIGN_IDENTITY)" >&2
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
fi

if [[ "$MODE" == "build-only" ]]; then
    echo "[run-app] built $APP_DIR"
    exit 0
fi

LAUNCH_TARGET="$APP_DIR"
if [[ "$MODE" == "run" ]]; then
    if [[ -w "$INSTALL_DIR" ]]; then
        echo "[run-app] installing to $INSTALLED_APP"
        /bin/rm -rf "$INSTALLED_APP"
        ditto "$APP_DIR" "$INSTALLED_APP"
        LAUNCH_TARGET="$INSTALLED_APP"
    else
        echo "[run-app] $INSTALL_DIR is not writable; running from $APP_DIR" >&2
    fi
fi

echo "[run-app] launching $LAUNCH_TARGET"
open "$LAUNCH_TARGET"
echo "[run-app] running. Menu bar dot, or press option-space. Quit from the menu bar."
