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

- Phases 1 to 4 are built and green; Phase 5 is in progress. `BRAINSTORM.md` holds
  the idea and the scope discipline.
  `design/mockups/v2/interactive.html` is a working HTML prototype of every
  screen and every key binding, and is the visual and interaction specification.
  `design/mockups/v2/index.html` holds the same states statically.
- Toolchain present on the machine: Swift 6.3.3, full Xcode, `xcodegen` 2.46,
  Node 24+. There is **no ChatGPT subscription and no working `codex` CLI**, which
  is why the judgement layer is an OpenRouter HTTPS call and the build is done by
  Claude agents.
- Verified by hand: one `POST https://openrouter.ai/api/v1/chat/completions` with
  `response_format: json_schema, strict: true` returns a clean verdict object.
  Round trip about 3 s with `openai/gpt-5.6-luna` at low reasoning — faster than the
  `codex exec` path it replaced.
- `~/code/projects/notetakr` is the reference project, and it is a macOS app with
  the same shape. Copy its `scripts/verify.sh` `gate()` helper, its
  `NoteTakrUITestCase` XCUITest boundary, its `.xctestplan` split and its
  `scripts/test.sh` mode switch rather than inventing new ones.
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
6. **Onboarding exists and is three steps:** grant Accessibility, paste an
   OpenRouter API key and prove it with one real call, paste the first plan.
   Nothing else.
7. **Meetings, breaks and reading get no special handling.** The model judges them
   from the anchor plus `context.md`. No calendar, no idle classifier, no app
   allowlist.
8. **No settings screen, no history, no statistics, no voice, no modes, no app
   blocking, no branch collapsing, no item reordering.**
9. **Design:** black background, white text, two greys, no accent colour, no emoji,
   no icons except the checkbox, no explanation labels. Sans for what a human
   wrote, mono for what the machine measured.

## Architecture Decisions

- **The Swift package is the build of record.** `swift build` and `swift test`
  compile everything. `Anchr.xcodeproj` is *generated* from `project.yml` by
  `scripts/generate-project.sh` (XcodeGen) and exists for one reason: XCUITest
  targets cannot live in a Swift package. It consumes the package's products, so
  the two can never drift, and it is never hand-edited. `scripts/run-app.sh`
  assembles the `.app` bundle when the app must actually run.
- **`AnchrKit` (Foundation only, no AppKit) holds every decision:** Markdown parse
  and serialize, paste normalization, indent operations, the check scheduler, the
  intervention policy, the prompt and JSON Schema as data. All unit-testable with
  no screen and no permission. **`AnchrCore` (macOS only) holds every side
  effect:** accessibility reads, process spawn, the loop's clock.
- **The one seam:** `protocol DriftClassifier { func classify(_ observation:
  Observation) async throws -> Verdict }`. `OpenRouterClassifier` makes the real
  HTTPS call; `ScriptedClassifier` replays a fixture file. The second makes the
  whole loop testable with no network and no screen.
- **Anchr spawns no processes.** The classifier is an HTTPS request, so there is no
  CLI to find, no login to inherit and no subprocess to sandbox. `verify.sh` gates
  `Process(` to zero occurrences in the whole tree.
- **The request lives in Kit, the socket lives in Core.**
  `AnchrKit/OpenRouterRequest.swift` owns the body, the strict JSON schema and the
  decoding, so the wire format is table-tested with no network.
  `AnchrCore/OpenRouterClassifier.swift` owns only `URLSession`. A `verify.sh` gate
  keeps `URLSession` out of every other file.
- **The API key never touches the repository.** It is read from
  `OPENROUTER_API_KEY`, else from `~/Library/Application Support/Anchr/openrouter-key`
  (0600, written by onboarding). Not the Keychain in V1: the app is ad-hoc signed,
  so its identity changes on every rebuild and macOS would raise a keychain dialog
  mid-session. A `verify.sh` gate fails on any `sk-or-` literal in the tree.
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

Two different things, do not confuse them.

**The model Anchr ships with** — judges one window, hundreds of times a day:

- OpenRouter, `openai/gpt-5.6-luna` with `reasoning.effort: low`, `temperature: 0`,
  strict structured output. Measured: ~3 s and $0.0003 a check, against 11 s for the
  same verdict at `medium`.
- Pinned in `AnchrKit/OpenRouterRequest.swift`, overridable with
  `ANCHR_OPENROUTER_MODEL`. Never read from a config file Anchr does not own —
  that failure mode already cost a night once.
