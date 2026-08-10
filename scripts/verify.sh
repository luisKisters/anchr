#!/usr/bin/env bash
# Fast verification gate for Anchr. Run after every change.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$REPO_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$REPO_ROOT/.build/swiftpm-module-cache"

FAILURES=0

log()  { echo "[verify] $*"; }
pass() { echo "[verify] PASS: $*"; }
fail() { echo "[verify] FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# gate <description> <grep arguments...>
# A gate is a hard failure when grep finds at least one match.
gate() {
    local desc="$1"; shift
    local matches
    matches=$(grep -rn "$@" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        local count
        count=$(echo "$matches" | wc -l | tr -d ' ')
        fail "$desc ($count occurrence(s)):"
        echo "$matches" | head -10 | sed 's/^/         /'
    else
        pass "$desc"
    fi
}

SWIFT_PATHS=(AnchrKit AnchrCore AnchrApp Tools Tests)

log "== Hard architecture gates =="

gate "Process is confined to CodexClassifier.swift" \
    -E 'Process[[:space:]]*\(' --include='*.swift' \
    --exclude='CodexClassifier.swift' "${SWIFT_PATHS[@]}"

gate "accessibility elements are confined to AXSnapshot.swift and FocusContext.swift" \
    'AXUIElement' --include='*.swift' \
    --exclude='AXSnapshot.swift' --exclude='FocusContext.swift' "${SWIFT_PATHS[@]}"

gate "no screen-capture API is present" \
    -E 'screencapture|CGWindowListCreateImage|SCStream' --include='*.swift' \
    "${SWIFT_PATHS[@]}"

gate "AnchrApp has no raw colour literal" \
    -E '#colorLiteral|(^|[^A-Za-z])(Color|NSColor)[[:space:]]*\(' \
    --include='*.swift' AnchrApp

gate "AnchrApp has no raw system font" \
    -F '.font(.system(' --include='*.swift' AnchrApp

log "== AnchrKit tests =="
if (cd AnchrKit && xcrun swift test --disable-sandbox 2>&1 | tail -12); then
    pass "AnchrKit swift test"
else
    fail "AnchrKit swift test"
fi

log "== AnchrCore tests =="
if (xcrun swift test --disable-sandbox 2>&1 | tail -16); then
    pass "AnchrCore swift test"
else
    fail "AnchrCore swift test"
fi

log "== Summary: $FAILURES failure(s) =="
[[ "$FAILURES" -eq 0 ]] || exit 1
