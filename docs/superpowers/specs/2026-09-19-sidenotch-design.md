# SideNotch — Design Spec

**Date:** 2026-09-19
**Status:** Approved in design review (grilling session), pending written-spec review
**Working name:** SideNotch (final name TBD by owner — see §9, renaming is a one-line change)

## 1. Summary

A macOS utility that pins a small black pill to the left or right edge of one screen.
Hovering the pill unfolds it into three tiles; each tile opens a mini app:

1. **Shelf** — a temporary pocket for files: drop files in, drag them out elsewhere.
2. **Notes** — a list of short plain-text notes with checkboxes.
3. **Reminders** — write what to be reminded of, pick when, get a macOS notification.

A normal Settings window configures everything. The app has a menu bar icon and no Dock icon.

The design is a small black pill that reads as part of the bezel rather than a floating panel,
combined with a widget-dock layout for the three mini apps, with one overriding engineering goal:
**stay as light on CPU and memory as possible**, chiefly by never polling.

## 2. Goals and non-goals

### Goals
- Native look and feel; the folded pill reads as part of the bezel.
- Near-zero idle cost: no timers or polling while folded (see §7 budget).
- Three focused mini apps, each usable in a couple of clicks.
- Codebase that is modular, tested, and easy to rename and ship.

### Non-goals (v1)
- Top/bottom edges; pill on multiple screens at once; following the mouse across screens.
- Sync of any kind (iCloud, Apple Reminders, Markdown folders).
- Repeating reminders; natural-language time parsing.
- Rich text notes.
- Dropping non-file content (browser images, URLs, text snippets) on the shelf.
- Notarization / Developer ID signing (app ships unsigned; see §10).
- Localization beyond English (strings live in a String Catalog so it can be added later).

## 3. User-facing behaviour

### 3.1 Notch states

```
            pointer enters (hover delay, default 150 ms)       click tile
 FOLDED ──────────────────────────────────────────► TILES ───────────────► EXPANDED(widget)
   ▲  │                                               │                        │
   │  │ file drag enters                              │ pointer exits          │ pointer exits AND not editing
   │  └────────────────► EXPANDED(shelf, dropTarget)  │ (250 ms grace)         │ (250 ms grace),
   │                                                  │                        │ or Esc, or click outside
   └──────────────────────────────────────────────────┴────────────────────────┘
```

- **FOLDED** — a thin black pill in the edge with concave "shoulders" that curve into the bezel.
  Shows a small dot when a reminder is overdue.
- **TILES** — the pill grows into a column of enabled widget tiles (default order Shelf, Notes,
  Reminders), plus a small gear button that opens Settings.
- **EXPANDED(widget)** — the shape grows into that widget's panel. A back chevron returns to TILES.
- A file drag entering the pill skips TILES and opens EXPANDED(shelf) with a "Drop here" highlight.
  If the drag leaves without dropping, the notch folds after the grace period.
- **Editing lock:** while a text field in a widget has focus, pointer exit does not fold. Esc,
  clicking outside the notch (panel resigns key), or the widget's shortcut folds it. Text is saved
  continuously, so folding never loses input.
- Right-click on the pill: context menu with *Settings…*, *Hide Notch*, *Quit*.
- ⌥-drag on the pill slides it along the edge; the offset is persisted.
- Reduce Motion (system setting or app setting) replaces springs with instant changes.

### 3.2 Placement
- Edge: **left or right** (default right), chosen in Settings.
- Along-edge offset: set by ⌥-drag, clamped so the pill stays on screen.
- Screen: **one chosen display** (default: main display). Stored by display UUID. If that display
  disconnects, the pill moves to the main display and returns when the chosen one reconnects.
- **Full screen:** when the frontmost app is full screen on the pill's display, the pill is drawn
  invisible, but its hover/drop strip stays live — hovering the very edge or dragging a file there
  still unfolds it. Detection runs only on space-change / app-activation notifications, never on a
  timer. Known limitation: full screen that posts no notification (e.g. a browser video going full
  screen inside the same space) may not be detected.

### 3.3 Shelf (Files widget)
- Accepts **files and folders only**, one or many per drop, from Finder or any app that drags file URLs.
- Stores a **security-scoped bookmark** to each original — never a copy. Duplicate drops of the same
  file are ignored.
- Shown as a grid with Quick Look thumbnails (generated lazily, cached in memory only while expanded).
- Click opens the file with its default app; Space shows Quick Look; ✕ removes the item; *Clear all*.
- **Drag out always copies** (the drag source offers only the copy operation). After a successful
  drag-out the item is removed from the shelf. Dragging several selected items out works the same.
