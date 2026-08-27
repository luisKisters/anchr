# Blockers

Things an agent cannot resolve alone. Record the exact blocker here instead of
faking a pass.

## Open

(none)

## Resolved

### Codex rejected every model, so no classification worked (2026-08-26, resolved same day)

`codex exec` inherited `model = "gpt-5.6-sol"` from the user's global
`~/.codex/config.toml`. This ChatGPT account cannot use that model, so every call
failed with `400 invalid_request_error: not supported when using Codex with a
ChatGPT account`. `CodexClassifier` passed no `-m`, so a setting Anchr does not
own decided whether the judgement layer worked at all.

Fixed by pinning the model in `CodexClassifier` (`-m`, default `gpt-5.6-terra`,
overridable with `ANCHR_CODEX_MODEL`). The account's usable models come from
`~/.codex/models_cache.json`: `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`,
`gpt-5.4-mini`. Round trip with `gpt-5.6-terra` is 6 s, matching the original
kill-point measurement. The same call now also passes `-c notify=[]`, because the
global config runs a GUI notifier on every turn and Anchr classifies every
45-90 s.

`scripts/preflight.sh` checks this with a real round trip and auto-selects a
working model, so it cannot silently break a run again.

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