- Cost at Anchr's rate (one call per 45-90 s, 3000 characters of context) is a few
  cents a day. The key is a real spend, so it lives in 1Password
  ("Anchr OpenRouter API Key") and reaches the app through onboarding.

**The models that build Anchr** — Claude agents, not Codex:

- Orchestrator: Opus 5, high effort.
- Subagents: Opus 5, low effort.
- Implementation is done by Claude agents in this repository. There is no Codex
  step anywhere in the build, and no `codex exec` anywhere in the product.

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
- **Key handling is proven in Kit; the wiring is proven by XCUITest.** Every key
  press goes through `AnchrKit/ListEditor.swift`, a pure reducer of
  `(state, key) -> state`, table-tested with no screen. That proves the rules but
  not that SwiftUI is actually bound to them, so `AnchrUITests` drives the real app
  with real key presses through XCUITest, after NoteTakr's `NoteTakrUITestCase`.
  This is not belt and braces: the first GUI run found that the borderless overlay
  window answered `false` to `canBecomeKey`, so every binding in the product was
  dead. No unit test over a reducer can see that.
- **The GUI suite never touches your real list.** `AnchrUITestCase` gives each run
  its own Application Support root under `/private/tmp` and passes it through
  `ANCHR_E2E_APP_SUPPORT_ROOT`. The app writes the fixture itself, because the
  XCUITest runner is sandboxed and can name a path outside its container but never
  create one. For the same reason the GUI cases assert what is on screen; the bytes
  in `list.md` are proven headlessly by `ObservationLoopE2ETests` and the Kit
  round-trip.
- **The suites are split by what they take over.** `scripts/test.sh unit` is
  headless and is what a gate runs. `scripts/test.sh uismoke` regenerates the
  project and runs `TestPlans/UISmoke.xctestplan`, which controls the screen for
  about a minute. `verify.sh` includes it only when `ANCHR_VERIFY_UI=1`.
- **Two test-hygiene gates, ported from NoteTakr.** No fixed sleep in any test file
  (wait on a condition, or carry
  `// anchr-verify: allow-real-elapsed-time -- <reason>`), and no real host named in
  a Kit test.
- **UI appearance is proven by design snapshots**, rendered in-process to PNG by a
  `--design-snapshot <state>` launch flag. Baselines are **self-baselined and
  approved once by the user**: the first run writes the PNG, the user looks at it
  next to `design/mockups/v2/interactive.html` and approves, and from then on the
  pixel diff catches regressions. The HTML prototype is the reference a human or
  agent compares against — it is never diffed against the app automatically,
  because SwiftUI and a browser will never rasterize identically.
- **Anything needing the real Accessibility permission or a real model call is
  opt-in and best effort.** `ANCHR_LIVE_MODEL=1` and `ANCHR_LIVE_AX=1` gate those
  tests. `ANCHR_LIVE_MODEL` is the only thing in the repository that spends money.
  If the permission is missing, the task must record the exact blocker in
  `docs/blockers.md` and ask the user to grant it in System Settings — never
  fake a pass and never try to grant it by automation.
- **`scripts/preflight.sh` runs before any unattended session.** It proves the
  toolchain, one real OpenRouter round trip, the Accessibility read, disk, sleep and
  push access, classifies each result OK / DEGRADED / BLOCKED, and lists the
  decisions only the owner can make. It never prompts and never uses `sudo`.
- **`scripts/verify.sh` must be green before any task is called done.** Its grep
  gates are hard failures, not warnings.

## Validation Commands

- `scripts/preflight.sh` (before any unattended run)
- `scripts/verify.sh`
- `scripts/test.sh unit`
- `scripts/test.sh uismoke` (takes over the screen)
- `swift build`
- `scripts/e2e-smoke.sh`
- `python3 .claude/skills/ralphex-plan-writer/scripts/check_plan_format.py docs/plans/mvp_v1.md`

## Phase 1: Harness Before Features

### Task 1: Skeleton, Gates, Green Empty Test Run

- [x] Create the Swift package: `AnchrKit` (Foundation only), `AnchrCore` (macOS),
      `AnchrApp` (SwiftUI executable), and a test target per library.