- Items persist across quit and restart until dragged out or removed.
- If an original can no longer be resolved, the item shows greyed out as "Missing" and can only be removed.

### 3.4 Notes widget
- A list of notes; the first line is the title. *+* creates a note and focuses it; click a note to
  edit it inline; ✕ (with ⌘Z undo) deletes.
- Plain text. Lines beginning `- [ ]` / `- [x]` render as tickable checkboxes; URLs are clickable.
- Autosave: changes are written ~0.5 s after the last keystroke, and immediately on fold/quit.
- Sorted by last edited, newest first.

### 3.5 Reminders widget
- Text field for what to remember, then a time chip: **5 min · 15 min · 30 min · 1 h · Tonight
  (20:00) · Tomorrow (09:00)** or **Custom…** (date + time picker). Chip times are configurable.
  "Tonight" when it is already past 20:00 means tomorrow 20:00.
- Delivery via macOS notifications (UserNotifications), scheduled with the system, so reminders
  fire even if the app is not running. Notification permission is requested the first time a
  reminder is created.
- Notification actions: **Done** and **Snooze** (default 10 min, configurable). Clicking the
  notification body opens the Reminders widget.
- The list shows upcoming reminders with relative times ("in 12 min"), refreshed once a minute
  and only while the widget is open. Overdue items show at the top in red with Done / Snooze.
- When a reminder becomes due while the app is running, the pill shows an overdue dot until it is
  marked done or snoozed. Done reminders are removed (⌘Z undo while the widget is open).
- No repeating reminders in v1.

### 3.6 App presence and Settings
- `LSUIElement` app: no Dock icon, not in ⌘-Tab.
- Menu bar icon with: *Settings…* (⌘,), *Show/Hide Notch*, *Quit*.
- Settings is a normal window (activates the app while open), with tabs:
  - **General:** edge, display, launch at login.
  - **Appearance:** style (*Solid black* default / *Liquid Glass*), pill size (S/M/L), accent colour,
    hover delay, reduce motion.
  - **Widgets:** enable/disable and reorder the three widgets.
  - **Shelf:** *Clear shelf*.
  - **Notes:** *Export all notes…* (one `.md` file per note into a chosen folder).
  - **Reminders:** snooze length, chip times.
  - **Shortcuts:** global shortcut to open each widget and to toggle the notch.
  - **About:** version, *Check for Updates…*, third-party notices.

## 4. Architecture

### 4.1 Layers

```
┌──────────────────────────── App target (thin shell, target "App") ────────────────────────────┐
│ AppDelegate → AppEnvironment (composition root; builds stores/services, wires modules)        │
│   ├─ StatusItemController      menu bar item                                                  │
│   ├─ NotchController           owns NotchStateMachine + NotchPanel, applies Preferences        │
│   ├─ SettingsWindowController  normal NSWindow hosting SettingsView                           │
│   └─ UpdaterController         Sparkle (M6)                                                   │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
        depends on the local Swift package `Packages/Modules`:
┌───────────────┬───────────────┬───────────────┬────────────────┬──────────────────┐
│ NotchKit      │ ShelfFeature  │ NotesFeature  │ RemindersFeat. │ SettingsFeature  │
├───────────────┴───────────────┴───────────────┴────────────────┴──────────────────┤
│ NotchWidgetAPI · Persistence (JSONFileStore, AppPaths) · DesignSystem · AppInfo     │
└────────────────────────────────────────────────────────────────────────────────────┘
```

**Rule:** feature modules never import each other or NotchKit. NotchKit knows
widgets only through the `NotchWidget` protocol. The app target is the only place that composes
modules. Dependencies point downward only.

### 4.2 Modules

