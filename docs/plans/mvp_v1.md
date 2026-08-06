# Anchr V1 — Build Plan

## Overview

Anchr is a native macOS menu bar app. It holds one to-do list at a time, reads
which app and window is in front, checks that against the current anchor (the
task you said you are on), and opens a full-screen question when you drift.
The one move that defines the product: instead of defending the task, it offers
to make it smaller, and writes that smaller step into the list as a child item.

V1 ships when the owner uses it for a week and does not want to switch it off.
Rollout is local only: a signed-nothing debug build run from Xcode/SPM. No CI,
no release, no distribution in V1.

## Context

- Repo is empty of code. `BRAINSTORM.md` holds the idea and the scope discipline.
  `design/mockups/v2/interactive.html` is a working HTML prototype of every
  screen and every key binding, and is the visual and interaction specification.
  `design/mockups/v2/index.html` holds the same states statically.
- Toolchain present on the machine: Swift 6.3.3, `xcodebuild`, Node 24+,
  `codex-cli 0.144.6` at `~/.local/bin/codex`, authenticated with the ChatGPT
  subscription (OAuth tokens in `~/.codex/auth.json`, no API key).
- Verified by hand before this plan: `codex exec --ephemeral --skip-git-repo-check
  -s read-only -c model_reasoning_effort=low --output-schema schema.json -o out.json
  "<prompt>"` returns a clean JSON object. Round trip 6.1 s.
- `~/code/projects/notetakr` is the reference project. Copy its `scripts/verify.sh`
  `gate()` helper and its `Tools/design/cdp.mjs` + `mockup-shot.mjs` design-snapshot
  tooling rather than inventing new ones.
- The HTML prototype was driven headlessly through `cdp.mjs` during design, so the
  same technique is available to verify the paste normalizer's expected output.

## Product Decisions

Locked. Do not reopen these while executing.

1. **One active list.** Anchr only ever checks against the active list. Detecting
   "you are on another project" is post-V1.
2. **Text only. No screenshots in V1.** The app must never contain a capture API.
   When the accessibility text is too thin to judge, the verdict is `unclear`.
3. **No model-proposed check-off in V1.** The model never edits the list. Only the
   user's answer to an intervention writes to it.
4. **No wiki links, no Obsidian format.** Pasted `[[Foo|Bar]]` is flattened to
   `Bar` on import.
5. **One fixed Markdown format**, written by Anchr and never negotiated:
   `- [ ]` / `- [x]`, two spaces per depth level, one item per line.
6. **Onboarding exists and is three steps:** grant Accessibility, confirm `codex`
   works, paste the first plan. Nothing else.
7. **Meetings, breaks and reading get no special handling.** The model judges them
   from the anchor plus `context.md`. No calendar, no idle classifier, no app
   allowlist.
8. **No settings screen, no history, no statistics, no voice, no modes, no app
   blocking, no branch collapsing, no item reordering.**
9. **Design:** black background, white text, two greys, no accent colour, no emoji,
   no icons except the checkbox, no explanation labels. Sans for what a human
   wrote, mono for what the machine measured.

## Architecture Decisions

- **Swift Package, no Xcode project.** `swift build` and `swift test` are the
  build. An `.app` bundle is produced by a script only when the app must run.
- **`AnchrKit` (Foundation only, no AppKit) holds every decision:** Markdown parse
  and serialize, paste normalization, indent operations, the check scheduler, the
  intervention policy, the prompt and JSON Schema as data. All unit-testable with
  no screen and no permission. **`AnchrCore` (macOS only) holds every side
  effect:** accessibility reads, process spawn, the loop's clock.
- **The one seam:** `protocol DriftClassifier { func classify(_ observation:
  Observation) async throws -> Verdict }`. `CodexClassifier` spawns the real CLI;
  `ScriptedClassifier` replays a fixture file. The second makes the whole loop
  testable with no network and no screen.
- **The anchor is an index into the list**, not a separate object. "Go smaller"
  inserts a child item under the anchor and moves the anchor to it.
