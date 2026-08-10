# Handoff — Anchr, 2026-08-06

State: **planning and de-risking are done. No app code exists yet.**
Next action: Task 1 of `docs/plans/mvp_v1.md`.

---

## What Anchr is

A native macOS menu bar app. It holds one to-do list at a time, reads which app
and window is in front through the Accessibility API, checks that against the
current anchor (the task you said you are on), and opens a full-screen question
when you drift. Instead of defending the task, it offers to make the task
smaller and writes that smaller step into the list as a child item.

It shells out to `codex exec`, so the ChatGPT subscription pays for the model and
V1 costs nothing per day.

## Read these, in this order

| File | What it is |
|---|---|
| `BRAINSTORM.md` | The idea, the why, and the scope discipline |
| `docs/plans/mvp_v1.md` | The executable plan. 16 tasks, Ralphex/executr format |
| `docs/kill-points.md` | The two experiments that could have killed the concept |
| `docs/ax-coverage.md` | Accessibility text yield measured across 13 real apps |
| `design/mockups/v2/interactive.html` | The specification. A working prototype — use it, do not read it |

The prototype wins over any written rule it contradicts.

## Both kill points passed

**Does the model judge well enough?** 4 / 6 on hand-written observations through
the real `codex exec`, 5–9 s per verdict. The two cases that could have killed
it both passed: Apple documentation that reads like drift was called `on_task`,
and a YouTube video that genuinely was the task was called `on_task`. Content
decided, not the app name. Both misses are recorded, including the one that
leans toward nagging.

**Do real apps give up enough text?** Yes. Safari gives the whole page
(29 210 chars). Electron apps give theirs. Chromium browsers give **only the tab
title** — which was then tested directly and found sufficient, one drift case and
one on-task case, both correct.

Reproduce both with `Tools/ax-probe/main.swift` and `Tools/verdict-probe/run.sh`.

## Three findings that constrain the implementation

1. **Chromium browsers expose no page content**, no matter which accessibility
   flag is set. Arc's large character count is its own sidebar, not the page.
   The tab title is the observation there. Accepted, verified sufficient.
2. **Electron apps need two reads.** Obsidian returned 91 chars on the first
   probe and 2 043 one second later. Set `AXManualAccessibility` and
   `AXEnhancedUserInterface` when an app becomes frontmost, read the tree on the
   **next** check, never in the same call.
3. **Editors expose their shell, not their text.** Enough to know which project
   you are in, not what you are typing.

## Locked decisions — do not reopen

One active list. Text only, no screenshots, so the app needs Accessibility
permission and never Screen Recording. The model never edits the list. One fixed
Markdown format with paste normalization on import. Three-step onboarding.
Meetings and breaks get no special handling — the model judges them from the
anchor and `context.md`. Black and white, no accent colour, no emoji.

Cut and staying cut: voice, modes, app blocking, learning, Obsidian integration,
statistics, branch collapsing, item reordering, model-proposed check-offs.

## Verification layers

- `scripts/verify.sh` — grep gates as hard failures, ported from NoteTakr's
  `gate()` helper. One of them forbids any capture API anywhere in the tree, so
  "no screenshots" is enforced, not remembered.
- `AnchrKit` holds every decision and is Foundation-only, so the Markdown
  round-trip, the paste normalizer, the check scheduler, the intervention policy
  and the key-handling reducer are all table-tested with no screen.
- `scripts/e2e-smoke.sh` drives a scripted verdict sequence through the real
  loop and asserts one intervention and one appended child item.
- Design snapshots are self-baselined and approved once, then diffed. They are
  never diffed against the HTML prototype — a browser and SwiftUI never
  rasterize identically.
- Real permissions and the real CLI are opt-in: `ANCHR_LIVE_AX=1`,
  `ANCHR_LIVE_CODEX=1`. Missing permission goes to `docs/blockers.md`, never a
  faked pass.

## Environment notes

- Accessibility permission is granted to `Emdash Dev.app`, which is the
  responsible parent process for an agent shell here. Without it `Tools/ax-probe`
  exits `NOT_TRUSTED`.
- `codex-cli 0.144.6` at `~/.local/bin/codex`, ChatGPT-subscription auth.
- Swift 6.3.3. Reference project for tooling: `~/code/projects/notetakr`.

## History was rewritten

Real company and person names from an example to-do list were replaced with
fictional ones and the public history was force-pushed twice. If you have an old
clone, delete it and clone again — do not merge it back. Old commit SHAs may
still resolve on GitHub until it garbage-collects; if that matters, the only
certain fix is deleting and recreating the repository.

## Next step

Task 1: the Swift package skeleton, `scripts/verify.sh` with its four grep gates,
and one green test run. Nothing else starts before that is green.
