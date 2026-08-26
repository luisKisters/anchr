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

# Anchr no longer shells out to anything: the classifier is an HTTPS call.
gate "no subprocess is spawned anywhere" \
    -E '(^|[^A-Za-z])Process[[:space:]]*\(' --include='*.swift' "${SWIFT_PATHS[@]}"

# The key must never reach a log, a fixture, or the repository.
gate "no OpenRouter key literal is committed" \
    -E 'sk-or-v1-[A-Za-z0-9]' --include='*.swift' --include='*.sh' --include='*.md' \
    --include='*.json' --include='*.yml' "${SWIFT_PATHS[@]}" scripts docs fixtures

# Only the transport may reach the network, and only at the one endpoint.
# The pattern targets calls and URLs, not the onboarding text that tells a human
# where to fetch their key.
gate "network calls are confined to OpenRouterClassifier.swift" \
    -E 'URLSession|https?://[a-z.]*openrouter' --include='*.swift' \
    --exclude='OpenRouterClassifier.swift' --exclude='OpenRouterRequest.swift' "${SWIFT_PATHS[@]}"

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

# Ported from NoteTakr: a fixed sleep in a test is a flake waiting to happen.
# A wait that genuinely measures elapsed time carries this trailing comment:
#   // anchr-verify: allow-real-elapsed-time -- <reason>
SWIFT_TEST_PATHS=(AnchrKit/Tests Tests AnchrUITests)
SLEEP_MATCHES=$(
    grep -rnE \
        -e 'Task\.sleep[[:space:]]*\([[:space:]]*(nanoseconds:[[:space:]]*[0-9]|for:[^)]*[0-9]|[0-9])' \
        -e 'Thread\.sleep[[:space:]]*\([[:space:]]*(forTimeInterval:[[:space:]]*)?[0-9]' \
        -e '(^|[^[:alnum:]_.])(sleep|usleep)[[:space:]]*\([[:space:]]*[0-9]' \
        --include='*.swift' "${SWIFT_TEST_PATHS[@]}" 2>/dev/null \
        | grep -vE '//[[:space:]]*anchr-verify: allow-real-elapsed-time[[:space:]]+--[[:space:]]+[^[:space:]]' \
        || true
)
if [[ -n "$SLEEP_MATCHES" ]]; then
    fail "fixed sleeps are banned in tests; wait on a condition instead:"
    echo "$SLEEP_MATCHES" | head -10 | sed 's/^/         /'
else
    pass "no fixed sleeps in tests"
fi

# Unit tests must not reach the real model. Only the opt-in live test may.
gate "Kit tests never name a real host" \
    -E 'https?://[a-zA-Z0-9]' --include='*.swift' AnchrKit/Tests

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

if [[ "${ANCHR_VERIFY_UI:-0}" == "1" ]]; then
    log "== GUI smoke =="
    if "$REPO_ROOT/scripts/test.sh" uismoke; then
        pass "XCUITest UI smoke"
    else
        fail "XCUITest UI smoke"
    fi
else
    log "GUI smoke skipped (set ANCHR_VERIFY_UI=1 to include it; it takes over the screen)"
fi

log "== Summary: $FAILURES failure(s) =="
[[ "$FAILURES" -eq 0 ]] || exit 1
