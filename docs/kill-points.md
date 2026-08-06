# Kill points

The two cheap experiments the V1 plan is built around. Both must answer yes
before the app is worth building. Reproduce with `Tools/ax-probe` and
`Tools/verdict-probe`.

---

## Kill point 2 — does the model judge well enough? (2026-08-06)

**Result: 4 / 6, and both misses lean the harmless way. Passed for now.**

Six hand-written observations in the accessibility-tree format Anchr will
actually send, scored against the real `codex exec` with the real schema.
Latency 5–9 s per verdict, low reasoning effort.

| Case | Expected | Got |
|---|---|---|
| Unrelated YouTube video | off_task | off_task |
| The extraction sheet itself | on_task | on_task |
| **Apple docs that read like drift** | on_task | on_task |
| **A YouTube video that genuinely is the task** | on_task | on_task |
| A terminal that could be anything | unclear | on_task |
| Slack while the anchor is a private email | unclear | off_task |

The two cases that could have killed the concept both passed. The model read the
`AXUIElementCopyAttributeValue` documentation page as work because the project
context said Anchr reads the Accessibility API, and it read a YouTube video as
work because the context named that video's subject as the source of the idea.
Content, not the app name, decided both. That is the whole bet.

**The two misses:**

- *Terminal.* The model answered `on_task`, reasoning that `export.csv` in
  Downloads plausibly is the extraction. Defensible, and it errs toward not
  interrupting.
- *Slack.* The model answered `off_task` where the label said `unclear`. This is
  the dangerous direction — the nag failure. It is survivable only because
  `InterventionPolicy` needs **two consecutive** `off_task` before it opens
  anything, so a short Slack check never triggers.

**What this does not prove.** The observations are hand-written, not captured.
Real trees are noisier, longer and full of chrome. The real number comes from
the corpus in Task 14, against real snapshots. Treat 4 / 6 as "keep going", not
as an accuracy figure.

**Prompt note.** `smaller_step` was useful in all six answers, including the
`on_task` ones. That is the field the whole intervention hangs on, so this is a
better signal than the verdict column.

---

## Kill point 1 — do real apps give up enough text? (2026-08-06)

**Result: passed, with one accepted limitation. Full table in
`docs/ax-coverage.md`.**

Thirteen apps measured with `Tools/ax-probe`. Safari gives the whole page
(29 210 chars), Electron apps give their content once the flag has been set and
read a second time, and Chromium browsers give **only the tab title**.

The limitation is the one that mattered, because browsers are where drift
happens. So it was tested directly: two more classification cases built from the
real Chrome observation, containing nothing but the tab title and the toolbar.

| Case | Expected | Got |
|---|---|---|
| Chrome title only, a YouTube video, drifting | off_task | off_task |
| Chrome title only, a Stack Overflow page that is the task | on_task | on_task |

Both correct. A tab title names the video, the repo or the document, and that is
enough for the judgement. Chrome's poverty does not kill the design.

Kill point 2 above used richer, hand-written observations. These two used a real,
poor one. Together they cover both ends.