- **Accessibility yield, measured — see `docs/ax-coverage.md`.** Set
  `AXManualAccessibility` and `AXEnhancedUserInterface` on the app element when it
  becomes frontmost, then read the tree on the **next** check, never in the same
  call: Electron apps build the tree asynchronously and returned 91 chars on the
  first read and 2043 one second later. Chromium browsers expose no page content
  at all, no matter which flag is set; the tab title is the observation there, and
  that was verified to be enough. Safari exposes the whole page. **No per-app
  special cases beyond the flags and the second read.**
- **Observation tiers:** free layer is frontmost app plus focused window title via
  `NSWorkspace` notifications and an `AXObserver` — push, no polling. Model layer
  is the accessibility text snapshot, capped at 3000 characters.
- **Check timing:** app/title change → wait 8 s → check. Otherwise every 90 s.
  At most one model call per 45 s. Pause on 3 min without input, on locked screen,
  and while Anchr's own overlay is in front.
- **Intervention policy:** two consecutive `off_task` → intervene. `unclear` never
  intervenes alone. 10 minutes of silence after every intervention. Ceiling of 4
  per hour.

## Models

- Orchestrator: Opus 5, high effort.
- Subagents: Opus 5, low effort.
- Delegated implementation: `codex exec` with gpt-5.6-sol at medium effort.

## Verification Contract

The agent must never claim a slice works because the code compiles.

- **Every Kit task is proven by `swift test` in `AnchrKit`** with table-driven
  cases, no mocks of Foundation.
- **The Markdown round-trip is the load-bearing test.** Parse a real pasted plan,
  serialize it, assert byte equality. Then apply one edit and assert only that one
  line changed. Fixtures live in `fixtures/lists/`.
- **The loop is proven headless** by `scripts/e2e-smoke.sh`: a scripted verdict
  sequence driven through the real scheduler, policy and store with
  `ScriptedClassifier` and a fake focus source. It asserts exactly one
  intervention fired and exactly one child item was appended to `list.md`.
- **UI behaviour is proven in Kit, not in SwiftUI.** Every key press goes through
  `AnchrKit/ListEditor.swift`, a pure reducer of `(state, key) -> state`. The
  SwiftUI views own no editing logic; they render the reducer's state and forward
  key events. So navigation, editing, indent, delete and anchor changes are
  table-tested with no screen.
- **UI appearance is proven by design snapshots**, rendered in-process to PNG by a
  `--design-snapshot <state>` launch flag. Baselines are **self-baselined and
  approved once by the user**: the first run writes the PNG, the user looks at it
  next to `design/mockups/v2/interactive.html` and approves, and from then on the
  pixel diff catches regressions. The HTML prototype is the reference a human or
  agent compares against — it is never diffed against the app automatically,
  because SwiftUI and a browser will never rasterize identically.
- **Anything needing the real Accessibility permission or the real `codex` CLI is
  opt-in and best effort.** `ANCHR_LIVE_CODEX=1` and `ANCHR_LIVE_AX=1` gate those
  tests. If the permission is missing, the task must record the exact blocker in
  `docs/blockers.md` and ask the user to grant it in System Settings — never
  fake a pass and never try to grant it by automation.
- **`scripts/verify.sh` must be green before any task is called done.** Its grep
  gates are hard failures, not warnings.

## Validation Commands

- `scripts/verify.sh`
- `cd AnchrKit && swift test`
- `swift build`
- `scripts/e2e-smoke.sh`
- `python3 .claude/skills/ralphex-plan-writer/scripts/check_plan_format.py docs/plans/mvp_v1.md`

## Phase 1: Harness Before Features

### Task 1: Skeleton, Gates, Green Empty Test Run

- [ ] Create the Swift package: `AnchrKit` (Foundation only), `AnchrCore` (macOS),
      `AnchrApp` (SwiftUI executable), and a test target per library.
- [ ] Port `scripts/verify.sh` from `~/code/projects/notetakr/scripts/verify.sh`,
      keeping the `gate()` helper shape. Gates, all severity `fail`:
      no `Process(` outside `CodexClassifier.swift`; no `AXUIElement` outside
      `AXSnapshot.swift` and `FocusContext.swift`; no `screencapture`,
      `CGWindowListCreateImage` or `SCStream` anywhere; no colour literal or
      `.font(.system(` under `AnchrApp/`.
