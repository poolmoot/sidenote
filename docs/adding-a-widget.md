# Adding (or removing) a widget

A widget is a self-contained mini app in the notch. This is the whole procedure; if a step here doesn't work, that's a bug in the seam, not in your feature.

## The plug

`NotchWidgetAPI` is all a widget knows about the notch:

```swift
@MainActor
public protocol NotchWidget: AnyObject {
    var id: WidgetID { get }
    var title: String { get }
    var systemImage: String { get }          // SF Symbol for the tile
    var expandedSize: CGSize { get }         // width = depth from the edge, height = along it
    var acceptsFileDrops: Bool { get }       // true → a file drag opens this widget
    var badge: WidgetBadge? { get }          // .dot shows on the folded pill
    func makeExpandedView(context: WidgetContext) -> AnyView
    func handleFileDrop(_ urls: [URL]) -> Bool   // false = rejected
}
```

`WidgetContext` gives the view two things back: `setEditing(_:)` (hold the notch open while a text field has focus) and `close()`.

## Steps

1. **Create the module** `Packages/Modules/Sources/<Name>Feature/` with, at minimum:
   - `<Thing>.swift` — the model plus a `<Thing>Document { version: 1, items }` for saving.
   - `<Name>Store.swift` — `@MainActor @Observable final class`, owns the data and a `JSONFileStore`, exposes intent methods (`add`, `remove`, …) and `flush()`.
   - `<Name>Widget.swift` — conforms to `NotchWidget`, holds the store, returns its view.
   - `<Name>View.swift` — SwiftUI, reads the store, calls intent methods. No disk access, no geometry.
2. **Register the module** in `Packages/Modules/Package.swift`: a `.library` product and a `.target` whose dependencies are only `NotchWidgetAPI`, `Persistence`, `DesignSystem`, `AppInfo` — plus a `.testTarget`. SwiftPM rejects an empty target, so add the module in the same commit as its first file.
3. **Add the product** to the `App` target's `dependencies` in `project.yml`.
4. **Wire it** in `App/Sources/AppEnvironment.swift`: build the store with a `JSONFileStore` at `AppPaths.<name>File`, build the widget, and put it in the `widgets` array passed to `NotchController`. Add its `flush()` to the terminate path. That's also the one and only place this widget needs to be listed at all: `Preferences` is constructed *from* `widgets.map(\.id)` (`Preferences(knownWidgetIDs:)`), so the Widgets and Shortcuts tabs, and a saved list from before this widget existed, all pick it up automatically — nothing in `SettingsFeature` names it.
5. **Add an id**: a `public static let` constant on `NotchWidgetAPI.WidgetID` (e.g. `public static let <name> = WidgetID(rawValue: "<name>")`) — see the note at the end.
6. **Write the tests first**, in `Packages/Modules/Tests/<Name>FeatureTests/`. Store logic, parsing and date maths are all testable without a window; inject a clock, a calendar and any system service behind a protocol so tests never touch the real thing.

That's it. The notch discovers the widget from the array: it gets a tile, a panel, the editing lock, file drops (if it wants them) and the badge with no further changes.

## Removing a widget

Delete the module folder and its tests, its product/target in `Package.swift`, its line in `project.yml`, its two lines in `AppEnvironment`, and its `WidgetID` constant. Nothing else in the codebase names it — removing it from the `widgets` array is also what removes it from `Preferences.knownWidgetIDs`, since that's derived from the array, not maintained separately. Its saved JSON file stays on disk harmlessly until deleted, and any shortcut assignment for it is silently ignored (`NotchStateMachine` only reacts to a `.shortcut(id)` for a widget it still holds and has enabled).

## House rules a new widget must follow

- **No polling.** Nothing that ticks while the notch is folded. A view may use one `TimelineView` while it is open.
- **Nothing expensive in `body`.** Parse, sort and derive in the store; the view renders.
- **One source of truth.** Never mirror store data in `@State` — bind through the store, or a toggle will silently revert on the next keystroke (this is a bug we shipped once already).
- **Hold the editing lock** exactly while a text field has focus, and release it in `onDisappear`.
- **Save on change, flush on close.** `flush()` in the view's `onDisappear` and in the app's terminate path.
- **Never type the app's name** in Swift; use `AppIdentity.current.name`.
- **Clicks:** any AppKit view over SwiftUI controls swallows their clicks; keep tap targets on top, give them `.contentShape`, and override `acceptsFirstMouse` when the panel may be non-key.

## Checks before you commit

```bash
make test     # every target must pass
make build    # no warnings from our code
grep -rnE "Timer\(|scheduledTimer|addGlobalMonitor|addLocalMonitor|repeatForever|CVDisplayLink" Packages/Modules/Sources App/Sources || echo "no polling"
```

Then run the app (`make run`) and check the widget by hand: hover opens it, typing doesn't fold it, Esc folds it, and it survives a quit and relaunch.

## Note on `WidgetID`

`WidgetID` is a string-backed identifier (`RawRepresentable` over `String`), not a fixed enum — a new widget declares its own `public static let` constant rather than editing a shared case list. It exists so the notch can persist "which widget is open", match drops to a widget, and store which widgets are enabled/ordered and which shortcuts are assigned, all without every widget module needing to touch one shared type. `Preferences` doesn't hardcode a list of ids anywhere — its `knownWidgetIDs` is passed in by `AppEnvironment` (`Preferences(knownWidgetIDs: widgets.map(\.id))`), reusing the one real source of truth for "which widgets does this app have" that already exists for `NotchController`.
