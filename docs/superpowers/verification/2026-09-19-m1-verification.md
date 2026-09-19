# M1 Verification — Notch Shell

**Date:** 2026-09-19 · **Build:** 2689a64 · **Mac:** Mac14,2, macOS 26.5.2

## Behaviour checklist

Interactive verification requires moving a real pointer, dragging files, and observing spring
animations, which this automated pass cannot perform. Every row below is marked pending for
user acceptance rather than claimed as passing.

| # | Result | Notes |
|---|---|---|
| 1 | ✅ | Checked by hand by the owner |
| 2 | ⏳ pending (user acceptance) | |
| 3 | ⏳ pending (user acceptance) | |
| 4 | ⏳ pending (user acceptance) | |
| 5 | ✅ | Checked by hand by the owner |
| 6 | ⏳ pending (user acceptance) | |
| 7 | ✅ | Checked by hand by the owner |
| 8 | ⏳ pending (user acceptance) | |
| 9 | ⏳ pending (user acceptance) | |
| 10 | ✅ | Checked by hand by the owner |
| 11 | ⏳ pending (user acceptance) | |
| 12 | ⏳ pending (user acceptance) | |
| 13 | ⏳ pending (user acceptance) | |
| 14 | ⏳ pending (user acceptance) | |
| 15 | ⏳ pending (user acceptance) | |
| 16 | ⏳ pending (user acceptance) | |
| 17 | ⏳ pending (user acceptance) | |
| 18 | ⏳ pending (user acceptance) | |
| 19 | ⏳ pending (user acceptance) | |
| 20 | ⏳ pending (user acceptance) | |
| 21 | ⏳ pending (user acceptance) | |
| 22 | ⏳ pending (user acceptance) | |
| 23 | ⏳ pending (user acceptance) | |
| 24 | ⏳ pending (user acceptance) | |
| 25 | ⏳ pending (user acceptance) | |
| 26 | ⏳ pending (user acceptance) | |
| 27 | ⏳ pending (user acceptance) | |

## Idle cost (Release)

Release build launched (`build/DerivedData/Build/Products/Release/SideNotch.app`), given 10 s
to settle, then sampled with `top -l 13 -s 5 -pid "$PID" -stats pid,command,cpu,idlew,mem`
(~65 s) and `footprint`.

| Metric | Budget | Measured |
|---|---|---|
| CPU, idle (13 × 5 s samples) | ≤ 0.5 % | 0.0 % on 12 of 13 samples, one sample at 0.3 %; all within budget |
| Idle wake-ups | ≈ 0 | IDLEW held steady at 2 across every sample (no growth over the run) |
| Physical footprint | < 80 MB | 14 MB (`footprint` output; RSS in `top` read 14–15 MB throughout) |
| CPU 1 s after folding | ≈ 0 % | hover-driven recovery pending user acceptance — a second `top -l 6 -s 5` run (~30 s) taken immediately after the first, as a longer idle baseline, read 0.0 % on 5 of 6 samples and 0.2 % on the last; IDLEW again steady at 2 |

Polling/timer check: `grep -rnE "Timer\(|scheduledTimer|addGlobalMonitor|addLocalMonitor|repeatForever|CVDisplayLink|TimelineView" Packages/Modules/Sources App/Sources` → `no polling` (no matches).

Screenshot attempt: `screencapture -x m1-screen.png` failed with `could not create image from display`
(screen-recording permission unavailable to this automated session). No image was captured or
committed; the visual state of the pill at the right screen edge was not verified by this pass.

## Issues found and fixes

- None found in automated checks. The owner checked rows 1, 5, 7 and 10 by hand (hover, typing, Esc, file drop); the other rows remain to be checked.
- The `screencapture` evidence step could not run in this sandboxed session (no screen-recording
  permission) — not a defect in the app, just a limitation of this verification environment.

<details>
<summary>Raw <code>top</code> and <code>footprint</code> output</summary>

```
$ pkill -x SideNotch; make CONFIG=Release build
(build succeeded, no errors)

$ open build/DerivedData/Build/Products/Release/SideNotch.app
$ sleep 10
$ PID=$(pgrep -x SideNotch)   # 31985

$ top -l 13 -s 5 -pid "$PID" -stats pid,command,cpu,idlew,mem
PID    COMMAND   %CPU IDLEW MEM
31985  SideNotch 0.0  2     15M
31985  SideNotch 0.0  2     14M-
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.3  2     14M+
31985  SideNotch 0.0  2     14M-

$ footprint "$PID" | head -3
======================================================================
SideNotch [31985]: 64-bit    Footprint: 14 MB (16384 bytes per page)
======================================================================

$ top -l 6 -s 5 -pid "$PID" -stats pid,command,cpu,idlew,mem   # immediately after run 1
PID    COMMAND   %CPU IDLEW MEM
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.0  2     14M-
31985  SideNotch 0.0  2     14M+
31985  SideNotch 0.0  2     14M-
31985  SideNotch 0.0  2     14M
31985  SideNotch 0.2  2     14M+

$ grep -rnE "Timer\(|scheduledTimer|addGlobalMonitor|addLocalMonitor|repeatForever|CVDisplayLink|TimelineView" Packages/Modules/Sources App/Sources
no polling

$ screencapture -x ".../m1-screen.png"
could not create image from display
(exit 1 — not committed)

$ pkill -x SideNotch
(app quit cleanly)
```

</details>
