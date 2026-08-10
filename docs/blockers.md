# Blockers

Things an agent cannot resolve alone. Record the exact blocker here instead of
faking a pass.

## Open

(none)

## Resolved

### Current Accessibility grant and tool sandbox (2026-08-10, resolved same day)

The saved `com.emdash.dev` permission had an old code requirement. It was reset,
then Accessibility was enabled for the current Emdash Dev and Emdash Dev Helper
signatures. The default command sandbox still made `AXIsProcessTrusted()` return
false. Running the live probe outside that sandbox succeeded with status 0:
484 nodes, 192 useful lines and 8 348 characters from Emdash Dev.

### Accessibility permission not granted (2026-08-06, resolved same day)

`Tools/ax-probe` exited with `NOT_TRUSTED`. macOS attributes the request to the
responsible parent process, which for an agent shell in this setup is
`/Applications/Emdash Dev.app`. The user enabled it in System Settings →
Privacy & Security → Accessibility. Measurements in `docs/ax-coverage.md`.