- [ ] Add one placeholder test per target so the suites are real.
- [ ] Write `docs/blockers.md` with an empty "Blockers" heading, used by later
      tasks to record permission problems.
- [ ] Run `scripts/verify.sh` and `swift build`. Both must pass.

### Task 2: Accessibility Coverage Probe

This is the experiment that decides whether the text-only design holds. It ships
as a small tool, not as throwaway code.

- [ ] Add `Tools/ax-probe`, a tiny executable target that takes a bundle ID or
      `--front`, sets `AXManualAccessibility = true` on the app element, walks the
      focused window's `AXUIElement` tree, and prints the flattened text plus a
      character count.
- [ ] Reuse this walker from `AnchrCore/AXSnapshot.swift` later — the probe must
      call the same function, not a copy.
- [ ] The measurement is already done — see `docs/ax-coverage.md`. Re-run the
      probe only to confirm the numbers still hold after the walker moves into
      `AXSnapshot.swift`, and update the table if they changed.
- [ ] Implement the second-read rule proven there: set the flags on app
      activation, read the tree on the next check.
- [ ] If the Accessibility permission is not granted, stop, write the exact
      blocker to `docs/blockers.md`, and ask the user to grant it in
      System Settings → Privacy & Security → Accessibility. Do not fake results.
- [ ] Run `scripts/verify.sh`.

## Phase 2: The List

### Task 3: Markdown Parse, Serialize, Round-Trip

- [ ] Implement `AnchrKit/TodoList.swift`: a flat array of `Item { text, depth,
      done }`, parsed from and serialized to the fixed format (`- [ ]` / `- [x]`,
      two spaces per depth level).
- [ ] Clamp depth on parse so a child can never be more than one level deeper than
      its predecessor.
- [ ] Add `fixtures/lists/real-day.md`, taken from the example list in the design
      prototype's seed data.
- [ ] Tests: byte-stable round trip of the fixture; single-line edit changes
      exactly one line; empty file, blank lines and a single item all survive.
- [ ] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 4: Paste Normalization

- [ ] Implement `TodoList.normalize(pasted:)`: detect the indent unit (tabs count
      as one level), strip `-`, `*`, `+`, `•`, `–`, `1.`, `1)`, parse `[ ]` / `[x]`,
      turn `#`-headings into depth-0 items, strip `**bold**`, flatten
      `[[Foo|Bar]]` to `Bar`, drop blank lines.
- [ ] Table-test it against the JavaScript prototype's `normalize()` in
      `design/mockups/v2/interactive.html`, which is the reference behaviour. At
      minimum the mixed-format German example from the prototype run must produce
      the same six items with the same depths and the same one checked item.
- [ ] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 5: Store, Contexts, State

- [ ] Implement `AnchrKit/ListStore.swift`: lists under
      `~/Library/Application Support/Anchr/lists/<slug>/list.md` plus
      `context.md`, and `state.json` holding the active list slug, the anchor
      index and the snooze deadline.
- [ ] Implement `AnchrKit/Anchor.swift`: the anchor index plus its parent chain,
      and `goSmaller(text:)` which inserts a child under the anchor and moves the
      anchor to it.
- [ ] Tests: create, list, switch, delete; `goSmaller` places the item at the right
      index and depth even when the anchor already has children; a corrupt
      `state.json` falls back to the first list instead of crashing.
- [ ] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

## Phase 3: The Judgement

### Task 6: Scheduler and Policy

- [ ] Implement `AnchrKit/CheckScheduler.swift` as a pure function of
      `(events, now, lastCall)` → `shouldCheck`: 8 s debounce after a focus
      signature change, 90 s heartbeat, 45 s minimum gap, paused on idle over
      3 min, on a locked screen, and while Anchr is frontmost.
- [ ] Implement `AnchrKit/InterventionPolicy.swift` as a pure function of the
      verdict history: two consecutive `off_task` intervene, `unclear` never
      intervenes alone, 10 min silence after an intervention, 4 per hour ceiling.
- [ ] Table-test both over explicit event and verdict sequences with an injected
      clock. Include the sequence that proves the nag ceiling holds when every
      verdict is `off_task` for an hour.
- [ ] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 7: The Codex Seam