| Module | Responsibility | Depends on |
|---|---|---|
| `AppInfo` | `AppIdentity`: app name, bundle ID, version, read from `Bundle.main`; `Logger` factory | — |
| `DesignSystem` | Colours, typography, `NotchStyle` (black/glass) surface modifier, motion constants | — |
| `Persistence` | `JSONFileStore<Value: Codable>` (atomic, debounced writes), `AppPaths` (Application Support dir) | AppInfo |
| `NotchWidgetAPI` | `NotchWidget` protocol, `WidgetID`, `WidgetBadge` — the only contract between the notch and the widgets | — |
| `NotchKit` | `NotchPanel`, `SideNotchShape`, `NotchEdge`, `NotchPlacement`, `NotchGeometry`, `NotchMetrics`, `NotchStateMachine`, `FullScreenObserver`, `NotchRootView`, hover/drag plumbing | NotchWidgetAPI, DesignSystem, AppInfo |
| `SettingsFeature` | `Preferences` (`@Observable`, UserDefaults-backed), `SettingsView` tabs, `LaunchAtLogin` | NotchKit (for `NotchEdge`/`NotchConfiguration`), AppInfo |
| `ShelfFeature` | `ShelfStore`, `ShelfItem`, bookmark resolution, `ThumbnailCache`, `ShelfView`, drag source/destination | NotchWidgetAPI, Persistence, DesignSystem |
| `NotesFeature` | `NotesStore`, `Note`, `ChecklistText` parser, `NotesView`, `NoteEditor` | NotchWidgetAPI, Persistence, DesignSystem |
| `RemindersFeature` | `RemindersStore`, `Reminder`, `ReminderScheduler` (UNUserNotificationCenter wrapper behind a protocol), `TimeChip`, `RemindersView` | NotchWidgetAPI, Persistence, DesignSystem |

`NotchWidget` lives in its own tiny module (`NotchWidgetAPI`) so feature modules can conform
without pulling in any window code:

```swift
@MainActor
public protocol NotchWidget: AnyObject {
    var id: WidgetID { get }                 // .shelf / .notes / .reminders
    var title: String { get }
    var systemImage: String { get }
    var expandedSize: CGSize { get }
    var acceptsFileDrops: Bool { get }
    var badge: WidgetBadge? { get }           // e.g. overdue dot
    func makeExpandedView(context: WidgetContext) -> AnyView   // context: setEditing(_:), close()
    func handleFileDrop(_ urls: [URL]) -> Bool
}
```

### 4.3 Window mechanics (NotchKit)
- **One `NotchPanel`** (`NSPanel`, borderless, `.nonactivatingPanel`, level `.statusBar`,
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, clear background,
  no shadow).
- `canBecomeKey` returns `true` only in EXPANDED states, so notes/reminders can take typing without
  activating the app or stealing the frontmost app's activation. Resigning key = "click outside" → fold.
- **The panel frame never changes with state.** The panel is a fixed strip on the chosen edge: the
  full height of the display, as deep as the deepest widget panel plus the hover margin. Only the
  SwiftUI shape inside it animates, so the window is never resized mid-animation (no flicker, no
  per-frame window-server work). It is re-placed only on screen, edge or display changes. Cost:
  one mostly-transparent backing store (~6 MB on a Retina display), well inside the §7 budget.
- **Hit testing:** a container view passes clicks through everywhere outside the visible shape
  (ported `NotchContainerView`/`NotchHostingView` pattern).
- **Hover:** one `NSTrackingArea` (`.mouseEnteredAndExited`, `.activeAlways`) whose rect is the
  visible shape's rect plus margin, updated on each state change. No global event monitors, no
  cursor polling.
- **Drag in:** the container view registers for `.fileURL` and implements `NSDraggingDestination`
  (`draggingEntered` → state machine event `.fileDragEntered`).
- **Invisible-but-live strip:** in full-screen mode and when folded, the hot strip is filled with a
  near-transparent colour (alpha ≈ 0.01) so the window server keeps routing mouse and drag events to
  it. (Fully transparent pixels in a non-opaque window pass events through.) Verified in M1.
- **⌥-drag** along the edge: handled in `NotchPanel.mouseDown` (ported).
- **Screen changes:** `NSApplication.didChangeScreenParametersNotification` → recompute frame and
  resolve display preference.
- **Full screen:** `FullScreenObserver` listens to `NSWorkspace.activeSpaceDidChangeNotification`
  and `didActivateApplicationNotification`, and on each runs the ported `FullScreenDetector` once
  (plus one follow-up 0.35 s later, since space transitions animate). Publishes `isFullScreen`.

### 4.4 State machine
`NotchStateMachine` is a pure value type (no AppKit), fully unit-tested:

- **States:** `folded`, `tiles`, `expanded(WidgetID, dropTarget: Bool)`.
- **Inputs:** `pointerEntered`, `pointerExited`, `hoverDelayElapsed`, `graceElapsed`,
  `fileDragEntered`, `fileDragExited`, `fileDropped`, `tileSelected(WidgetID)`, `back`,
  `editingBegan`, `editingEnded`, `escape`, `resignedKey`, `shortcut(WidgetID)`. (Show/Hide Notch is
  configuration — `NotchConfiguration.isVisible` — not a state-machine input.)
