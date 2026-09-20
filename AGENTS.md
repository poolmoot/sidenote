# Working on this repo

Instructions for anyone — human or agent — writing code here. Read `docs/architecture.md` first; it explains the shape. This file is the working agreement.

## Commands

```bash
make bootstrap   # once: builds the pinned XcodeGen into .tools/
make generate    # regenerate App.xcodeproj from project.yml
make build       # build the app (no warnings allowed from our code)
make test        # every test target
make run         # build, quit any running copy, launch
```

Requirements: macOS 26+, Xcode 26+. After a macOS/Xcode upgrade you may need `sudo xcodebuild -runFirstLaunch`. The repo path contains spaces — quote it in shell commands.

## Non-negotiables

1. **No polling.** No repeating timers, no `NSEvent` global/local monitors, no cursor polling. The idle budget is under 0.5 % CPU and under 80 MB; it currently measures 0.0–0.3 % and ~14 MB. Verify with the grep in `docs/architecture.md`.
2. **Module boundaries.** Feature modules import only `NotchWidgetAPI`, `Persistence`, `DesignSystem`, `AppInfo`. They never import `NotchKit` or each other. Only the app target composes modules.
3. **The app name** lives only in `Config/Branding.xcconfig`; Swift reads `AppIdentity.current.name`.
4. **Test-first for logic.** Stores, parsing, date maths and state transitions are pure and tested; views and window behaviour are checked by hand. Inject clocks, calendars and system services behind protocols — tests never touch the real `UNUserNotificationCenter`, the real pasteboard, or the user's real defaults.
5. **One source of truth.** Data lives in a store; views bind to it. No `@State` copies of store data.
6. **Nothing expensive in a SwiftUI `body`.**
7. **Commits** end with the trailer:
   `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
8. **No third-party code or attributions** in this repo. Everything here is written for this project.

## How work is organised

- `docs/superpowers/specs/` — the design spec. It is the authority; if code and spec disagree, one of them is a bug.
- `docs/superpowers/plans/` — one plan per milestone: files, behaviour, tricky parts, tests, done-when.
- `docs/superpowers/verification/` — hand-check records.
- A milestone runs: short plan → implement (test-first) → one thorough review → fix pass → re-review → the owner's hand check → merge.

## Style

Follow the surrounding code. In particular:
- Doc comments explain **why**, not what. The *why* is the part a reader can't recover from the code.
- Small files with one responsibility. If a file is growing past a few hundred lines, it is doing two jobs.
- Name things after what they mean to the user (`isMissing`, `overdue`, `foldedHoverMargin`), not after their mechanism.
- Errors are logged through `AppIdentity.current.logger(_:)` and never swallowed silently.

## Traps this codebase has already fallen into

Each of these shipped once and was caught in review. Don't repeat them:

- A `@State` copy of a note's text made checkbox ticks invisible and silently reverted them.
- An AppKit drag-source view over the cell swallowed the ✕ button's clicks.
- The notch treated the shelf's own drag-out as an incoming file drag and folded mid-drag.
- `split(separator: "\n")` treats CRLF as one line — split on the unicode scalar.
- Swallowing resign-key while editing left the notch stuck open with no way out.
- `reconcile()` rescheduled past-due reminders, re-firing them on every launch.
- Rounding a countdown up made a 5-minute reminder read "in 6 min".

## Git

`publish` tracks the public GitHub repo. Branch each milestone from `publish`, merge it back fast-forward, push. The local `main` branch is a private archive of pre-publication history and is never pushed.