- [x] Port `scripts/verify.sh` from `~/code/projects/notetakr/scripts/verify.sh`,
      keeping the `gate()` helper shape. Gates, all severity `fail`:
      no `Process(` anywhere; no `sk-or-` key literal anywhere; no `URLSession`
      outside `OpenRouterClassifier.swift`; no `AXUIElement` outside
      `AXSnapshot.swift` and `FocusContext.swift`; no `screencapture`,
      `CGWindowListCreateImage` or `SCStream` anywhere; no colour literal or
      `.font(.system(` under `AnchrApp/`; no fixed sleep in a test file; no real
      host named in a Kit test.
- [x] Add one placeholder test per target so the suites are real.
- [x] Write `docs/blockers.md` with an empty "Blockers" heading, used by later
      tasks to record permission problems.
- [x] Run `scripts/verify.sh` and `swift build`. Both must pass.

### Task 2: Accessibility Coverage Probe

This is the experiment that decides whether the text-only design holds. It ships
as a small tool, not as throwaway code.

- [x] Add `Tools/ax-probe`, a tiny executable target that takes a bundle ID or
      `--front`, sets `AXManualAccessibility = true` on the app element, walks the
      focused window's `AXUIElement` tree, and prints the flattened text plus a
      character count.
- [x] Reuse this walker from `AnchrCore/AXSnapshot.swift` later — the probe must
      call the same function, not a copy.
- [x] The measurement is already done — see `docs/ax-coverage.md`. Re-run the
      probe only to confirm the numbers still hold after the walker moves into
      `AXSnapshot.swift`, and update the table if they changed.
- [x] Implement the second-read rule proven there: set the flags on app
      activation, read the tree on the next check.
- [x] If the Accessibility permission is not granted, stop, write the exact
      blocker to `docs/blockers.md`, and ask the user to grant it in
      System Settings → Privacy & Security → Accessibility. Do not fake results.
- [x] Run `scripts/verify.sh`.

## Phase 2: The List

### Task 3: Markdown Parse, Serialize, Round-Trip

- [x] Implement `AnchrKit/TodoList.swift`: a flat array of `Item { text, depth,
      done }`, parsed from and serialized to the fixed format (`- [ ]` / `- [x]`,
      two spaces per depth level).
- [x] Clamp depth on parse so a child can never be more than one level deeper than
      its predecessor.
- [x] Add `fixtures/lists/real-day.md`, taken from the example list in the design
      prototype's seed data.
- [x] Tests: byte-stable round trip of the fixture; single-line edit changes
      exactly one line; empty file, blank lines and a single item all survive.
- [x] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 4: Paste Normalization

- [x] Implement `TodoList.normalize(pasted:)`: detect the indent unit (tabs count
      as one level), strip `-`, `*`, `+`, `•`, `–`, `1.`, `1)`, parse `[ ]` / `[x]`,
      turn `#`-headings into depth-0 items, strip `**bold**`, flatten
      `[[Foo|Bar]]` to `Bar`, drop blank lines.
- [x] Table-test it against the JavaScript prototype's `normalize()` in
      `design/mockups/v2/interactive.html`, which is the reference behaviour. At
      minimum the mixed-format German example from the prototype run must produce
      the same six items with the same depths and the same one checked item.
- [x] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 5: Store, Contexts, State

- [x] Implement `AnchrKit/ListStore.swift`: lists under
      `~/Library/Application Support/Anchr/lists/<slug>/list.md` plus
      `context.md`, and `state.json` holding the active list slug, the anchor
      index and the snooze deadline.
- [x] Implement `AnchrKit/Anchor.swift`: the anchor index plus its parent chain,
      and `goSmaller(text:)` which inserts a child under the anchor and moves the
      anchor to it.
- [x] Tests: create, list, switch, delete; `goSmaller` places the item at the right
      index and depth even when the anchor already has children; a corrupt
      `state.json` falls back to the first list instead of crashing.
- [x] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

## Phase 3: The Judgement

### Task 6: Scheduler and Policy

- [x] Implement `AnchrKit/CheckScheduler.swift` as a pure function of
      `(events, now, lastCall)` → `shouldCheck`: 8 s debounce after a focus
      signature change, 90 s heartbeat, 45 s minimum gap, paused on idle over
      3 min, on a locked screen, and while Anchr is frontmost.
- [x] Implement `AnchrKit/InterventionPolicy.swift` as a pure function of the
      verdict history: two consecutive `off_task` intervene, `unclear` never
      intervenes alone, 10 min silence after an intervention, 4 per hour ceiling.