- **Outputs:** the new state plus effects (`startHoverTimer`, `startGraceTimer`, `cancelTimers`,
  `makeKey`, `resignKey`). `NotchController` executes the effects with one-shot
  cancellable `Task`s — the only timers in the notch, and they exist only during a transition.

### 4.5 Persistence
- UI preferences: `UserDefaults` via `Preferences` (`@Observable`), keys namespaced in one enum.
- Content: one JSON file per widget in `~/Library/Containers/<bundle-id>/Data/Library/Application
  Support/<AppName>/` (sandboxed path; `AppPaths` resolves it):
  `shelf.json`, `notes.json`, `reminders.json`, each `{ "version": 1, "items": [...] }`.
- `JSONFileStore` writes atomically (`Data.write(options: .atomic)`) on a background queue,
  debounced 0.5 s, and flushes synchronously on `applicationWillTerminate` and on fold.
- A file that fails to decode is renamed `<name>.corrupt-<timestamp>.json` and the store starts
  empty (logged). Schema `version` enables future migrations.

### 4.6 Data model

```swift
struct ShelfItem: Codable, Identifiable { let id: UUID; var bookmark: Data; var displayName: String; let addedAt: Date }
struct Note:      Codable, Identifiable { let id: UUID; var text: String; let createdAt: Date; var updatedAt: Date }
struct Reminder:  Codable, Identifiable { let id: UUID; var text: String; var fireDate: Date; var status: Status; let createdAt: Date
                                          enum Status: String, Codable { case pending, done } }
```

### 4.7 Reminder scheduling
- `ReminderScheduler` protocol (`schedule`, `cancel`, `pendingIDs`, `requestAuthorization`) with a
  `UNUserNotificationCenter` implementation and an in-memory fake for tests.
- One notification request per reminder; request identifier = `reminder.id.uuidString`;
  category `REMINDER` with actions `DONE` and `SNOOZE`.
- **Reconciliation on launch:** schedule any pending, future reminder with no request; remove
  requests with no matching pending reminder; mark pending reminders whose `fireDate` has passed
  as overdue (they stay pending, flagged in UI).
- **Overdue dot while running:** one non-repeating timer for the soonest pending `fireDate`,
  re-armed whenever the reminder set changes. No periodic timers.
- Snooze: `fireDate = now + snoozeLength`, reschedule. Done: `status = .done`, cancel request,
  remove from list.

### 4.8 Global shortcuts
Carbon `RegisterEventHotKey` (works in the sandbox, needs no Accessibility permission), wrapped in
a small `HotKeyCenter` in the app target. Defaults unset; user records them in Settings.

## 5. Visual design
- **Solid black** (default): pure black shape, white/grey text, accent colour for highlights.
  Cheapest to render.
- **Liquid Glass:** macOS 26 glass material on the expanded shape; pill stays black-edged so it
  still reads as part of the bezel. Costs GPU for live blur only while visible.
- Shape and motion: `SideNotchShape` (concave flares into the bezel),
  springs (`unfold` 0.42/0.78, `contents` 0.36/0.82), staggered tile entrance, Reduce Motion respected.
- Metrics (`NotchMetrics`, scaled by pill size S/M/L, M shown):
  folded pill 6 × 72 pt; tiles column 64 pt deep, 52 pt per tile; widget panels 320 × 420 pt.

## 6. Error handling
| Situation | Behaviour |
|---|---|
| Chosen display disconnected | Fall back to main display; restore when it returns |
| Bookmark can't be resolved | Shelf item shown as "Missing", removable |
| Bookmark is stale but resolvable | Re-create bookmark, save |
| Notification permission denied | Reminders widget shows an inline banner with a button to System Settings; reminders still saved and shown in-app, overdue dot still works |
| JSON decode failure | Quarantine file, start empty, log error |
| Disk write failure | Log, keep in-memory state, retry on next change |
| Drag-out cancelled / rejected | Item stays on shelf |
| Launch-at-login registration fails | Toggle reverts, inline error text in Settings |

Logging via `os.Logger` (subsystem = bundle ID; categories `notch`, `shelf`, `notes`, `reminders`, `persistence`).

## 7. Performance budget (relaxed)
Measured on the release build:
- **Idle (folded, nothing due):** < 0.5 % CPU averaged over 60 s; < 80 MB physical footprint.
- **No periodic timers** anywhere while folded (the single next-reminder timer excepted).
- Expanded: CPU returns to idle levels within 1 s of folding; thumbnails released on fold.
- Unfold/fold animations smooth (no dropped frames visible on a 120 Hz display).
- Tools: Activity Monitor (CPU, Energy Impact, Idle Wake Ups), `footprint <pid>`, Instruments
  Time Profiler before each milestone is closed.

