#!/usr/bin/env bash
# Regenerate Anchr.xcodeproj from project.yml.
#
# The project is generated, never hand-edited: the Swift package stays the build of
# record and the project exists only to host the XCUITest target.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "[generate-project] xcodegen is missing. Install it: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate --spec project.yml --project .
echo "[generate-project] wrote Anchr.xcodeproj"