- [x] Table-test both over explicit event and verdict sequences with an injected
      clock. Include the sequence that proves the nag ceiling holds when every
      verdict is `off_task` for an hour.
- [x] Run `cd AnchrKit && swift test` and `scripts/verify.sh`.

### Task 7: The Model Seam

- [x] Implement `AnchrKit/Verdict.swift` and `AnchrKit/ObservationPrompt.swift`:
      the verdict struct (`verdict`, `evidence`, `smaller_step`), its JSON Schema
      and the prompt text, all as data in Kit.
- [x] Implement `AnchrKit/OpenRouterRequest.swift`: the chat-completions body with
      `temperature: 0` and `response_format: json_schema, strict: true` carrying
      the schema Kit already owns, plus the answer decoding. No URLSession here.
- [x] Implement `AnchrCore/OpenRouterClassifier.swift`: the `URLSession` call, the
      `Authorization` header, an ephemeral non-caching session and a timeout.
- [x] Implement `AnchrCore/OpenRouterKey.swift`: `OPENROUTER_API_KEY`, else
      `~/Library/Application Support/Anchr/openrouter-key` written 0600. Never the
      repository, never a log line.
- [x] Implement `ScriptedClassifier` in the test support target: verdicts replayed
      in order from a fixture.
- [x] Tests: the body carries the strict schema Kit owns; a valid envelope decodes;
      an OpenRouter `error` object, an unparsable answer and a blank `smaller_step`
      all throw rather than looking like `on_task`. Add a live test gated by
      `ANCHR_LIVE_MODEL=1` that sends one fixture observation through the real API.
- [x] Run `scripts/test.sh unit`, `swift build`, `scripts/verify.sh`.

## Phase 4: Watching

### Task 8: Focus Context and Accessibility Snapshot

- [x] Implement `AnchrCore/FocusContext.swift`: frontmost bundle ID and focused
      window title from `NSWorkspace` notifications and an `AXObserver`. Push
      only, no polling loop.
- [x] Implement `AnchrCore/AXSnapshot.swift` around the walker from Task 2: set
      `AXManualAccessibility`, collect role/title/value/description, drop empty
      and decorative nodes, cap at 3000 characters, and report the useful
      character count so the caller can fall back to the title alone.
- [x] Add a permission check that reports "not granted" without prompting in a
      loop, plus the onboarding entry point that opens the right System Settings
      pane.
- [x] Tests: the flattener is a pure function over a fixture tree structure and is
      unit-tested without a live app. Add `AXSnapshotLive`, gated by
      `ANCHR_LIVE_AX=1`, that snapshots the frontmost app and asserts a non-empty
      result.
- [x] Run `swift build` and `scripts/verify.sh`.

### Task 9: The Loop, Proven Headless

- [x] Implement `AnchrCore/ObservationLoop.swift`: focus events in, scheduler
      decides, snapshot taken, classifier called, policy consulted, intervention
      requested through a callback. It must depend on protocols for the clock, the
      focus source and the classifier.
- [x] Write `scripts/e2e-smoke.sh` running `ObservationLoopE2ETests`: verdicts
      `on_task, off_task, off_task` through the real scheduler, policy and store
      with a fake focus source and `ScriptedClassifier`. Assert exactly one
      intervention fired, exactly one child item was appended to `list.md`, and
      the anchor moved to it.
- [x] Assert in the same test that no file was written outside the temporary
      Application Support directory the test created.
- [x] Run `scripts/e2e-smoke.sh` and `scripts/verify.sh`.

## Phase 5: The App

### Task 10: Overlay, List, Keys

- [ ] Implement the menu bar item (dot, pause, quit) and `OverlayWindow`: a
      borderless full-screen window over all spaces, blurred backdrop, opened by
      the ⌥Space global hotkey. A borderless `NSWindow` must override
      `canBecomeKey` and `canBecomeMain`, or it receives no key press at all and
      every binding below is dead.
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
- [ ] Add `project.yml`, `scripts/generate-project.sh` and `TestPlans/UISmoke.xctestplan`
      so XCUITest has a generated project to run in. The Swift package stays the
      build of record.
- [ ] Add `AnchrUITests/AnchrUITestCase.swift` after NoteTakr's: a fixture root
      under `/private/tmp` passed through `ANCHR_E2E_APP_SUPPORT_ROOT`, seeding done
      by the app through `ANCHR_E2E_SEED_LIST`, `ANCHR_E2E_SHOW_OVERLAY=1` because
      XCUITest cannot press a system hotkey, an empty `OPENROUTER_API_KEY` so the
      GUI never spends money, and a screenshot attached on failure.
