# Blockers

Things an agent cannot resolve alone. Record the exact blocker here instead of
faking a pass.

## Open

### Accessibility permission not granted (2026-08-06)

`Tools/ax-probe` exits with `NOT_TRUSTED`. macOS attributes the request to the
responsible parent process, which for an agent shell in this setup is
`/Applications/Emdash Dev.app`.

**To unblock:** System Settings → Privacy & Security → Accessibility → add and
enable **Emdash Dev**. Then run:

```
swiftc -O -o /tmp/axprobe Tools/ax-probe/main.swift && /tmp/axprobe --front
```

Blocks: kill point 1 in `docs/kill-points.md`, and Task 2 of
`docs/plans/mvp_v1.md`.

## Resolved

(none yet)
