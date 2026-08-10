# Accessibility text yield per app

Measured 2026-08-06 with `Tools/ax-probe` on this machine. The shared
`AnchrCore/AXSnapshot.swift` walker was confirmed again on 2026-08-10.
Method: set `AXManualAccessibility` and `AXEnhancedUserInterface` on the app
element, walk the focused window, keep role + title + value + description, drop
nodes with no text of their own.

## Conclusion: text-only holds. Build it.

The window title is always available and it carries most of the signal. Where
the tree is rich, it is a bonus, not a requirement. Two title-only test cases
were classified correctly by the real model (see `docs/kill-points.md`), which is
the result that decides this.

## Numbers

| App | Chars | Document or page content? |
|---|---|---|
| Safari | 29 210 | **Yes** — full web area, headings, body text |
| Spotify | 44 906 | Yes |
| Emdash Dev (Electron) | 8 348 on shared-walker recheck; 38 513 before | Yes |
| WhatsApp | 6 170 | Yes |
| T3 Code (VS Code fork) | 4 361 | UI and project name only, no editor text |
| Obsidian (Electron) | 2 043 | Yes — note content, **on the second read** |
| Chrome | 882 | **No** — tab title, toolbar, URL |
| Arc | 27 852 | **No** — its own sidebar and tab list, not the page |
| Xcode | 631 | Thin |
| Terminal (cmux) | 613 | Thin — window title carries the directory |
| Slack | 557 | Not a fair test, signed out |
| Finder | 223 | Thin |
| Telegram | 25 | **No** — effectively empty |

## Findings that change the implementation

1. **Chromium browsers do not expose page content.** Neither
   `AXManualAccessibility` nor `AXEnhancedUserInterface` makes Chrome or Arc
   build the renderer tree for an ordinary AX client. Arc's large number is
   misleading: it is Arc's own sidebar, bookmarks and tab titles, with no
   `AXWebArea` anywhere.
   **Accepted.** The tab title names the video, the repo, the document. Two
   title-only cases were judged correctly, one drift and one on-task.
2. **Safari is the opposite** and gives the whole page. No special handling
   needed; it just gets a better observation.
3. **Electron apps need two reads.** Obsidian returned 91 characters on the
   first probe and 2 043 on the second, one second later. Setting
   `AXManualAccessibility` starts the tree build; the result is not there yet
   when the same call returns.
   **Implementation rule:** set the flag when an app becomes frontmost, then
   read on the next check, never in the same call.
4. **Editors expose their shell, not their text.** T3 Code and Xcode give the
   sidebar, the tabs and the project name, but not the file contents. Enough to
   know which project you are in, not enough to know what you are typing.
5. **Some native apps give nothing** (Telegram, 25 characters). The title is the
   whole observation there, and `unclear` is the correct verdict.

## Reproduce

```
swift run ax-probe --front
swift run ax-probe com.apple.Safari
```

Needs Accessibility permission for the process that runs it.
