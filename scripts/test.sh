#!/usr/bin/env bash
# Anchr test runner.
#
#   scripts/test.sh unit      headless: Kit + Core. Default. Never touches the screen.
#   scripts/test.sh uismoke   XCUITest against the real app. Takes over the screen.
#   scripts/test.sh all       both
#
# Split on purpose: the headless suite is what a gate runs, and the GUI suite is what
# proves SwiftUI is actually wired to the reducer. Only the GUI suite grabs the
# keyboard, so it is never something you run by accident.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$REPO_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$REPO_ROOT/.build/swiftpm-module-cache"

MODE="${1:-unit}"
STATUS=0

run_unit() {
    echo "[test] headless: AnchrKit"
    (cd AnchrKit && xcrun swift test --disable-sandbox) || STATUS=1
    echo "[test] headless: AnchrCore"
    xcrun swift test --disable-sandbox || STATUS=1
}

run_uismoke() {
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "[test] xcodegen is missing; cannot generate the XCUITest project." >&2
        echo "[test] install it with: brew install xcodegen" >&2
        return 1
    fi
    "$REPO_ROOT/scripts/generate-project.sh" >/dev/null

    # The runner cannot clean up after itself: it is sandboxed and the fixtures live
    # outside its container. Sweeping here keeps /private/tmp from filling up.
    find /private/tmp -maxdepth 1 -name 'AnchrUITests-*' -type d -mmin +60 \
        -exec /bin/rm -rf {} + 2>/dev/null

    echo "[test] GUI: the app will control the screen for about a minute"
    xcrun xcodebuild test \
        -project Anchr.xcodeproj \
        -scheme Anchr \
        -destination "platform=macOS" \
        -derivedDataPath "$REPO_ROOT/.build/xcode" \
        -testPlan UISmoke \
        -test-timeouts-enabled YES \
        -quiet || STATUS=1
}

case "$MODE" in
    unit) run_unit ;;
    uismoke) run_uismoke ;;
    all) run_unit; run_uismoke ;;
    *)
        echo "usage: scripts/test.sh [unit|uismoke|all]" >&2
        exit 2
        ;;
esac

if [[ $STATUS -eq 0 ]]; then
    echo "[test] green"
else
    echo "[test] FAILED"
fi
exit $STATUS