## 8. Testing strategy
- **Swift Testing** (`import Testing`) in the package; run with `swift test` from `Packages/Modules`
  for a fast loop without Xcode.
- Unit tests: `NotchStateMachine` (every transition + effects), `NotchGeometry`/`NotchPlacement`
  (clamping, left/right, display fallback via `ScreenDescribing` fakes), `JSONFileStore`
  (round-trip, debounce, corrupt-file quarantine), each store's logic, `ChecklistText` parser,
  time-chip date maths (incl. "Tonight" after 20:00, DST), reminder reconciliation against a fake
  scheduler.
- App level: `make run` smoke check each milestone; an XCTest host target arrives with CI in M6.
- Manual checklist per milestone for window-server behaviour that unit tests can't cover
  (hover, drag in/out, full screen, multiple displays).

## 9. Naming & project configuration
- **Single source of truth:** `Config/Branding.xcconfig`
  ```
  APP_NAME = SideNotch
  BUNDLE_ID_PREFIX = com.example
  ```
  `project.yml` uses generic names (project `App`, target `App`) and sets
  `PRODUCT_NAME = $(APP_NAME)`, `PRODUCT_BUNDLE_IDENTIFIER = $(BUNDLE_ID_PREFIX).$(APP_NAME:lower)`.
  Code reads the name via `AppIdentity.current.name` (module `AppInfo`, from `CFBundleDisplayName`). The Makefile reads `APP_NAME` from the
  xcconfig for the DMG name. Renaming = edit two lines, regenerate.
- **XcodeGen** generates `App.xcodeproj` (git-ignored). Pinned version installed to `.tools/` by
  `Scripts/bootstrap.sh` (no Homebrew on this machine).
- Swift 6 language mode; UI types `@MainActor`. Deployment target macOS 26.0.
- App Sandbox **on**. Entitlements: `app-sandbox`, `files.bookmarks.app-scope`,
  `files.user-selected.read-write` (notes export), `network.client` (Sparkle, M6) — each added
  in the milestone that needs it; M1 has only `app-sandbox`.
- Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) for development and release.
- `Makefile` targets: `bootstrap`, `generate`, `build`, `test`, `run`, `release`, `dmg` (M6).

## 10. Distribution (M6)
- Unsigned (ad-hoc) universal build, packaged as a DMG, published on GitHub Releases.
- README explains the one-time `xattr -dr com.apple.quarantine` step.
- Sparkle 2 auto-update with EdDSA-signed appcast hosted on GitHub; daily check. Sandbox requires
  Sparkle's installer launcher XPC service (`SUEnableInstallerLauncherService`).
- GitHub Actions CI: build + `swift test` on every push; release workflow builds the DMG and appcast.

## 11. Milestones

| # | Scope | Done when |
|---|---|---|
| **M1** | Project scaffold, modules skeleton, notch shell: pill, hover → tiles → placeholder widget panels, fold rules, editing lock plumbing, left/right edge, ⌥-drag offset, display choice, full-screen hide with live strip, menu bar item, Settings window with General tab (edge, display, launch at login) | Pill behaves per §3.1–3.2 with placeholder widgets; idle budget met; state machine + geometry tested |
| **M2** | Shelf widget (§3.3), JSONFileStore | Drag in/out, persistence, missing items, thumbnails |
| **M3** | Notes widget (§3.4) | Notes CRUD, checkboxes, autosave, undo |
| **M4** | Reminders widget (§3.5), scheduler, overdue dot | Chips/custom, notifications with actions, reconciliation |
| **M5** | Full Settings (§3.6), Liquid Glass style, shortcuts, widget reorder | All settings functional |
| **M6** | Packaging: DMG, Sparkle, CI, README, notices | A downloaded DMG installs, runs, and self-updates |

## 12. Risks
- **Transparent-window event routing** (live strip in full screen) — mitigated by the α≈0.01 fill;
  verified early in M1.
- **Non-activating panel + text input** — typing in a non-activating key panel is the standard
  Spotlight-style pattern, but IME and ⌘Z/⌘C need checking in M3.
- **Sparkle in a sandboxed, unsigned app** — XPC installer service configuration; spike at start of M6.
- **Ad-hoc signing** changes identity per build; the only TCC-style grant is Notifications
  (keyed by bundle ID), so the impact is expected to be low.
