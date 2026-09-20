# Architecture

How SideNote is put together, why, and where to change things. Read this before adding a feature.

## The shape of it

```
App/Sources            a thin shell — the ONLY place that wires modules together
Packages/Modules       every line of logic, one module per concern, each with its own tests
```

The app target owns no behaviour. `AppEnvironment` builds the stores, the widgets and the notch, hands them to each other, and gets out of the way. If you find yourself adding logic to `App/Sources`, it belongs in a module instead.

```
                     ┌──────────────── App target ────────────────┐
                     │ AppDelegate → AppEnvironment               │
                     │   StatusItemController · SettingsWindow    │
                     │   NotificationDelegate                     │
                     └───────────────┬────────────────────────────┘
                                     │ builds & wires
   ┌─────────────┬──────────────┬────┴─────────┬──────────────────┐
   │ NotchKit    │ ShelfFeature │ NotesFeature │ RemindersFeature │
   │ the window  │              │              │                  │
   └──────┬──────┴───────┬──────┴──────┬───────┴─────────┬────────┘
          │              └─────────────┴─────────────────┘
          │                            │ every feature depends only on
   ┌──────┴──────┐        ┌────────────┴─────────────┬─────────────┐
   │ NotchWidget │        │ Persistence  DesignSystem  AppInfo     │
   │ API         │        └──────────────────────────────────────  │
   └─────────────┘
```

**The one rule that keeps this healthy:** features never import `NotchKit`, and never import each other. A feature knows only `NotchWidgetAPI` (the plug), `Persistence` (saving), `DesignSystem` (colours and motion) and `AppInfo` (name, logging). `NotchKit` never knows what a Shelf or a Note is — it holds widgets as `any NotchWidget`.

That's what makes a feature removable: delete its folder, its product line in `Package.swift`, its `project.yml` entry and its two lines in `AppEnvironment`. Nothing else refers to it.

## The modules

| Module | What it owns |
|---|---|
| `NotchWidgetAPI` | The plug: `NotchWidget`, `WidgetID`, `WidgetContext`, `WidgetBadge`. No dependencies at all. |
| `NotchKit` | The window and its behaviour: the panel, the shape, hover/drag plumbing, the state machine, placement maths, full-screen detection, the controller. |
| `Persistence` | `JSONFileStore` (atomic, debounced, corrupt-file quarantine) and `AppPaths`. |
| `DesignSystem` | Colours (`Palette`) and motion (`NotchMotion`). |
| `AppInfo` | `AppIdentity`: app name, bundle id, version, loggers. |
| `SettingsFeature` | `Preferences` (UserDefaults) and the Settings window's views. |
| `ShelfFeature` / `NotesFeature` / `RemindersFeature` | One mini app each: model, store, widget, views, tests. |

## How the notch behaves

Every transition is decided by `NotchStateMachine`, a pure value type with no AppKit, no clock and no I/O:

```
FOLDED ──hover 150 ms──► TILES ──click tile──► EXPANDED(widget)
   ▲                        │                       │
   └── file drag ───────────┴── pointer out 250 ms ─┘   Esc · click outside · back
```

- It takes an **event** (`pointerEntered`, `tileSelected`, `escape`, …) and returns **effects** (`startHoverTimer`, `makeKey`, …).
- `NotchController` performs those effects on real AppKit objects. That split is why the notch's rules are testable at all: 57 tests drive the machine directly.
- The views draw from rects the controller computed. **Views contain no geometry and no logic.**

**The editing lock:** while a widget's text field has focus, the notch must not fold when the pointer leaves. A widget signals that with `context.setEditing(true/false)`. Get this wrong in one direction and typing gets interrupted; wrong in the other and the notch sticks open forever. Always pair it with the actual focus state, and release it in `onDisappear`.

## Performance rules (non-negotiable)

The whole point of the app is that it costs nothing while you aren't using it. Measured: **0.0–0.3 % CPU idle, ~14 MB**.

1. **No polling.** No repeating timers, no global event monitors, no cursor polling. Hover comes from one `NSTrackingArea`; drags from `NSDraggingDestination`; full-screen state from workspace notifications.
2. The only time-based code allowed: one-shot hover/grace delays, one re-armed `Task.sleep` for the next due reminder, and a `TimelineView` that exists **only inside an open widget**.
3. **Nothing expensive in a SwiftUI `body`** — no disk reads, no parsing a whole document, no regex per keystroke. Cache in the store, recompute on change.
4. Thumbnails and other caches live in the expanded view, so folding frees them.

CI-style check before every commit:

```bash
grep -rnE "Timer\(|scheduledTimer|addGlobalMonitor|addLocalMonitor|repeatForever|CVDisplayLink" Packages/Modules/Sources App/Sources || echo "no polling"
```

## Saving data

Each store owns a `JSONFileStore<Document>` and calls `save` on change and `flush()` when the widget closes or the app quits. The store writes atomically on a background queue, debounced ~0.5 s. A file that can't be decoded is renamed `<name>.corrupt-<timestamp>.json` and the store starts empty — data is never silently overwritten with garbage. Documents carry `version: 1`; `load(isValid:)` refuses anything newer.

Files live in `~/Library/Containers/<bundle-id>/Data/Library/Application Support/<AppName>/`.

## Window mechanics (the subtle part)

- One borderless, non-activating `NSPanel` at `.statusBar` level, joining all spaces. It is a **fixed full-height strip** as deep as the deepest widget; only the SwiftUI shape inside it animates, so the window is never resized mid-animation.
- Everything outside the live region (`hotRect`) passes clicks through. The live region is painted at 1 % opacity, because fully transparent pixels let events fall through the window.
- The panel may take the keyboard only while a widget is expanded (`allowsKey`). Losing key status folds the notch — unless the app itself is still active, which is how Quick Look's own panel doesn't dismiss itself.
- Escape folds the notch, except while a text view has marked text (so typing in Japanese or Chinese isn't interrupted).
- Any AppKit view you put over SwiftUI swallows its clicks. Keep tap targets on top, give them `.contentShape`, and override `acceptsFirstMouse` if the panel may be non-key.

## Naming and identity

The app's name exists in exactly one place: `Config/Branding.xcconfig` (`APP_NAME`, `BUNDLE_ID_PREFIX`). Swift reads it via `AppIdentity.current.name`. Never type the product name in Swift. Changing the bundle id changes where preferences and data live, so don't change it after release.

## Known limits worth fixing before the app grows much further

- `WidgetID` is a fixed enum (`shelf`, `notes`, `reminders`), so a fourth widget means editing `NotchWidgetAPI`. A string-backed identifier would make widgets fully additive.
- Widget order and enablement are hard-coded in `AppEnvironment`; Settings gains that in M5.
- The controller has no automated tests (its logic lives in the tested state machine); window behaviour is verified by hand.
