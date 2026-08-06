# Blockers

Things an agent cannot resolve alone. Record the exact blocker here instead of
faking a pass.

## Open

(none)

## Resolved

### Accessibility permission not granted (2026-08-06, resolved same day)

`Tools/ax-probe` exited with `NOT_TRUSTED`. macOS attributes the request to the
responsible parent process, which for an agent shell in this setup is
`/Applications/Emdash Dev.app`. The user enabled it in System Settings →
Privacy & Security → Accessibility. Measurements in `docs/ax-coverage.md`.