- [ ] Add `AnchrUITests/ListOverlayUITests.swift`: the seeded list renders, an arrow
      key moves the selection, and space checks the selected item. Assert through
      accessibility identifiers, not on-screen text position.
- [ ] Show that baseline to the user next to the prototype for approval, then run
      `scripts/test.sh all` and `scripts/verify.sh`.

### Task 11: Create From Paste, and the Switcher

- [ ] Implement `CreateListView`: name field, one paste box, an optional
      `+ CONTEXT` box, `⌘↵` creates. It calls `TodoList.normalize` from Task 4 and
      nothing else.
- [ ] Implement the `⌘K` switcher: list names with open counts and whether a
      context file exists; `↵` opens, `C` edits context, `N` opens create,
      `esc` back.
- [ ] Test in Kit that creating a list from a pasted plan produces the expected
      `list.md` bytes. Add one XCUITest that pastes a plan into the real create
      view and asserts the resulting rows, because that path crosses the pasteboard
      and no unit test can.
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
- [ ] Add one XCUITest that opens the intervention with a scripted verdict and
      presses `1`, `2` and `3`, asserting the list and the anchor afterwards. This
      is the screen with no escape hatch, so a wrong key binding traps the user.
- [ ] Add design snapshots `intervention/ask` and `intervention/smaller`, get the
      baselines approved once, then run `scripts/e2e-smoke.sh`, `scripts/test.sh all`
      and `scripts/verify.sh`.

### Task 13: Onboarding

- [ ] Implement the three-step first run: grant Accessibility (one sentence
      explaining that Anchr reads the text of the front window and takes no
      pictures, plus a button that opens the right System Settings pane); connect
      OpenRouter by pasting a key and proving it with one real classification;
      paste the first plan through `CreateListView`.
- [ ] The key step reads the pasteboard, stores the key 0600 through
      `OpenRouterKey.store`, and reports the three failures that actually happen in
      the user's own words: no key, a rejected key (401/403), and no credit (402).
      Do not build a fallback path and never print the key.
- [ ] Add design snapshot `onboarding/permission`, get the baseline approved once,
      then run `scripts/verify.sh`.

## Phase 6: Does It Actually Work

### Task 14: The Verdict Corpus

- [ ] Collect about 30 real accessibility snapshots from work sessions into
      `fixtures/corpus/`, each with the anchor, the context file and the expected
      verdict. Include the hard ones: documentation that reads like YouTube, a
      YouTube video that genuinely is the task, a terminal that could be anything,
      a meeting, and a break.
- [ ] Add `VerdictCorpusTests`, gated by `ANCHR_LIVE_MODEL=1`, that scores the
      real classifier against the corpus and prints an accuracy number plus every
      disagreement. Report the spend for the run; the corpus is the one place where
      cost is worth measuring.
- [ ] Score the same corpus against one cheaper and one stronger OpenRouter model
      before settling. Changing `ANCHR_OPENROUTER_MODEL` is now a one-line
      experiment, which the `codex` path never allowed.
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
      pass a task. Check specifically that the no-subprocess, no-key-literal and
      network-confinement gates still hold.
- [ ] Confirm `Anchr.xcodeproj` is still fully generated: delete it, run
      `scripts/generate-project.sh`, and the GUI suite must still pass.
- [ ] Run `scripts/verify.sh`, `scripts/test.sh all`, `scripts/e2e-smoke.sh`.

## Phase 8: End-to-End

### Task 16: Full Product Run

- [ ] Build and launch the real app. Grant Accessibility if asked. Paste a real
      plan, add context, set an anchor.
- [ ] Work normally for at least 20 minutes with the loop live against the real
      OpenRouter model, then deliberately drift to an unrelated site and confirm an
      intervention appears within two minutes.
- [ ] Answer "go smaller" and confirm the child item appears in `list.md` on disk
      with correct indentation and that the anchor moved.
- [ ] Confirm no file appeared anywhere outside
      `~/Library/Application Support/Anchr/` and that no image file was written at
      any point. Confirm the OpenRouter key never appeared in a log or a crash
      report.
- [ ] Fix only what this run breaks. Record anything else in `ideas.md`.
- [ ] Run `scripts/verify.sh` and `scripts/e2e-smoke.sh` one last time.