- [ ] Implement `AnchrKit/Verdict.swift` and `AnchrKit/ObservationPrompt.swift`:
      the verdict struct (`verdict`, `evidence`, `smaller_step`), its JSON Schema
      and the prompt text, all as data in Kit.
- [ ] Implement `AnchrCore/CodexClassifier.swift`: spawn `codex exec --ephemeral
      --skip-git-repo-check -s read-only -c model_reasoning_effort=low
      --output-schema <schema> -o <out>`, feed the anchor, the parent chain,
      `context.md`, the open items and the observation text; parse and validate.
- [ ] Implement `ScriptedClassifier` in the test support target: verdicts replayed
      in order from a fixture.
- [ ] Tests: decoding accepts a valid object and rejects a missing `smaller_step`;
      a non-zero exit and a timeout both surface as thrown errors, not as
      `on_task`. Add `CodexClassifierLive`, gated by `ANCHR_LIVE_CODEX=1`, that
      sends one fixture observation through the real CLI and validates the JSON.
- [ ] Run `cd AnchrKit && swift test`, `swift build`, `scripts/verify.sh`.

## Phase 4: Watching

### Task 8: Focus Context and Accessibility Snapshot

- [ ] Implement `AnchrCore/FocusContext.swift`: frontmost bundle ID and focused
      window title from `NSWorkspace` notifications and an `AXObserver`. Push
      only, no polling loop.
- [ ] Implement `AnchrCore/AXSnapshot.swift` around the walker from Task 2: set
      `AXManualAccessibility`, collect role/title/value/description, drop empty
      and decorative nodes, cap at 3000 characters, and report the useful
      character count so the caller can fall back to the title alone.
- [ ] Add a permission check that reports "not granted" without prompting in a
      loop, plus the onboarding entry point that opens the right System Settings
      pane.
- [ ] Tests: the flattener is a pure function over a fixture tree structure and is
      unit-tested without a live app. Add `AXSnapshotLive`, gated by
      `ANCHR_LIVE_AX=1`, that snapshots the frontmost app and asserts a non-empty
      result.
- [ ] Run `swift build` and `scripts/verify.sh`.

### Task 9: The Loop, Proven Headless

- [ ] Implement `AnchrCore/ObservationLoop.swift`: focus events in, scheduler
      decides, snapshot taken, classifier called, policy consulted, intervention
      requested through a callback. It must depend on protocols for the clock, the
      focus source and the classifier.
- [ ] Write `scripts/e2e-smoke.sh` running `ObservationLoopE2ETests`: verdicts
      `on_task, off_task, off_task` through the real scheduler, policy and store
      with a fake focus source and `ScriptedClassifier`. Assert exactly one
      intervention fired, exactly one child item was appended to `list.md`, and
      the anchor moved to it.
- [ ] Assert in the same test that no file was written outside the temporary
      Application Support directory the test created.
- [ ] Run `scripts/e2e-smoke.sh` and `scripts/verify.sh`.

## Phase 5: The App

### Task 10: Overlay, List, Keys

- [ ] Implement the menu bar item (dot, pause, quit) and `OverlayWindow`: a
      borderless full-screen window over all spaces, blurred backdrop, opened by
      the ⌥Space global hotkey.
- [ ] Implement `ListView` matching the prototype: header, anchor bar, the tree
      with indent, selection, done state, and the key hint row.
- [ ] Implement `AnchrKit/ListEditor.swift` first: a pure reducer of
      `(state, key) -> state` covering `↑↓`/`WS` move, `space` done, `↵` edit,
      `⇥`/`⇧⇥` indent and unindent with children following, `N` new, `A` set
      anchor, `esc` close, and "saving an empty item deletes it". The SwiftUI view
      must contain no editing logic — it renders the state and forwards keys.
- [ ] Table-test the reducer over key sequences, including: unindent at depth 0 is
      a no-op, indent deeper than predecessor + 1 is a no-op, deleting the last
      item leaves a valid selection, and a parent's children follow its indent.
- [ ] Add the `--design-snapshot <state>` launch flag that renders one named state
      to PNG in process, and write the first `overlay/list` baseline.
- [ ] Show that baseline to the user next to the prototype for approval, then run
      `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 11: Create From Paste, and the Switcher

- [ ] Implement `CreateListView`: name field, one paste box, an optional
      `+ CONTEXT` box, `⌘↵` creates. It calls `TodoList.normalize` from Task 4 and
      nothing else.
- [ ] Implement the `⌘K` switcher: list names with open counts and whether a
      context file exists; `↵` opens, `C` edits context, `N` opens create,
      `esc` back.
- [ ] Test in Kit that creating a list from a pasted plan produces the expected
      `list.md` bytes; test in the app layer only what the snapshots cover.
- [ ] Add design snapshots `overlay/create` and `overlay/switcher`, get the
      baselines approved once, then run `scripts/verify.sh`.

### Task 12: The Intervention

- [ ] Implement `InterventionView` on the same window with the heavier veil: the
      detected line in mono, the anchor echo, the question, three answers bound to
      `1` `2` `3`, no `esc` and no `⌘W`, and the 420 ms settle-from-the-top
      animation.
- [ ] "Go smaller" pre-fills the model's `smaller_step`, `↵` writes it as a child
      item under the anchor and moves the anchor there. "New anchor" asks what you
      are doing instead and writes that as a sibling. "Back to it" only snoozes.
- [ ] Add design snapshots `intervention/ask` and `intervention/smaller`, get the
      baselines approved once, then run `scripts/e2e-smoke.sh` and
      `scripts/verify.sh`.

### Task 13: Onboarding

- [ ] Implement the three-step first run: grant Accessibility (one sentence
      explaining that Anchr reads the text of the front window and takes no
      pictures, plus a button that opens the right System Settings pane); confirm
      `codex` is installed and logged in by running one real classification; paste
      the first plan through `CreateListView`.
- [ ] If `codex` is missing or unauthenticated, say exactly what to run. Do not
      build a fallback path.
- [ ] Add design snapshot `onboarding/permission`, get the baseline approved once,
      then run `scripts/verify.sh`.

## Phase 6: Does It Actually Work

### Task 14: The Verdict Corpus

- [ ] Collect about 30 real accessibility snapshots from work sessions into
      `fixtures/corpus/`, each with the anchor, the context file and the expected
      verdict. Include the hard ones: documentation that reads like YouTube, a
      YouTube video that genuinely is the task, a terminal that could be anything,
      a meeting, and a break.
- [ ] Add `VerdictCorpusTests`, gated by `ANCHR_LIVE_CODEX=1`, that scores the
      real classifier against the corpus and prints an accuracy number plus every
      disagreement.
- [ ] Write the number and the failure patterns into `docs/ax-coverage.md`. This is
      the go/no-go for the concept; do not tune the prompt more than twice before
      reporting the number to the user.
- [ ] Run `scripts/verify.sh`.

## Phase 7: Review

### Task 15: Review Pass

- [ ] Delete code that is bad, not best practice, or was never asked for. Check
      specifically for: a second Markdown writer, a second AX walker, any capture
      or screenshot API, any settings surface, and any abstraction with one
      implementation that is not the `DriftClassifier` seam.
- [ ] Cut redundant tests. Keep one test per acceptance criterion; the round-trip,
      the normalizer table, the policy table, the scheduler table and the loop
      smoke test are the ones that must survive.
- [ ] Confirm every `verify.sh` gate is severity `fail` and none were downgraded to
      pass a task.
- [ ] Run `scripts/verify.sh`, `cd AnchrKit && swift test`, `scripts/e2e-smoke.sh`.

## Phase 8: End-to-End

### Task 16: Full Product Run

- [ ] Build and launch the real app. Grant Accessibility if asked. Paste a real
      plan, add context, set an anchor.
- [ ] Work normally for at least 20 minutes with the loop live against the real
      `codex` CLI, then deliberately drift to an unrelated site and confirm an
      intervention appears within two minutes.
- [ ] Answer "go smaller" and confirm the child item appears in `list.md` on disk
      with correct indentation and that the anchor moved.
- [ ] Confirm no file appeared anywhere outside
      `~/Library/Application Support/Anchr/` and that no image file was written at
      any point.
- [ ] Fix only what this run breaks. Record anything else in `ideas.md`.
- [ ] Run `scripts/verify.sh` and `scripts/e2e-smoke.sh` one last time.
