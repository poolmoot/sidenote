# SideNotch M1 — Notch Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running menu-bar app whose black pill sits on the left or right screen edge, unfolds on hover into three tiles, opens placeholder widget panels, and folds back — with zero polling.

**Architecture:** A thin AppKit app target composes a local Swift package (`Packages/Modules`) of small modules. `NotchKit` owns the window: a fixed, mostly transparent full-height `NSPanel` strip whose only live region (`hotRect`) receives hover (one `NSTrackingArea`) and file drags; a pure `NotchStateMachine` decides every transition and `NotchController` performs its effects. SwiftUI draws the shape and content from rects the controller computes.

**Tech Stack:** Swift 6, SwiftUI + AppKit, macOS 26, Swift Package Manager, Swift Testing, XcodeGen 2.46.0 (built from source), `make`.

**Spec:** `docs/superpowers/specs/2026-09-19-sidenotch-design.md` (M1 row of §11; behaviour in §3.1–3.2 and §3.6; architecture in §4.1–4.4; naming in §9).

## Global Constraints

- Deployment target **macOS 26.0**; package `// swift-tools-version: 6.2` with `platforms: [.macOS(.v26)]`; Xcode `SWIFT_VERSION: "6.0"`.
- The app name is written **only** in `Config/Branding.xcconfig` (`APP_NAME = SideNotch`, `BUNDLE_ID_PREFIX = com.example`). Swift reads it via `AppIdentity.current.name`. Never type the name anywhere else.
- Module rules: feature modules never import each other or `NotchKit`; `NotchKit` knows widgets only through `NotchWidgetAPI`; only the `App` target composes modules.
- **No polling:** no repeating timers, no `NSEvent` global/local monitors, no cursor polling. The only timers are the one-shot hover delay (150 ms) and fold grace (250 ms).
- Ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`), App Sandbox **on** (only the `app-sandbox` entitlement in M1), hardened runtime on.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- The repo path contains spaces (`/Users/bamsefar/Desktop/Mac app note taker`): quote it in shell commands. All commands below run from the repo root.
- Every commit message ends with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- SwiftPM rejects a target with no source files, so each task adds a module to `Package.swift` in the same step that gives it its first file. Each task shows the complete `Package.swift` for that point.

## File Structure

```
.
├── Makefile                      make bootstrap / generate / build / test / run / clean
├── project.yml                   XcodeGen spec (generic names; identity comes from Branding.xcconfig)
├── README.md
├── Config/
│   ├── Branding.xcconfig         APP_NAME + BUNDLE_ID_PREFIX — the only place the name lives
│   └── App.entitlements          app-sandbox
├── Scripts/bootstrap.sh          builds pinned XcodeGen from source into .tools/
├── App/Sources/                  thin shell
│   ├── AppDelegate.swift         entry point (explicit main), builds AppEnvironment
│   ├── AppEnvironment.swift      composition root; pushes Preferences into NotchController
│   ├── MainMenu.swift            hidden app + Edit menus (⌘, ⌘Q ⌘C ⌘V ⌘Z)
│   ├── StatusItemController.swift  menu bar icon + menu (also the pill's right-click menu)
│   ├── SettingsWindowController.swift  normal NSWindow hosting SettingsView
│   └── PlaceholderWidget.swift   stand-in widgets until M2–M4
└── Packages/Modules/
    ├── Package.swift
    ├── Sources/
    │   ├── AppInfo/AppIdentity.swift              name / bundle ID / version / Logger
    │   ├── NotchWidgetAPI/NotchWidget.swift       WidgetID, WidgetBadge, WidgetContext, NotchWidget
    │   ├── DesignSystem/{NotchMotion,Palette}.swift
    │   ├── NotchKit/
    │   │   ├── State/NotchStateMachine.swift      NotchState, NotchEvent, NotchEffect, NotchStateMachine
    │   │   ├── Geometry/NotchEdge.swift
    │   │   ├── Geometry/NotchMetrics.swift        NotchShapeSize, NotchMetrics
    │   │   ├── Geometry/NotchGeometry.swift       pure placement maths
    │   │   ├── Geometry/NSScreen+Display.swift    stable display UUID
    │   │   ├── Window/NotchPanel.swift            the NSPanel (Esc, right-click, ⌥-drag, key handling)
    │   │   ├── Window/NotchContainerView.swift    hotRect: hit test, tracking area, drops; NotchHostingView
    │   │   ├── Views/SideNotchShape.swift
    │   │   ├── Views/NotchViewModel.swift
    │   │   ├── Views/NotchRootView.swift
    │   │   ├── Views/TilesView.swift
    │   │   ├── Views/ExpandedWidgetView.swift
    │   │   ├── FullScreen/FullScreenDetector.swift
    │   │   ├── FullScreen/FullScreenObserver.swift
    │   │   ├── NotchConfiguration.swift
    │   │   └── NotchController.swift
    │   └── SettingsFeature/{Preferences,LaunchAtLogin,GeneralSettingsView,SettingsView}.swift
    └── Tests/
        ├── AppInfoTests/AppIdentityTests.swift
        ├── NotchKitTests/{NotchStateMachineTests,NotchGeometryTests,SideNotchShapeTests,NotchContainerViewTests,FullScreenDetectorTests}.swift
        └── SettingsFeatureTests/PreferencesTests.swift
```

`.gitignore` (already committed) ignores `*.xcodeproj/`, `build/`, `.build/`, `.swiftpm/` and `.tools/`.

---

### Task 1: Tooling, project scaffold and the `AppInfo` module

Sets up everything needed to build and test: XcodeGen bootstrap, Makefile, branding, entitlements, the package with its first module, and an app that launches (and shows nothing yet).

**Files:**
- Create: `Scripts/bootstrap.sh`, `Makefile`, `Config/Branding.xcconfig`, `Config/App.entitlements`, `project.yml`, `App/Sources/AppDelegate.swift`, `Packages/Modules/Package.swift`, `Packages/Modules/Sources/AppInfo/AppIdentity.swift`, `README.md`
- Test: `Packages/Modules/Tests/AppInfoTests/AppIdentityTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public struct AppIdentity` with `name: String`, `bundleIdentifier: String`, `version: String`, `init(infoDictionary: [String: Any])`, `static let current`, `func logger(_ category: String) -> Logger`. Make targets `bootstrap`, `generate`, `build`, `test`, `run`, `clean`.

- [ ] **Step 1: Create a branch**

```bash
git switch -c m1-notch-shell
```

- [ ] **Step 2: Write the bootstrap script and Makefile**

`Scripts/bootstrap.sh` (then `chmod +x Scripts/bootstrap.sh`):

```bash
#!/usr/bin/env bash
# Builds the pinned XcodeGen from source into .tools/ (git-ignored).
# From source rather than a downloaded binary: no Homebrew needed, nothing unsigned to trust.
set -euo pipefail

VERSION="${1:?usage: Scripts/bootstrap.sh <xcodegen-version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.tools/src/XcodeGen"
BIN="$SRC/.build/release/xcodegen"

if [[ -x "$BIN" ]] && "$BIN" --version | grep -q "$VERSION"; then
  echo "XcodeGen $VERSION is already built."
  exit 0
fi

echo "Building XcodeGen $VERSION from source (takes a minute or two, once)…"
rm -rf "$SRC"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$VERSION" \
  https://github.com/yonaskolb/XcodeGen.git "$SRC"
swift build --quiet -c release --package-path "$SRC" --product xcodegen
"$BIN" --version
```

`Makefile` (recipe lines are indented with a **tab**, not spaces):

```make
# Everyday commands. Run `make` with no target to see them.

XCODEGEN_VERSION := 2.46.0
XCODEGEN := .tools/src/XcodeGen/.build/release/xcodegen
APP_NAME := $(shell sed -n 's/^APP_NAME *= *//p' Config/Branding.xcconfig)
CONFIG ?= Debug
ARCH := $(shell uname -m)
DERIVED_DATA := build/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIG)/$(APP_NAME).app

.PHONY: help bootstrap generate build test run clean

help:
	@echo "make bootstrap  build the pinned XcodeGen into .tools/ (once)"
	@echo "make generate   generate App.xcodeproj from project.yml"
	@echo "make build      build $(APP_NAME).app ($(CONFIG))"
	@echo "make test       run the module tests"
	@echo "make run        build, quit any running copy, and launch"
	@echo "make clean      remove build products and the generated project"

bootstrap:
	@Scripts/bootstrap.sh $(XCODEGEN_VERSION)

generate:
	@test -x $(XCODEGEN) || $(MAKE) bootstrap
	@$(XCODEGEN) generate --quiet

build: generate
	xcodebuild -project App.xcodeproj -scheme App -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS,arch=$(ARCH)' build -quiet

test:
	swift test --package-path Packages/Modules

run: build
	-@pkill -x "$(APP_NAME)"
	open "$(APP_PATH)"

clean:
	rm -rf build App.xcodeproj
```

- [ ] **Step 3: Build XcodeGen**

Run: `make bootstrap`
Expected: ends with `Version: 2.46.0` (about 80 s the first time). Running it again prints `XcodeGen 2.46.0 is already built.`

- [ ] **Step 4: Write the failing AppIdentity test and the package manifest**

`Packages/Modules/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppInfo", targets: ["AppInfo"]),
    ],
    targets: [
        .target(name: "AppInfo"),
        .testTarget(name: "AppInfoTests", dependencies: ["AppInfo"]),
    ]
)
```

`Packages/Modules/Tests/AppInfoTests/AppIdentityTests.swift`:

```swift
import Testing
@testable import AppInfo

struct AppIdentityTests {
    @Test func prefersDisplayName() {
        let identity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Display",
            "CFBundleName": "Bundle",
            "CFBundleIdentifier": "com.example.display",
            "CFBundleShortVersionString": "1.2.3",
        ])
        #expect(identity.name == "Display")
        #expect(identity.bundleIdentifier == "com.example.display")
        #expect(identity.version == "1.2.3")
    }

    @Test func fallsBackToBundleNameWhenDisplayNameIsEmpty() {
        let identity = AppIdentity(infoDictionary: ["CFBundleDisplayName": "", "CFBundleName": "Bundle"])
        #expect(identity.name == "Bundle")
    }

    @Test func hasSafeDefaultsWithNoInfoDictionary() {
        let identity = AppIdentity(infoDictionary: [:])
        #expect(identity.name == "App")
        #expect(identity.bundleIdentifier == "local.app")
        #expect(identity.version == "0.0.0")
    }
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `make test`
Expected: FAIL — `error: 'modules': target 'AppInfo' referenced in product 'AppInfo' is empty`.

- [ ] **Step 6: Implement AppIdentity**

`Packages/Modules/Sources/AppInfo/AppIdentity.swift`:

```swift
import Foundation
import os

/// Who this app is, read from its Info.plist.
///
/// The app's name is written in exactly one place — `Config/Branding.xcconfig` — and reaches
/// Swift only through here, so renaming the app never means editing code.
public struct AppIdentity: Sendable, Equatable {
    public let name: String
    public let bundleIdentifier: String
    public let version: String

    public init(infoDictionary: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let string = infoDictionary[key] as? String, !string.isEmpty else { return nil }
            return string
        }
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? "App"
        bundleIdentifier = value("CFBundleIdentifier") ?? "local.app"
        version = value("CFBundleShortVersionString") ?? "0.0.0"
    }

    public static let current = AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])

    public func logger(_ category: String) -> Logger {
        Logger(subsystem: bundleIdentifier, category: category)
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `make test`
Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 8: Add branding, entitlements, the project spec and the app entry point**

`Config/Branding.xcconfig`:

```
// The app's identity — the ONLY place its name is written.
// After editing, run `make generate` (or any make target) and rebuild.
// Changing BUNDLE_ID_PREFIX or APP_NAME gives the app a new identity: fresh preferences and data.

APP_NAME = SideNotch
BUNDLE_ID_PREFIX = com.example
```

`Config/App.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
```

`project.yml` (M1's first version — Task 10 adds the other module products):

```yaml
# Generates App.xcodeproj (git-ignored). Run `make generate` after editing this file.
# Names here are deliberately generic: the product name and bundle ID come from
# Config/Branding.xcconfig, so renaming the app never touches this file.
name: App
options:
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true

configFiles:
  Debug: Config/Branding.xcconfig
  Release: Config/Branding.xcconfig

settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    # Ad-hoc signing: no Apple Developer account needed. See the spec, §9–10.
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES

packages:
  Modules:
    path: Packages/Modules

targets:
  App:
    type: application
    platform: macOS
    sources:
      - path: App/Sources
    settings:
      base:
        PRODUCT_NAME: $(APP_NAME)
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).$(APP_NAME:lower)
        PRODUCT_MODULE_NAME: App
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: $(APP_NAME)
        INFOPLIST_KEY_LSUIElement: YES
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.productivity
        CODE_SIGN_ENTITLEMENTS: Config/App.entitlements
    dependencies:
      - package: Modules
        product: AppInfo
    scheme: {}
```

`App/Sources/AppDelegate.swift` (first version — Task 10 replaces it):

```swift
import AppKit
import AppInfo

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Explicit entry point: without a main nib, `NSApplicationMain` would never create the delegate.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIdentity.current.logger("app").info("Launched \(AppIdentity.current.name, privacy: .public)")
    }
}
```

- [ ] **Step 9: Build and check the bundle identity**

Run: `make build && plutil -p build/DerivedData/Build/Products/Debug/SideNotch.app/Contents/Info.plist | grep -E "CFBundleName|CFBundleDisplayName|CFBundleIdentifier|LSUIElement"`
Expected:
```
  "CFBundleDisplayName" => "SideNotch"
  "CFBundleIdentifier" => "com.example.sidenotch"
  "CFBundleName" => "SideNotch"
  "LSUIElement" => true
```
Then run: `codesign -d --entitlements - build/DerivedData/Build/Products/Debug/SideNotch.app 2>&1 | grep sandbox`
Expected: `[Key] com.apple.security.app-sandbox`.

- [ ] **Step 10: Launch it**

Run: `make run && sleep 2 && pgrep -x SideNotch && pkill -x SideNotch`
Expected: a PID is printed; no Dock icon appeared; nothing visible on screen yet.

- [ ] **Step 11: Add the README**

`README.md`:

````markdown
# SideNotch

A side notch for macOS: a small black pill on the edge of your screen that unfolds into three
mini apps — a file shelf, quick notes and reminders.

> **SideNotch is a working name.** The name is written only in `Config/Branding.xcconfig`.
> Change `APP_NAME` there and run `make run`; nothing else needs editing.

## Requirements

- macOS 26 or later
- Xcode 26 (`xcode-select -p` should print a path inside `Xcode.app`)

## Getting started

```bash
make bootstrap   # once: builds the pinned XcodeGen into .tools/
make run         # generate the project, build and launch
make test        # module tests (Swift Testing)
```

`App.xcodeproj` is generated from `project.yml` and git-ignored: run `make generate` and open it
in Xcode if you like, but make project changes in `project.yml`.

## Layout

| Path | What lives there |
|---|---|
| `App/Sources` | Thin app shell: composition root, menu bar item, Settings window |
| `Packages/Modules` | All logic, one Swift module per concern, each with its own tests |
| `Config` | Branding (name, bundle ID) and entitlements |
| `Scripts` | Tooling |
| `docs/superpowers` | Design spec and implementation plans |

## Design

See [the design spec](docs/superpowers/specs/2026-09-19-sidenotch-design.md).
````

- [ ] **Step 12: Commit**

```bash
git add Scripts Makefile Config project.yml App Packages README.md
git commit -m "Scaffold project: XcodeGen bootstrap, Makefile, AppInfo module

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Widget contract and the notch state machine

The pure core of the notch: every rule from spec §3.1 as a value type with no AppKit and no clock.

**Files:**
- Create: `Packages/Modules/Sources/NotchWidgetAPI/NotchWidget.swift`, `Packages/Modules/Sources/NotchKit/State/NotchStateMachine.swift`
- Modify: `Packages/Modules/Package.swift`
- Test: `Packages/Modules/Tests/NotchKitTests/NotchStateMachineTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `NotchWidgetAPI`: `enum WidgetID: String { case shelf, notes, reminders }`, `enum WidgetBadge { case dot }`, `@MainActor struct WidgetContext { setEditing: (Bool) -> Void; close: () -> Void }`, `@MainActor protocol NotchWidget: AnyObject { id, title, systemImage, expandedSize: CGSize, acceptsFileDrops, badge, makeExpandedView(context:) -> AnyView, handleFileDrop(_ urls: [URL]) -> Bool }` with defaults for `acceptsFileDrops` (false), `badge` (nil) and `handleFileDrop` (false).
  - `NotchKit`: `enum NotchState { folded, tiles, expanded(WidgetID, dropTarget: Bool) }` with `isExpanded` and `expandedWidget`; `enum NotchEvent` (14 cases, see code); `enum NotchEffect { startHoverTimer, startGraceTimer, cancelTimers, makeKey, resignKey }`; `struct NotchStateMachine { init(dropWidget: WidgetID?); state; isPointerInside; isEditing; mutating func handle(_:) -> [NotchEffect] }`.

- [ ] **Step 1: Update the manifest and add the widget contract**

`Packages/Modules/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppInfo", targets: ["AppInfo"]),
        .library(name: "NotchWidgetAPI", targets: ["NotchWidgetAPI"]),
        .library(name: "NotchKit", targets: ["NotchKit"]),
    ],
    targets: [
        .target(name: "AppInfo"),
        .target(name: "NotchWidgetAPI"),
        .target(name: "NotchKit", dependencies: ["NotchWidgetAPI"]),
        .testTarget(name: "AppInfoTests", dependencies: ["AppInfo"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit", "NotchWidgetAPI"]),
    ]
)
```

`Packages/Modules/Sources/NotchWidgetAPI/NotchWidget.swift`:

```swift
import SwiftUI

/// The three mini apps. The raw value is persisted, so never rename a case.
public enum WidgetID: String, CaseIterable, Codable, Sendable {
    case shelf
    case notes
    case reminders
}

/// A small mark the folded pill shows on behalf of a widget (e.g. an overdue reminder).
public enum WidgetBadge: Equatable, Sendable {
    case dot
}

/// What the notch hands a widget's view, so the view can talk back without knowing about windows.
@MainActor
public struct WidgetContext {
    /// Report that a text field gained (`true`) or lost (`false`) focus. While editing, the notch
    /// does not fold when the pointer leaves it.
    public let setEditing: (Bool) -> Void
    /// Fold the notch, e.g. after an action that finishes the user's task.
    public let close: () -> Void

    public init(setEditing: @escaping (Bool) -> Void, close: @escaping () -> Void) {
        self.setEditing = setEditing
        self.close = close
    }
}

/// The only contract between the notch and a mini app. Feature modules conform to this and never
/// import NotchKit.
@MainActor
public protocol NotchWidget: AnyObject {
    var id: WidgetID { get }
    var title: String { get }
    /// An SF Symbol name.
    var systemImage: String { get }
    /// The expanded panel: `width` is the depth in from the screen edge, `height` the length along it.
    var expandedSize: CGSize { get }
    var acceptsFileDrops: Bool { get }
    var badge: WidgetBadge? { get }
    func makeExpandedView(context: WidgetContext) -> AnyView
    /// Called only when `acceptsFileDrops` is true. Returns whether the drop was taken.
    func handleFileDrop(_ urls: [URL]) -> Bool
}

public extension NotchWidget {
    var acceptsFileDrops: Bool { false }
    var badge: WidgetBadge? { nil }
    func handleFileDrop(_ urls: [URL]) -> Bool { false }
}
```

- [ ] **Step 2: Write the failing state machine tests**

`Packages/Modules/Tests/NotchKitTests/NotchStateMachineTests.swift`:

```swift
import Testing
import NotchWidgetAPI
@testable import NotchKit

struct NotchStateMachineTests {
    private func machine(dropWidget: WidgetID? = .shelf) -> NotchStateMachine {
        NotchStateMachine(dropWidget: dropWidget)
    }

    /// A machine already showing tiles with the pointer inside.
    private func tiles() -> NotchStateMachine {
        var m = machine()
        _ = m.handle(.pointerEntered)
        _ = m.handle(.hoverDelayElapsed)
        return m
    }

    /// A machine showing the notes widget with the pointer inside.
    private func expandedNotes() -> NotchStateMachine {
        var m = tiles()
        _ = m.handle(.tileSelected(.notes))
        return m
    }

    @Test func startsFolded() {
        let m = machine()
        #expect(m.state == .folded)
        #expect(!m.isPointerInside)
        #expect(!m.isEditing)
    }

    @Test func pointerEnteringFoldedStartsHoverTimer() {
        var m = machine()
        #expect(m.handle(.pointerEntered) == [.startHoverTimer])
        #expect(m.state == .folded)
    }

    @Test func hoverDelayUnfoldsToTiles() {
        var m = machine()
        _ = m.handle(.pointerEntered)
        #expect(m.handle(.hoverDelayElapsed) == [])
        #expect(m.state == .tiles)
    }

    @Test func leavingBeforeHoverDelayCancelsAndStaysFolded() {
        var m = machine()
        _ = m.handle(.pointerEntered)
        #expect(m.handle(.pointerExited) == [.cancelTimers])
        _ = m.handle(.hoverDelayElapsed)
        #expect(m.state == .folded)
    }

    @Test func leavingTilesStartsGraceThenFolds() {
        var m = tiles()
        #expect(m.handle(.pointerExited) == [.startGraceTimer])
        #expect(m.handle(.graceElapsed) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
    }

    @Test func returningDuringGraceCancelsFold() {
        var m = tiles()
        _ = m.handle(.pointerExited)
        #expect(m.handle(.pointerEntered) == [.cancelTimers])
        #expect(m.handle(.graceElapsed) == [])
        #expect(m.state == .tiles)
    }

    @Test func selectingTileExpandsAndTakesKey() {
        var m = tiles()
        #expect(m.handle(.tileSelected(.notes)) == [.cancelTimers, .makeKey])
        #expect(m.state == .expanded(.notes, dropTarget: false))
    }

    @Test func selectingTileWhileFoldedIsIgnored() {
        var m = machine()
        #expect(m.handle(.tileSelected(.notes)) == [])
        #expect(m.state == .folded)
    }

    @Test func leavingExpandedWithoutEditingFoldsAfterGrace() {
        var m = expandedNotes()
        #expect(m.handle(.pointerExited) == [.startGraceTimer])
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func editingLockKeepsExpandedWhenPointerLeaves() {
        var m = expandedNotes()
        #expect(m.handle(.editingBegan) == [.cancelTimers])
        #expect(m.handle(.pointerExited) == [])
        #expect(m.handle(.graceElapsed) == [])
        #expect(m.state == .expanded(.notes, dropTarget: false))
    }

    @Test func endingEditOutsideStartsGrace() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        _ = m.handle(.pointerExited)
        #expect(m.handle(.editingEnded) == [.startGraceTimer])
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func endingEditInsideDoesNothing() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.editingEnded) == [])
        #expect(m.state == .expanded(.notes, dropTarget: false))
    }

    @Test func escapeFoldsEvenWhileEditing() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.escape) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
        #expect(!m.isEditing)
    }

    @Test func escapeWhenFoldedIsIgnored() {
        var m = machine()
        #expect(m.handle(.escape) == [])
    }

    @Test func resigningKeyFoldsExpanded() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.resignedKey) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
    }

    @Test func resigningKeyInTilesIsIgnored() {
        var m = tiles()
        #expect(m.handle(.resignedKey) == [])
        #expect(m.state == .tiles)
    }

    @Test func backReturnsToTilesAndGivesUpKey() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.back) == [.resignKey])
        #expect(m.state == .tiles)
        #expect(!m.isEditing)
    }

    @Test func fileDragOpensDropWidgetDirectly() {
        var m = machine()
        #expect(m.handle(.fileDragEntered) == [.cancelTimers])
        #expect(m.state == .expanded(.shelf, dropTarget: true))
    }

    @Test func fileDragIgnoredWithoutDropWidget() {
        var m = machine(dropWidget: nil)
        #expect(m.handle(.fileDragEntered) == [])
        #expect(m.state == .folded)
    }

    @Test func fileDragLeavingClearsHighlightThenFolds() {
        var m = machine()
        _ = m.handle(.fileDragEntered)
        #expect(m.handle(.fileDragExited) == [.startGraceTimer])
        #expect(m.state == .expanded(.shelf, dropTarget: false))
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func droppingClearsHighlightAndStaysOpen() {
        var m = machine()
        _ = m.handle(.fileDragEntered)
        #expect(m.handle(.fileDropped) == [])
        #expect(m.state == .expanded(.shelf, dropTarget: false))
        #expect(m.isPointerInside)
    }

    @Test func shortcutOpensWidgetFromAnywhereAndTogglesClosed() {
        var m = machine()
        #expect(m.handle(.shortcut(.reminders)) == [.cancelTimers, .makeKey])
        #expect(m.state == .expanded(.reminders, dropTarget: false))
        #expect(m.handle(.shortcut(.reminders)) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
    }

    @Test func shortcutSwitchesBetweenWidgets() {
        var m = expandedNotes()
        _ = m.handle(.shortcut(.shelf))
        #expect(m.state == .expanded(.shelf, dropTarget: false))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path Packages/Modules --filter NotchStateMachineTests`
Expected: FAIL — `target 'NotchKit' referenced in product 'NotchKit' is empty`.

- [ ] **Step 4: Implement the state machine**

`Packages/Modules/Sources/NotchKit/State/NotchStateMachine.swift`:

```swift
import NotchWidgetAPI

/// What the notch is showing.
public enum NotchState: Equatable, Sendable {
    case folded
    case tiles
    case expanded(WidgetID, dropTarget: Bool)

    public var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    public var expandedWidget: WidgetID? {
        if case .expanded(let id, _) = self { return id }
        return nil
    }
}

/// Everything that can happen to the notch. Pointer and drag events come from the window,
/// timer events from `NotchController`, the rest from the user.
public enum NotchEvent: Equatable, Sendable {
    case pointerEntered
    case pointerExited
    case hoverDelayElapsed
    case graceElapsed
    case fileDragEntered
    case fileDragExited
    case fileDropped
    case tileSelected(WidgetID)
    case back
    case editingBegan
    case editingEnded
    case escape
    case resignedKey
    case shortcut(WidgetID)
}

/// Side effects the controller must carry out after a transition.
public enum NotchEffect: Equatable, Sendable {
    case startHoverTimer
    case startGraceTimer
    case cancelTimers
    case makeKey
    case resignKey
}

/// The notch's behaviour as a pure value: no AppKit, no timers, no clock. `NotchController`
/// feeds it events and performs the effects it returns, which keeps every rule unit-testable.
public struct NotchStateMachine: Equatable, Sendable {
    public private(set) var state: NotchState = .folded
    public private(set) var isPointerInside = false
    public private(set) var isEditing = false
    /// The widget a file drag opens, or nil when no widget takes files.
    public let dropWidget: WidgetID?

    public init(dropWidget: WidgetID?) {
        self.dropWidget = dropWidget
    }

    public mutating func handle(_ event: NotchEvent) -> [NotchEffect] {
        switch event {
        case .pointerEntered:
            isPointerInside = true
            return state == .folded ? [.startHoverTimer] : [.cancelTimers]

        case .pointerExited:
            isPointerInside = false
            switch state {
            case .folded: return [.cancelTimers]
            case .tiles: return [.startGraceTimer]
            case .expanded: return isEditing ? [] : [.startGraceTimer]
            }

        case .hoverDelayElapsed:
            guard state == .folded, isPointerInside else { return [] }
            state = .tiles
            return []

        case .graceElapsed:
            guard state != .folded, !isPointerInside, !isEditing else { return [] }
            return fold()

        case .fileDragEntered:
            guard let dropWidget else { return [] }
            isPointerInside = true
            state = .expanded(dropWidget, dropTarget: true)
            return [.cancelTimers]

        case .fileDragExited:
            guard case .expanded(let id, true) = state else { return [] }
            isPointerInside = false
            state = .expanded(id, dropTarget: false)
            return [.startGraceTimer]

        case .fileDropped:
            guard case .expanded(let id, true) = state else { return [] }
            isPointerInside = true
            state = .expanded(id, dropTarget: false)
            return []

        case .tileSelected(let id):
            guard state == .tiles else { return [] }
            state = .expanded(id, dropTarget: false)
            return [.cancelTimers, .makeKey]

        case .back:
            guard state.isExpanded else { return [] }
            isEditing = false
            state = .tiles
            return [.resignKey]

        case .editingBegan:
            guard state.isExpanded else { return [] }
            isEditing = true
            return [.cancelTimers]

        case .editingEnded:
            guard isEditing else { return [] }
            isEditing = false
            return state.isExpanded && !isPointerInside ? [.startGraceTimer] : []

        case .escape:
            guard state != .folded else { return [] }
            return fold()

        case .resignedKey:
            guard state.isExpanded else { return [] }
            return fold()

        case .shortcut(let id):
            if state.expandedWidget == id { return fold() }
            isEditing = false
            state = .expanded(id, dropTarget: false)
            return [.cancelTimers, .makeKey]
        }
    }

    private mutating func fold() -> [NotchEffect] {
        state = .folded
        isEditing = false
        return [.cancelTimers, .resignKey]
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Modules --filter NotchStateMachineTests`
Expected: `✔ Test run with 23 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Modules
git commit -m "Add widget contract and notch state machine

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Geometry and metrics

Pure placement maths: where the panel goes, where the shape sits inside it, how big each state is, and which display to use.

**Files:**
- Create: `Packages/Modules/Sources/NotchKit/Geometry/NotchEdge.swift`, `NotchMetrics.swift`, `NotchGeometry.swift`, `NSScreen+Display.swift`
- Test: `Packages/Modules/Tests/NotchKitTests/NotchGeometryTests.swift`

**Interfaces:**
- Consumes: `NotchState`, `WidgetID` (Task 2).
- Produces:
  - `enum NotchEdge: String, CaseIterable, Codable, Identifiable { case left, right }`
  - `struct NotchShapeSize { depth: CGFloat; length: CGFloat }`
  - `struct NotchMetrics` with `static let standard`, fields (`foldedDepth` 6, `foldedBodyLength` 72, `foldedCornerRadius` 3, `tilesDepth` 64, `tileExtent` 52, `gearExtent` 36, `contentPadding` 10, `cornerRadius` 18, `flare` 12, `hoverMargin` 6, `defaultExpandedSize` 320×420) and `shapeSize(for:tileCount:expandedSizes: [WidgetID: CGSize]) -> NotchShapeSize`, `cornerRadius(for:) -> CGFloat`, `panelDepth(expandedSizes: [CGSize]) -> CGFloat`, `contentRect(in: CGRect) -> CGRect`
  - `enum NotchGeometry` with `panelFrame(screenFrame:edge:depth:) -> CGRect`, `shapeRect(panelSize:edge:size:alongOffset:) -> CGRect`, `clampedOffset(_:panelLength:length:) -> CGFloat`, `hotRect(shapeRect:edge:margin:) -> CGRect`, `preferredScreenIndex(displayIDs: [String?], preferred: String?) -> Int?`
  - `extension NSScreen { var displayIdentifier: String? }`

- [ ] **Step 1: Write the failing geometry tests**

`Packages/Modules/Tests/NotchKitTests/NotchGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
import NotchWidgetAPI
@testable import NotchKit

struct NotchGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let size = NotchShapeSize(depth: 64, length: 200)

    @Test func panelHugsRightEdgeFullHeight() {
        let frame = NotchGeometry.panelFrame(screenFrame: screen, edge: .right, depth: 325.5)
        #expect(frame == CGRect(x: 1186, y: 0, width: 326, height: 982))
    }

    @Test func panelHugsLeftEdgeOnSecondaryScreen() {
        let secondary = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let frame = NotchGeometry.panelFrame(screenFrame: secondary, edge: .left, depth: 100)
        #expect(frame == CGRect(x: -1920, y: 100, width: 100, height: 1080))
    }

    @Test func shapeIsCentredOnRightEdgeByDefault() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 982), edge: .right, size: size, alongOffset: 0)
        #expect(rect == CGRect(x: 262, y: 391, width: 64, height: 200))
    }

    @Test func shapeSitsAtZeroOnLeftEdge() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 982), edge: .left, size: size, alongOffset: 0)
        #expect(rect.minX == 0)
    }

    @Test func positiveOffsetMovesShapeDown() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 982), edge: .right, size: size, alongOffset: 100)
        #expect(rect.minY == 491)
    }

    @Test func shapeIsClampedOnScreen() {
        let panel = CGSize(width: 326, height: 982)
        let low = NotchGeometry.shapeRect(panelSize: panel, edge: .right, size: size, alongOffset: 10_000)
        let high = NotchGeometry.shapeRect(panelSize: panel, edge: .right, size: size, alongOffset: -10_000)
        #expect(low.maxY == 982)
        #expect(high.minY == 0)
    }

    @Test func shapeLongerThanPanelDoesNotTrap() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 100), edge: .right, size: size, alongOffset: 0)
        #expect(rect.minY == 0)
    }

    @Test func clampedOffsetLimitsTravel() {
        #expect(NotchGeometry.clampedOffset(1_000, panelLength: 1000, length: 100) == 450)
        #expect(NotchGeometry.clampedOffset(-1_000, panelLength: 1000, length: 100) == -450)
        #expect(NotchGeometry.clampedOffset(20, panelLength: 1000, length: 100) == 20)
    }

    @Test func hotRectGrowsInwardOnly() {
        let shape = CGRect(x: 262, y: 391, width: 64, height: 200)
        #expect(NotchGeometry.hotRect(shapeRect: shape, edge: .right, margin: 6) == CGRect(x: 256, y: 391, width: 70, height: 200))
        let left = CGRect(x: 0, y: 391, width: 64, height: 200)
        #expect(NotchGeometry.hotRect(shapeRect: left, edge: .left, margin: 6) == CGRect(x: 0, y: 391, width: 70, height: 200))
    }

    @Test func preferredScreenMatchesSavedDisplay() {
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: ["A", "B"], preferred: "B") == 1)
    }

    @Test func preferredScreenFallsBackToPrimary() {
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: ["A", "B"], preferred: "gone") == 0)
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: ["A", nil], preferred: nil) == 0)
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: [], preferred: "A") == nil)
    }
}

struct NotchMetricsTests {
    let metrics = NotchMetrics.standard

    @Test func foldedSizeIncludesFlares() {
        let size = metrics.shapeSize(for: .folded, tileCount: 3, expandedSizes: [:])
        #expect(size == NotchShapeSize(depth: 6, length: 72 + 24))
    }

    @Test func tilesLengthGrowsWithTileCount() {
        let three = metrics.shapeSize(for: .tiles, tileCount: 3, expandedSizes: [:])
        let two = metrics.shapeSize(for: .tiles, tileCount: 2, expandedSizes: [:])
        #expect(three.length - two.length == metrics.tileExtent)
        #expect(three.depth == 64)
    }

    @Test func expandedUsesWidgetSizeOrDefault() {
        let custom = metrics.shapeSize(for: .expanded(.notes, dropTarget: false), tileCount: 3,
                                       expandedSizes: [.notes: CGSize(width: 280, height: 300)])
        #expect(custom == NotchShapeSize(depth: 280, length: 324))
        let fallback = metrics.shapeSize(for: .expanded(.shelf, dropTarget: false), tileCount: 3, expandedSizes: [:])
        #expect(fallback == NotchShapeSize(depth: 320, length: 444))
    }

    @Test func panelDepthCoversDeepestStatePlusMargin() {
        #expect(metrics.panelDepth(expandedSizes: [CGSize(width: 320, height: 1), CGSize(width: 280, height: 1)]) == 326)
        #expect(metrics.panelDepth(expandedSizes: []) == 326)
    }

    @Test func contentRectNeverGoesNegative() {
        let folded = metrics.contentRect(in: CGRect(x: 0, y: 0, width: 6, height: 96))
        #expect(folded.width == 0)
        #expect(folded.height == 52)
    }

    @Test func contentRectInsetsByFlareAndPadding() {
        let rect = metrics.contentRect(in: CGRect(x: 100, y: 100, width: 64, height: 200))
        #expect(rect == CGRect(x: 110, y: 122, width: 44, height: 156))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/Modules --filter "NotchGeometryTests|NotchMetricsTests"`
Expected: FAIL — the tests don't compile (`cannot find 'NotchGeometry' in scope` and similar).

- [ ] **Step 3: Implement the geometry types**

`Packages/Modules/Sources/NotchKit/Geometry/NotchEdge.swift`:

```swift
/// Which side of the screen the notch is attached to. The raw value is persisted.
public enum NotchEdge: String, CaseIterable, Codable, Sendable, Identifiable {
    case left
    case right

    public var id: String { rawValue }
}
```

`Packages/Modules/Sources/NotchKit/Geometry/NotchMetrics.swift`:

```swift
import CoreGraphics
import NotchWidgetAPI

/// The size of the notch shape. `depth` runs in from the screen edge; `length` runs along it and
/// includes both concave flares.
public struct NotchShapeSize: Equatable, Sendable {
    public var depth: CGFloat
    public var length: CGFloat

    public init(depth: CGFloat, length: CGFloat) {
        self.depth = depth
        self.length = length
    }
}

/// Every fixed dimension of the notch, in points.
public struct NotchMetrics: Equatable, Sendable {
    public var foldedDepth: CGFloat = 6
    public var foldedBodyLength: CGFloat = 72
    public var foldedCornerRadius: CGFloat = 3
    public var tilesDepth: CGFloat = 64
    public var tileExtent: CGFloat = 52
    public var gearExtent: CGFloat = 36
    public var contentPadding: CGFloat = 10
    public var cornerRadius: CGFloat = 18
    /// Radius of the concave shoulders where the shape meets the bezel.
    public var flare: CGFloat = 12
    /// Extra depth, beyond the shape, that still counts as hovering it.
    public var hoverMargin: CGFloat = 6
    public var defaultExpandedSize = CGSize(width: 320, height: 420)

    public init() {}

    public static let standard = NotchMetrics()

    public func shapeSize(for state: NotchState, tileCount: Int, expandedSizes: [WidgetID: CGSize]) -> NotchShapeSize {
        switch state {
        case .folded:
            return NotchShapeSize(depth: foldedDepth, length: foldedBodyLength + 2 * flare)
        case .tiles:
            let body = 2 * contentPadding + CGFloat(tileCount) * tileExtent + gearExtent
            return NotchShapeSize(depth: tilesDepth, length: body + 2 * flare)
        case .expanded(let id, _):
            let size = expandedSizes[id] ?? defaultExpandedSize
            return NotchShapeSize(depth: size.width, length: size.height + 2 * flare)
        }
    }

    public func cornerRadius(for state: NotchState) -> CGFloat {
        state == .folded ? foldedCornerRadius : cornerRadius
    }

    /// The panel is as deep as the deepest shape any state can take, plus the hover margin.
    public func panelDepth(expandedSizes: [CGSize]) -> CGFloat {
        let deepest = expandedSizes.map(\.width).max() ?? defaultExpandedSize.width
        return max(tilesDepth, deepest) + hoverMargin
    }

    /// Where a state's content goes: the shape minus its flares and padding. Never negative.
    public func contentRect(in shapeRect: CGRect) -> CGRect {
        let dx = contentPadding
        let dy = flare + contentPadding
        return CGRect(
            x: shapeRect.minX + dx,
            y: shapeRect.minY + dy,
            width: max(0, shapeRect.width - 2 * dx),
            height: max(0, shapeRect.height - 2 * dy)
        )
    }
}
```

`Packages/Modules/Sources/NotchKit/Geometry/NotchGeometry.swift`:

```swift
import CoreGraphics

/// Pure placement maths. Panel coordinates have a top-left origin (the container view is flipped,
/// as SwiftUI is), so `y` grows down the screen.
public enum NotchGeometry {
    /// The panel: a strip `depth` wide, the full height of the screen, flush with `edge`.
    /// Rounded to whole points so no hairline of wallpaper shows between notch and bezel.
    public static func panelFrame(screenFrame: CGRect, edge: NotchEdge, depth: CGFloat) -> CGRect {
        let width = depth.rounded(.up)
        let x = edge == .right ? screenFrame.maxX - width : screenFrame.minX
        return CGRect(x: x.rounded(), y: screenFrame.minY, width: width, height: screenFrame.height)
    }

    /// Where a shape sits in the panel. `alongOffset` moves its centre down from the panel's
    /// middle; the result is clamped so the whole shape stays on screen.
    public static func shapeRect(panelSize: CGSize, edge: NotchEdge, size: NotchShapeSize, alongOffset: CGFloat) -> CGRect {
        let center = clamp(
            panelSize.height / 2 + alongOffset,
            min: size.length / 2,
            max: panelSize.height - size.length / 2
        )
        let x = edge == .right ? panelSize.width - size.depth : 0
        return CGRect(x: x, y: center - size.length / 2, width: size.depth, height: size.length)
    }

    /// Clamps an offset so a shape of `length` stays fully on a panel `panelLength` tall.
    public static func clampedOffset(_ offset: CGFloat, panelLength: CGFloat, length: CGFloat) -> CGFloat {
        let limit = max(0, (panelLength - length) / 2)
        return clamp(offset, min: -limit, max: limit)
    }

    /// The region that receives hover and drops: the shape grown inward by `margin`.
    public static func hotRect(shapeRect: CGRect, edge: NotchEdge, margin: CGFloat) -> CGRect {
        var rect = shapeRect
        rect.size.width += margin
        if edge == .right { rect.origin.x -= margin }
        return rect
    }

    /// Index of the screen to use: the one whose ID matches `displayID`, else the primary (index 0).
    public static func preferredScreenIndex(displayIDs: [String?], preferred displayID: String?) -> Int? {
        guard !displayIDs.isEmpty else { return nil }
        if let displayID, let index = displayIDs.firstIndex(of: displayID) {
            return index
        }
        return 0
    }

    /// A clamp that never traps, even when the range is inverted (a shape longer than the screen).
    static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }
}
```

See the current source: `Packages/Modules/Sources/NotchKit/Geometry/NSScreen+Display.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Modules --filter "NotchGeometryTests|NotchMetricsTests"`
Expected: `✔ Test run with 17 tests in 2 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/Modules
git commit -m "Add notch geometry and metrics

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The notch shape

The black body with concave shoulders that curve back into the bezel, left/right edges only.

**Files:**
- Create: `Packages/Modules/Sources/NotchKit/Views/SideNotchShape.swift`
- Test: `Packages/Modules/Tests/NotchKitTests/SideNotchShapeTests.swift`

**Interfaces:**
- Consumes: `NotchEdge` (Task 3).
- Produces: `struct SideNotchShape: Shape { edge: NotchEdge; flare: CGFloat; cornerRadius: CGFloat }` (internal), animatable over `flare` and `cornerRadius`.

- [ ] **Step 1: Write the failing shape tests**

`Packages/Modules/Tests/NotchKitTests/SideNotchShapeTests.swift`:

```swift
import CoreGraphics
import SwiftUI
import Testing
@testable import NotchKit

struct SideNotchShapeTests {
    let rect = CGRect(x: 10, y: 20, width: 64, height: 200)

    @Test func rightEdgeShapeFillsItsRect() {
        let path = SideNotchShape(edge: .right, flare: 12, cornerRadius: 18).path(in: rect)
        #expect(path.boundingRect.integral == rect)
    }

    @Test func rightEdgeFlareTouchesBezelNotFarSide() {
        let path = SideNotchShape(edge: .right, flare: 12, cornerRadius: 18).path(in: rect)
        // At the foot of the top flare, right against the bezel: filled.
        #expect(path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 11)))
        // Same height on the far side: empty, because only the bezel side flares.
        #expect(!path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 11)))
        // The corner of the flare's square is carved away — that is what makes it concave.
        #expect(!path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 1)))
        // Middle of the body: inside.
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    @Test func leftEdgeIsMirrored() {
        let path = SideNotchShape(edge: .left, flare: 12, cornerRadius: 18).path(in: rect)
        #expect(path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 11)))
        #expect(!path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 11)))
    }

    @Test func thinFoldedPillKeepsRoundedCorners() {
        let pill = CGRect(x: 0, y: 0, width: 6, height: 96)
        let path = SideNotchShape(edge: .right, flare: 12, cornerRadius: 3).path(in: pill)
        #expect(path.boundingRect.integral == pill)
        #expect(path.contains(CGPoint(x: 3, y: 48)))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/Modules --filter SideNotchShapeTests`
Expected: FAIL — the tests don't compile (`cannot find 'SideNotchShape' in scope`).

- [ ] **Step 3: Implement the shape**

See the current source: `Packages/Modules/Sources/NotchKit/Views/SideNotchShape.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Modules --filter SideNotchShapeTests`
Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/Modules
git commit -m "Add side notch shape

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Window plumbing — panel and container view

The `NSPanel` and the content view that defines the live region. This is where "no polling" is enforced: hover comes from one `NSTrackingArea`, drags from `NSDraggingDestination`.

**Files:**
- Create: `Packages/Modules/Sources/NotchKit/Window/NotchPanel.swift`, `Packages/Modules/Sources/NotchKit/Window/NotchContainerView.swift`
- Test: `Packages/Modules/Tests/NotchKitTests/NotchContainerViewTests.swift`

**Interfaces:**
- Consumes: nothing beyond AppKit/SwiftUI.
- Produces (all internal to NotchKit):
  - `final class NotchPanel: NSPanel` — `init()`, `allowsKey: Bool`, callbacks `contextMenuProvider: (() -> NSMenu?)?`, `onEscape`, `onResignKey`, `onDragStart`, `onDrag: ((CGFloat, CGFloat) -> Void)?` (deltaX, deltaY; deltaY > 0 is down), `onDragEnd`; `func relinquishKey()`.
  - `final class NotchContainerView: NSView` — flipped; `hotRect` (read-only) set via `func setHotRect(_ rect: CGRect)`; `func syncPointer()`; callbacks `onPointerEntered`, `onPointerExited`, `onFileDragEntered`, `onFileDragExited`, `onFileDrop: (([URL]) -> Bool)?`; `static func fileURLs(_ pasteboard: NSPasteboard) -> [URL]`.
  - `final class NotchHostingView<Content: View>: NSHostingView<Content>` — accepts first mouse.

- [ ] **Step 1: Write the failing container tests**

`Packages/Modules/Tests/NotchKitTests/NotchContainerViewTests.swift`:

```swift
import AppKit
import Testing
@testable import NotchKit

@MainActor
struct NotchContainerViewTests {
    private func container() -> NotchContainerView {
        let view = NotchContainerView(frame: CGRect(x: 0, y: 0, width: 326, height: 982))
        view.setHotRect(CGRect(x: 256, y: 391, width: 70, height: 200))
        return view
    }

    @Test func clicksOutsideHotRectFallThrough() {
        #expect(container().hitTest(CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func clicksInsideHotRectAreTaken() {
        let view = container()
        #expect(view.hitTest(CGPoint(x: 300, y: 450)) === view)
    }

    @Test func isFlippedToMatchSwiftUI() {
        #expect(container().isFlipped)
    }

    @Test func readsOnlyFileURLsFromPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotchContainerViewTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL, URL(string: "https://example.com")! as NSURL])
        #expect(NotchContainerView.fileURLs(pasteboard) == [URL(fileURLWithPath: "/tmp/a.txt")])
        pasteboard.releaseGlobally()
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/Modules --filter NotchContainerViewTests`
Expected: FAIL — the tests don't compile (`cannot find 'NotchContainerView' in scope`).

- [ ] **Step 3: Implement the container view**

`Packages/Modules/Sources/NotchKit/Window/NotchContainerView.swift`:

```swift
import AppKit
import SwiftUI

/// The panel's content view. It owns everything that decides *where* the notch is live:
/// hit testing, hover tracking and file drops, all limited to `hotRect`. Outside it the panel is
/// a hole that clicks fall through.
///
/// Hover comes from a single `NSTrackingArea` — no cursor polling, no global event monitors — so
/// the notch costs nothing while the pointer is elsewhere.
final class NotchContainerView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    var onFileDrop: (([URL]) -> Bool)?

    private(set) var hotRect: CGRect = .zero
    private(set) var isPointerInside = false
    private var isDragInside = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Moves the live region. Re-checks where the pointer is on the next run-loop turn, because a
    /// tracking area replaced while the pointer is already outside it never reports an exit.
    func setHotRect(_ rect: CGRect) {
        guard rect != hotRect else { return }
        hotRect = rect
        updateTrackingAreas()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.syncPointer() }
        }
    }

    /// Brings `isPointerInside` in line with where the pointer really is.
    func syncPointer() {
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setPointerInside(hotRect.contains(location))
    }

    // MARK: Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard hotRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: hotRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        if inside { onPointerEntered?() } else { onPointerExited?() }
    }

    // MARK: File drops

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let inside = hotRect.contains(location) && Self.hasFileURLs(sender.draggingPasteboard)
        if inside != isDragInside {
            isDragInside = inside
            if inside { onFileDragEntered?() } else { onFileDragExited?() }
        }
        return inside ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard isDragInside else { return }
        isDragInside = false
        onFileDragExited?()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDragInside = false
        let urls = Self.fileURLs(sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        return onFileDrop?(urls) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        // A drag suppresses tracking events, so re-learn where the pointer is.
        syncPointer()
    }

    private static let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    private static func hasFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: fileURLOptions)
    }

    static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL]) ?? []
    }
}

/// Hosts the SwiftUI notch. Accepts the first click so tiles respond even though the panel is
/// never the key window while they are showing.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Modules --filter NotchContainerViewTests`
Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Implement the panel**

The panel is driven by the window server (event routing, key status), so it is verified by hand in Task 11 rather than unit-tested.

See the current source: `Packages/Modules/Sources/NotchKit/Window/NotchPanel.swift`.

- [ ] **Step 6: Build and run all tests**

Run: `make test`
Expected: `✔ Test run with 51 tests in 6 suites passed`, no warnings.

- [ ] **Step 7: Commit**

```bash
git add Packages/Modules
git commit -m "Add notch panel and container view (hover, hit testing, drops)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Design system and notch views

The SwiftUI surface: the view model the controller writes to, the root view that places everything from precomputed rects, the tiles column and the expanded-widget frame.

**Files:**
- Create: `Packages/Modules/Sources/DesignSystem/NotchMotion.swift`, `Packages/Modules/Sources/DesignSystem/Palette.swift`, `Packages/Modules/Sources/NotchKit/Views/NotchViewModel.swift`, `NotchRootView.swift`, `TilesView.swift`, `ExpandedWidgetView.swift`
- Modify: `Packages/Modules/Package.swift`

**Interfaces:**
- Consumes: `NotchState`, `WidgetID`, `NotchWidget`, `WidgetContext` (Task 2); `NotchEdge`, `NotchMetrics` (Task 3); `SideNotchShape` (Task 4).
- Produces:
  - `DesignSystem`: `enum NotchMotion { static let unfold, contents, crossfade: Animation }`, `enum Palette { notch, primaryText, secondaryText, tileFill, tileHover, dropHighlight: Color }`.
  - `NotchKit` (internal): `@Observable final class NotchViewModel` with `state`, `edge`, `metrics`, `shapeRect`, `hotRect`, `cornerRadius`, `isGhosted`, `widgets`, intent closures `onSelect(WidgetID)`, `onBack()`, `onOpenSettings()`, `onEditingChanged(Bool)`, `onClose()`, `func widget(_ id: WidgetID) -> (any NotchWidget)?`, `var widgetContext: WidgetContext`; `struct NotchRootView(model:)`.

- [ ] **Step 1: Update the manifest**

`Packages/Modules/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppInfo", targets: ["AppInfo"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NotchWidgetAPI", targets: ["NotchWidgetAPI"]),
        .library(name: "NotchKit", targets: ["NotchKit"]),
    ],
    targets: [
        .target(name: "AppInfo"),
        .target(name: "DesignSystem"),
        .target(name: "NotchWidgetAPI"),
        .target(name: "NotchKit", dependencies: ["NotchWidgetAPI", "DesignSystem"]),
        .testTarget(name: "AppInfoTests", dependencies: ["AppInfo"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit", "NotchWidgetAPI"]),
    ]
)
```

- [ ] **Step 2: Add the design system**

See the current source: `Packages/Modules/Sources/DesignSystem/NotchMotion.swift`.

`Packages/Modules/Sources/DesignSystem/Palette.swift`:

```swift
import SwiftUI

/// Colours for the notch surface. The notch is always dark, whatever the system appearance.
public enum Palette {
    public static let notch = Color.black
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.6)
    public static let tileFill = Color.white.opacity(0.08)
    public static let tileHover = Color.white.opacity(0.16)
    public static let dropHighlight = Color.accentColor
}
```

- [ ] **Step 3: Add the view model**

`Packages/Modules/Sources/NotchKit/Views/NotchViewModel.swift`:

```swift
import CoreGraphics
import Observation
import NotchWidgetAPI

/// Everything the SwiftUI notch draws, pushed in by `NotchController`, plus the user's intents
/// flowing back out. Views never compute geometry themselves.
@MainActor
@Observable
final class NotchViewModel {
    var state: NotchState = .folded
    var edge: NotchEdge = .right
    var metrics = NotchMetrics.standard
    /// The visible shape, in panel coordinates (top-left origin).
    var shapeRect: CGRect = .zero
    /// The region that takes hover and drops; drawn near-transparent so it receives events.
    var hotRect: CGRect = .zero
    var cornerRadius: CGFloat = NotchMetrics.standard.foldedCornerRadius
    /// True while a full-screen app is in front: the folded pill is not drawn, but stays live.
    var isGhosted = false
    @ObservationIgnored var widgets: [any NotchWidget] = []

    @ObservationIgnored var onSelect: (WidgetID) -> Void = { _ in }
    @ObservationIgnored var onBack: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    func widget(_ id: WidgetID) -> (any NotchWidget)? {
        widgets.first { $0.id == id }
    }

    var widgetContext: WidgetContext {
        WidgetContext(
            setEditing: { [weak self] in self?.onEditingChanged($0) },
            close: { [weak self] in self?.onClose() }
        )
    }
}
```

- [ ] **Step 4: Add the views**

`Packages/Modules/Sources/NotchKit/Views/NotchRootView.swift`:

```swift
import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// The whole notch surface. Fills the panel; everything is placed from rects the controller
/// computed, so this view has no layout logic of its own.
struct NotchRootView: View {
    let model: NotchViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Fully transparent pixels let events fall through the window, so the live region is
            // painted at 1% opacity — invisible, but it keeps hover and drops working even when
            // the pill itself is hidden for a full-screen app.
            Rectangle()
                .fill(Color.black.opacity(0.01))
                .frame(width: model.hotRect.width, height: model.hotRect.height)
                .offset(x: model.hotRect.minX, y: model.hotRect.minY)

            SideNotchShape(edge: model.edge, flare: model.metrics.flare, cornerRadius: model.cornerRadius)
                .fill(Palette.notch)
                .opacity(model.isGhosted && model.state == .folded ? 0 : 1)
                .frame(width: model.shapeRect.width, height: model.shapeRect.height)
                .offset(x: model.shapeRect.minX, y: model.shapeRect.minY)

            let content = model.metrics.contentRect(in: model.shapeRect)
            stateContent
                .frame(width: content.width, height: content.height)
                .offset(x: content.minX, y: content.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .folded:
            EmptyView()
        case .tiles:
            TilesView(model: model)
                .transition(.opacity.animation(NotchMotion.contents))
        case .expanded(let id, let dropTarget):
            if let widget = model.widget(id) {
                ExpandedWidgetView(model: model, widget: widget, dropTarget: dropTarget)
                    .transition(.opacity.animation(NotchMotion.contents))
            }
        }
    }
}
```

`Packages/Modules/Sources/NotchKit/Views/TilesView.swift`:

```swift
import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// The unfolded column: one tile per enabled widget, then the Settings gear.
struct TilesView: View {
    let model: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.widgets, id: \.id) { widget in
                TileButton(title: widget.title, systemImage: widget.systemImage) {
                    model.onSelect(widget.id)
                }
                .frame(height: model.metrics.tileExtent)
            }
            Button(action: model.onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .frame(height: model.metrics.gearExtent)
        }
    }
}

private struct TileButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .frame(width: 40, height: 40)
                .background(isHovering ? Palette.tileHover : Palette.tileFill, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }
}
```

`Packages/Modules/Sources/NotchKit/Views/ExpandedWidgetView.swift`:

```swift
import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// An open mini app: a header with a back chevron, then the widget's own view.
struct ExpandedWidgetView: View {
    let model: NotchViewModel
    let widget: any NotchWidget
    let dropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: model.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                Image(systemName: widget.systemImage)
                Text(widget.title)
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(Palette.primaryText)

            widget.makeExpandedView(context: model.widgetContext)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Palette.dropHighlight, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .overlay(Text("Drop here").font(.headline).foregroundStyle(Palette.primaryText))
                    .background(Palette.notch.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
```

- [ ] **Step 5: Build and run all tests**

The views hold no logic of their own (every rect comes from `NotchMetrics`/`NotchGeometry`, tested in Task 3); they are checked visually in Task 11.

Run: `swift build --package-path Packages/Modules 2>&1 | grep -E "error|warning: "; make test`
Expected: the grep prints nothing; `✔ Test run with 51 tests in 6 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Modules
git commit -m "Add design system and notch SwiftUI views

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Full-screen detection

Hides the folded pill while a full-screen app is in front of its display, driven only by workspace notifications.

**Files:**
- Create: `Packages/Modules/Sources/NotchKit/FullScreen/FullScreenDetector.swift`, `Packages/Modules/Sources/NotchKit/FullScreen/FullScreenObserver.swift`
- Test: `Packages/Modules/Tests/NotchKitTests/FullScreenDetectorTests.swift`

**Interfaces:**
- Consumes: nothing beyond AppKit.
- Produces (internal): `struct WindowSummary { pid: pid_t; layer: Int; bounds: CGRect }`; `enum FullScreenDetector { static func isFullScreen(screenBounds:frontmostPID:windows:safeAreaTopInset:) -> Bool; @MainActor static func isFullScreenAppFrontmost(on: NSScreen) -> Bool }`; `@MainActor final class FullScreenObserver { init(screen: @escaping () -> NSScreen?); onChange: ((Bool) -> Void)?; isFullScreen; start(); stop() }`.

- [ ] **Step 1: Write the failing detector tests**

`Packages/Modules/Tests/NotchKitTests/FullScreenDetectorTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import NotchKit

struct FullScreenDetectorTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func window(pid: pid_t = 42, layer: Int = 0, _ bounds: CGRect) -> WindowSummary {
        WindowSummary(pid: pid, layer: layer, bounds: bounds)
    }

    @Test func windowCoveringDisplayIsFullScreen() {
        #expect(FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(screen)]))
    }

    @Test func windowBelowCameraNotchIsFullScreen() {
        let below = CGRect(x: 0, y: 32, width: 1512, height: 950)
        #expect(FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(below)], safeAreaTopInset: 32))
    }

    @Test func ordinaryWindowIsNotFullScreen() {
        let small = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(small)]))
    }

    @Test func otherAppsWindowDoesNotCount() {
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(pid: 7, screen)]))
    }

    @Test func overlayLayerDoesNotCount() {
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(layer: 25, screen)]))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/Modules --filter FullScreenDetectorTests`
Expected: FAIL — the tests don't compile (`cannot find 'WindowSummary' in scope` and similar).

- [ ] **Step 3: Implement the detector**

See the current source: `Packages/Modules/Sources/NotchKit/FullScreen/FullScreenDetector.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Modules --filter FullScreenDetectorTests`
Expected: `✔ Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5: Implement the observer**

`Packages/Modules/Sources/NotchKit/FullScreen/FullScreenObserver.swift`:

```swift
import AppKit

/// Tells the controller when a full-screen app comes to the front of the notch's display.
///
/// Event-driven only: it re-checks when macOS announces a space change or an app activation (and
/// once more shortly after, since space transitions animate). There is no polling timer.
@MainActor
final class FullScreenObserver {
    var onChange: ((Bool) -> Void)?
    private(set) var isFullScreen = false

    private let screen: () -> NSScreen?
    private var tokens: [NSObjectProtocol] = []
    private var followUp: Task<Void, Never>?

    init(screen: @escaping () -> NSScreen?) {
        self.screen = screen
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.spaceOrAppChanged() }
            }
            tokens.append(token)
        }
        evaluate()
    }

    func stop() {
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens.removeAll()
        followUp?.cancel()
    }

    private func spaceOrAppChanged() {
        evaluate()
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard let screen = screen() else { return }
        let value = FullScreenDetector.isFullScreenAppFrontmost(on: screen)
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange?(value)
    }
}
```

- [ ] **Step 6: Build and run all tests**

Run: `swift build --package-path Packages/Modules 2>&1 | grep -E "error|warning: "; make test`
Expected: the grep prints nothing; `✔ Test run with 56 tests in 7 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Packages/Modules
git commit -m "Add event-driven full-screen detection

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Notch controller

Ties the window, the views and the state machine together, and turns effects into one-shot timers and key-window changes.

**Files:**
- Create: `Packages/Modules/Sources/NotchKit/NotchConfiguration.swift`, `Packages/Modules/Sources/NotchKit/NotchController.swift`
- Modify: `Packages/Modules/Package.swift`

**Interfaces:**
- Consumes: everything in NotchKit from Tasks 2–7; `AppIdentity.logger` (Task 1); `NotchMotion` (Task 6).
- Produces (public):
  - `struct NotchConfiguration: Equatable, Sendable { edge: NotchEdge; displayID: String?; alongOffset: CGFloat; isVisible: Bool; hoverDelay: Duration (150 ms); graceDelay: Duration (250 ms) }` with a memberwise `init` whose parameters all have defaults.
  - `@MainActor final class NotchController { init(widgets: [any NotchWidget], configuration: NotchConfiguration); onOpenSettings: () -> Void; onAlongOffsetCommitted: (CGFloat) -> Void; contextMenuProvider: () -> NSMenu?; configuration; state; func start(); func apply(_: NotchConfiguration); func send(_: NotchEvent) }`.

- [ ] **Step 1: Update the manifest**

In `Packages/Modules/Package.swift`, change the NotchKit target line to:

```swift
        .target(name: "NotchKit", dependencies: ["NotchWidgetAPI", "DesignSystem", "AppInfo"]),
```

- [ ] **Step 2: Add the configuration**

`Packages/Modules/Sources/NotchKit/NotchConfiguration.swift`:

```swift
import CoreGraphics

/// The user-controlled settings the notch needs. The app maps its preferences onto this, so
/// NotchKit never reads UserDefaults itself.
public struct NotchConfiguration: Equatable, Sendable {
    public var edge: NotchEdge
    /// `NSScreen.displayIdentifier` of the chosen display; nil means the primary display.
    public var displayID: String?
    /// How far the pill's centre sits below the middle of the edge, in points.
    public var alongOffset: CGFloat
    public var isVisible: Bool
    public var hoverDelay: Duration
    public var graceDelay: Duration

    public init(
        edge: NotchEdge = .right,
        displayID: String? = nil,
        alongOffset: CGFloat = 0,
        isVisible: Bool = true,
        hoverDelay: Duration = .milliseconds(150),
        graceDelay: Duration = .milliseconds(250)
    ) {
        self.edge = edge
        self.displayID = displayID
        self.alongOffset = alongOffset
        self.isVisible = isVisible
        self.hoverDelay = hoverDelay
        self.graceDelay = graceDelay
    }
}
```

- [ ] **Step 3: Add the controller**

`Packages/Modules/Sources/NotchKit/NotchController.swift`:

```swift
import AppKit
import SwiftUI
import AppInfo
import DesignSystem
import NotchWidgetAPI

/// Owns the notch window and runs its state machine.
///
/// Performance contract: while folded, nothing here runs. Hover, drags, screen and space changes
/// all arrive as events; the only timers are the one-shot hover and grace delays, and they exist
/// only for the moment a transition is pending.
@MainActor
public final class NotchController {
    public var onOpenSettings: () -> Void = {}
    /// Called when an ⌥-drag ends, with the new offset to persist.
    public var onAlongOffsetCommitted: (CGFloat) -> Void = { _ in }
    public var contextMenuProvider: () -> NSMenu? = { nil }

    public private(set) var configuration: NotchConfiguration
    public var state: NotchState { machine.state }

    private let widgets: [any NotchWidget]
    private let metrics = NotchMetrics.standard
    private var machine: NotchStateMachine
    private let model = NotchViewModel()
    private let panel = NotchPanel()
    private let container = NotchContainerView(frame: .zero)
    private lazy var fullScreen = FullScreenObserver { [weak self] in self?.currentScreen() }
    private var hoverTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private let log = AppIdentity.current.logger("notch")

    public init(widgets: [any NotchWidget], configuration: NotchConfiguration) {
        self.widgets = widgets
        self.configuration = configuration
        machine = NotchStateMachine(dropWidget: widgets.first { $0.acceptsFileDrops }?.id)

        let hosting = NotchHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        model.widgets = widgets
        model.metrics = metrics
        wire()
    }

    /// Puts the notch on screen and starts listening for screen and space changes.
    public func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        fullScreen.start()
        layout()
        applyVisibility()
    }

    public func apply(_ newValue: NotchConfiguration) {
        let old = configuration
        configuration = newValue
        if old.edge != newValue.edge || old.displayID != newValue.displayID || old.alongOffset != newValue.alongOffset {
            layout()
        }
        if old.isVisible != newValue.isVisible {
            applyVisibility()
        }
    }

    /// Feeds one event through the state machine and carries out what it asks for.
    public func send(_ event: NotchEvent) {
        let before = machine.state
        let effects = machine.handle(event)
        effects.forEach(perform)
        if machine.state != before {
            log.debug("\(String(describing: before), privacy: .public) → \(String(describing: self.machine.state), privacy: .public)")
            updateShape(animated: true)
        }
    }

    // MARK: Wiring

    private func wire() {
        container.onPointerEntered = { [weak self] in self?.send(.pointerEntered) }
        container.onPointerExited = { [weak self] in self?.send(.pointerExited) }
        container.onFileDragEntered = { [weak self] in self?.send(.fileDragEntered) }
        container.onFileDragExited = { [weak self] in self?.send(.fileDragExited) }
        container.onFileDrop = { [weak self] urls in self?.drop(urls) ?? false }

        panel.onEscape = { [weak self] in self?.send(.escape) }
        panel.onResignKey = { [weak self] in self?.send(.resignedKey) }
        panel.contextMenuProvider = { [weak self] in self?.contextMenuProvider() }
        panel.onDragStart = { [weak self] in self?.cancelTimers() }
        panel.onDrag = { [weak self] _, dy in self?.slide(by: dy) }
        panel.onDragEnd = { [weak self] in
            guard let self else { return }
            onAlongOffsetCommitted(configuration.alongOffset)
        }

        model.onSelect = { [weak self] in self?.send(.tileSelected($0)) }
        model.onBack = { [weak self] in self?.send(.back) }
        model.onClose = { [weak self] in self?.send(.escape) }
        model.onEditingChanged = { [weak self] in self?.send($0 ? .editingBegan : .editingEnded) }
        model.onOpenSettings = { [weak self] in
            self?.send(.escape)
            self?.onOpenSettings()
        }

        fullScreen.onChange = { [weak self] isFullScreen in self?.model.isGhosted = isFullScreen }
    }

    // MARK: Effects

    private func perform(_ effect: NotchEffect) {
        switch effect {
        case .startHoverTimer:
            hoverTask?.cancel()
            hoverTask = after(configuration.hoverDelay) { [weak self] in self?.send(.hoverDelayElapsed) }
        case .startGraceTimer:
            graceTask?.cancel()
            graceTask = after(configuration.graceDelay) { [weak self] in self?.send(.graceElapsed) }
        case .cancelTimers:
            cancelTimers()
        case .makeKey:
            panel.allowsKey = true
            panel.makeKey()
        case .resignKey:
            panel.relinquishKey()
        }
    }

    private func after(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func cancelTimers() {
        hoverTask?.cancel()
        graceTask?.cancel()
        hoverTask = nil
        graceTask = nil
    }

    // MARK: Layout

    private func currentScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let index = NotchGeometry.preferredScreenIndex(
            displayIDs: screens.map(\.displayIdentifier),
            preferred: configuration.displayID
        )
        return index.map { screens[$0] }
    }

    /// Re-places the panel: on start, on screen changes and when the edge or display changes.
    private func layout() {
        guard let screen = currentScreen() else { return }
        let depth = metrics.panelDepth(expandedSizes: widgets.map(\.expandedSize))
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame, edge: configuration.edge, depth: depth)
        panel.setFrame(frame, display: false)
        model.edge = configuration.edge
        updateShape(animated: false)
    }

    private var expandedSizes: [WidgetID: CGSize] {
        Dictionary(uniqueKeysWithValues: widgets.map { ($0.id, $0.expandedSize) })
    }

    /// Moves the shape to match the current state. The panel frame never changes here — only the
    /// shape inside it animates — so the window is never resized per animation frame.
    private func updateShape(animated: Bool) {
        let state = machine.state
        let size = metrics.shapeSize(for: state, tileCount: widgets.count, expandedSizes: expandedSizes)
        let rect = NotchGeometry.shapeRect(
            panelSize: panel.frame.size, edge: configuration.edge, size: size, alongOffset: configuration.alongOffset
        )
        let hot = NotchGeometry.hotRect(shapeRect: rect, edge: configuration.edge, margin: metrics.hoverMargin)
        let radius = metrics.cornerRadius(for: state)

        model.hotRect = hot
        let apply = { [model] in
            model.state = state
            model.shapeRect = rect
            model.cornerRadius = radius
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(NotchMotion.unfold, apply)
        } else {
            apply()
        }
        container.setHotRect(hot)
    }

    private func applyVisibility() {
        if configuration.isVisible {
            panel.orderFrontRegardless()
        } else {
            send(.escape)
            panel.orderOut(nil)
        }
    }

    // MARK: Drops and dragging

    private func drop(_ urls: [URL]) -> Bool {
        defer { send(.fileDropped) }
        guard let id = machine.state.expandedWidget,
              let widget = model.widget(id),
              widget.acceptsFileDrops
        else { return false }
        return widget.handleFileDrop(urls)
    }

    private func slide(by dy: CGFloat) {
        let folded = metrics.shapeSize(for: .folded, tileCount: widgets.count, expandedSizes: expandedSizes)
        configuration.alongOffset = NotchGeometry.clampedOffset(
            configuration.alongOffset + dy, panelLength: panel.frame.height, length: folded.length
        )
        updateShape(animated: false)
    }
}
```

Key points for the reviewer:
- The panel frame changes only in `layout()` (start, screen change, edge/display change). State changes only move the SwiftUI shape (spec §4.3).
- `hotRect` changes at once and is not animated, so the live region is always the target state's, while the visible shape springs into place.
- The only `Task`s are the hover and grace delays, and both are cancelled on the next relevant event.

- [ ] **Step 4: Build and run all tests**

Run: `swift build --package-path Packages/Modules 2>&1 | grep -E "error|warning: "; make test`
Expected: the grep prints nothing; `✔ Test run with 56 tests in 7 suites passed`.

- [ ] **Step 5: Confirm there is no polling**

Run: `grep -rnE "Timer\(|scheduledTimer|addGlobalMonitor|addLocalMonitor|repeatForever|CVDisplayLink|TimelineView" Packages/Modules/Sources || echo "no polling"`
Expected: `no polling`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Modules
git commit -m "Add notch controller

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Settings feature (preferences + General tab)

Persisted preferences mapped onto `NotchConfiguration`, launch at login, and the General settings tab.

**Files:**
- Create: `Packages/Modules/Sources/SettingsFeature/Preferences.swift`, `LaunchAtLogin.swift`, `GeneralSettingsView.swift`, `SettingsView.swift`
- Modify: `Packages/Modules/Package.swift`
- Test: `Packages/Modules/Tests/SettingsFeatureTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: `NotchEdge`, `NotchConfiguration`, `NSScreen.displayIdentifier` (NotchKit).
- Produces (public): `@MainActor @Observable final class Preferences { init(defaults: UserDefaults = .standard); edge; displayID: String?; alongOffset: Double; isNotchVisible: Bool; notchConfiguration: NotchConfiguration; func resetPosition() }` (UserDefaults keys `notch.edge`, `notch.displayID`, `notch.alongOffset`, `notch.isVisible`); `@MainActor enum LaunchAtLogin { static var isEnabled: Bool; static func setEnabled(_:) throws }`; `struct SettingsView: View { init(preferences:) }`.

- [ ] **Step 1: Write the final manifest**

`Packages/Modules/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppInfo", targets: ["AppInfo"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NotchWidgetAPI", targets: ["NotchWidgetAPI"]),
        .library(name: "NotchKit", targets: ["NotchKit"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    targets: [
        .target(name: "AppInfo"),
        .target(name: "DesignSystem"),
        .target(name: "NotchWidgetAPI"),
        .target(name: "NotchKit", dependencies: ["NotchWidgetAPI", "DesignSystem", "AppInfo"]),
        .target(name: "SettingsFeature", dependencies: ["NotchKit", "AppInfo"]),
        .testTarget(name: "AppInfoTests", dependencies: ["AppInfo"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit", "NotchWidgetAPI"]),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
    ]
)
```

- [ ] **Step 2: Write the failing preferences tests**

`Packages/Modules/Tests/SettingsFeatureTests/PreferencesTests.swift`:

```swift
import Foundation
import Testing
import NotchKit
@testable import SettingsFeature

@MainActor
struct PreferencesTests {
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "PreferencesTests-\(UUID().uuidString)")!
    }

    @Test func defaultsWhenNothingSaved() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.edge == .right)
        #expect(preferences.displayID == nil)
        #expect(preferences.alongOffset == 0)
        #expect(preferences.isNotchVisible)
    }

    @Test func changesPersistAcrossInstances() {
        let first = Preferences(defaults: defaults)
        first.edge = .left
        first.displayID = "DISPLAY-UUID"
        first.alongOffset = -120
        first.isNotchVisible = false

        let second = Preferences(defaults: defaults)
        #expect(second.edge == .left)
        #expect(second.displayID == "DISPLAY-UUID")
        #expect(second.alongOffset == -120)
        #expect(!second.isNotchVisible)
    }

    @Test func clearingDisplayFallsBackToPrimary() {
        let first = Preferences(defaults: defaults)
        first.displayID = "DISPLAY-UUID"
        first.displayID = nil
        #expect(Preferences(defaults: defaults).displayID == nil)
    }

    @Test func unknownSavedEdgeFallsBackToRight() {
        defaults.set("top", forKey: Preferences.Key.edge)
        #expect(Preferences(defaults: defaults).edge == .right)
    }

    @Test func mapsToNotchConfiguration() {
        let preferences = Preferences(defaults: defaults)
        preferences.edge = .left
        preferences.alongOffset = 40
        let configuration = preferences.notchConfiguration
        #expect(configuration.edge == .left)
        #expect(configuration.alongOffset == 40)
        #expect(configuration.isVisible)
    }

    @Test func resetPositionZeroesOffset() {
        let preferences = Preferences(defaults: defaults)
        preferences.alongOffset = 200
        preferences.resetPosition()
        #expect(preferences.alongOffset == 0)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path Packages/Modules --filter PreferencesTests`
Expected: FAIL — `target 'SettingsFeature' referenced in product 'SettingsFeature' is empty`.

- [ ] **Step 4: Implement Preferences**

`Packages/Modules/Sources/SettingsFeature/Preferences.swift`:

```swift
import Foundation
import Observation
import NotchKit

/// The user's settings, persisted in UserDefaults. Observable, so Settings views bind straight
/// to it and the app can react to changes.
@MainActor
@Observable
public final class Preferences {
    public var edge: NotchEdge {
        didSet { defaults.set(edge.rawValue, forKey: Key.edge) }
    }
    /// nil means "the primary display".
    public var displayID: String? {
        didSet { defaults.set(displayID, forKey: Key.displayID) }
    }
    public var alongOffset: Double {
        didSet { defaults.set(alongOffset, forKey: Key.alongOffset) }
    }
    public var isNotchVisible: Bool {
        didSet { defaults.set(isNotchVisible, forKey: Key.isNotchVisible) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = defaults.string(forKey: Key.edge).flatMap(NotchEdge.init(rawValue:)) ?? .right
        displayID = defaults.string(forKey: Key.displayID)
        alongOffset = defaults.double(forKey: Key.alongOffset)
        isNotchVisible = defaults.object(forKey: Key.isNotchVisible) as? Bool ?? true
    }

    /// What the notch needs from these settings.
    public var notchConfiguration: NotchConfiguration {
        NotchConfiguration(edge: edge, displayID: displayID, alongOffset: alongOffset, isVisible: isNotchVisible)
    }

    public func resetPosition() {
        alongOffset = 0
    }

    enum Key {
        static let edge = "notch.edge"
        static let displayID = "notch.displayID"
        static let alongOffset = "notch.alongOffset"
        static let isNotchVisible = "notch.isVisible"
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Modules --filter PreferencesTests`
Expected: `✔ Test run with 6 tests in 1 suite passed`.

- [ ] **Step 6: Add launch at login and the settings views**

`Packages/Modules/Sources/SettingsFeature/LaunchAtLogin.swift`:

```swift
import ServiceManagement

/// Registers the app as a login item with the modern SMAppService API (no helper app needed).
@MainActor
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

`Packages/Modules/Sources/SettingsFeature/GeneralSettingsView.swift`:

```swift
import AppKit
import SwiftUI
import NotchKit

/// Settings › General: where the notch lives and whether the app starts at login.
struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Position") {
                Picker("Screen edge", selection: $preferences.edge) {
                    ForEach(NotchEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Display", selection: $preferences.displayID) {
                    Text("Primary display").tag(String?.none)
                    ForEach(DisplayOption.connected()) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                }

                LabeledContent("Position along edge") {
                    Button("Reset") { preferences.resetPosition() }
                }
                Text("Tip: hold ⌥ and drag the notch to slide it along the edge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Only flips the toggle once registration actually succeeded.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = newValue
                    launchError = nil
                } catch {
                    launchError = "Couldn't change the login item: \(error.localizedDescription)"
                }
            }
        )
    }
}

extension NotchEdge {
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// A connected display the notch can be placed on.
struct DisplayOption: Identifiable, Hashable {
    let id: String
    let name: String

    @MainActor
    static func connected() -> [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            screen.displayIdentifier.map { DisplayOption(id: $0, name: screen.localizedName) }
        }
    }
}
```

`Packages/Modules/Sources/SettingsFeature/SettingsView.swift`:

```swift
import SwiftUI

/// The Settings window's content. M1 has the General tab; later milestones add the rest.
public struct SettingsView: View {
    private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 7: Build and run all tests**

Run: `swift build --package-path Packages/Modules 2>&1 | grep -E "error|warning: "; make test`
Expected: the grep prints nothing; `✔ Test run with 62 tests in 8 suites passed`.

- [ ] **Step 8: Commit**

```bash
git add Packages/Modules
git commit -m "Add settings feature: preferences, launch at login, General tab

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: App shell — composition, menu bar, Settings window, placeholder widgets

Wires every module into a running app.

**Files:**
- Create: `App/Sources/AppEnvironment.swift`, `App/Sources/MainMenu.swift`, `App/Sources/StatusItemController.swift`, `App/Sources/SettingsWindowController.swift`, `App/Sources/PlaceholderWidget.swift`
- Modify: `App/Sources/AppDelegate.swift` (replace), `project.yml` (add products)

**Interfaces:**
- Consumes: `AppIdentity` (Task 1); `NotchWidget`, `WidgetID`, `WidgetContext` (Task 2); `NotchController`, `NotchConfiguration` (Task 8); `Preferences`, `SettingsView` (Task 9).
- Produces: the runnable app. `AppEnvironment { init(); start(); showSettings() }`; `StatusItemController { init(isNotchVisible:onOpenSettings:onToggleNotch:); install(); makeMenu() -> NSMenu }`; `SettingsWindowController { init(preferences:); show() }`; `PlaceholderWidget: NotchWidget` with `static func all() -> [PlaceholderWidget]`; `MainMenu.make(target:settingsAction:) -> NSMenu`.

- [ ] **Step 1: Add the remaining products to `project.yml`**

Replace the `dependencies:` block of the `App` target with:

```yaml
    dependencies:
      - package: Modules
        product: AppInfo
      - package: Modules
        product: NotchWidgetAPI
      - package: Modules
        product: NotchKit
      - package: Modules
        product: SettingsFeature
```

- [ ] **Step 2: Add the placeholder widgets**

`App/Sources/PlaceholderWidget.swift`:

```swift
import SwiftUI
import Observation
import NotchWidgetAPI

/// Stand-ins for the three mini apps until their milestones land (Shelf M2, Notes M3,
/// Reminders M4). Each exercises one piece of notch plumbing: the shelf takes file drops, and every
/// placeholder has a text field that engages the editing lock.
@MainActor
@Observable
final class PlaceholderWidget: NotchWidget {
    let id: WidgetID
    let title: String
    let systemImage: String
    let acceptsFileDrops: Bool
    let milestone: String
    let expandedSize = CGSize(width: 320, height: 420)
    private(set) var droppedNames: [String] = []

    init(id: WidgetID, title: String, systemImage: String, milestone: String, acceptsFileDrops: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.milestone = milestone
        self.acceptsFileDrops = acceptsFileDrops
    }

    static func all() -> [PlaceholderWidget] {
        [
            PlaceholderWidget(id: .shelf, title: "Shelf", systemImage: "tray", milestone: "M2", acceptsFileDrops: true),
            PlaceholderWidget(id: .notes, title: "Notes", systemImage: "note.text", milestone: "M3"),
            PlaceholderWidget(id: .reminders, title: "Reminders", systemImage: "bell", milestone: "M4"),
        ]
    }

    func makeExpandedView(context: WidgetContext) -> AnyView {
        AnyView(PlaceholderView(widget: self, context: context))
    }

    func handleFileDrop(_ urls: [URL]) -> Bool {
        droppedNames = urls.map(\.lastPathComponent)
        return true
    }
}

private struct PlaceholderView: View {
    let widget: PlaceholderWidget
    let context: WidgetContext
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(widget.title) arrives in \(widget.milestone).")
                .foregroundStyle(.secondary)
            if !widget.droppedNames.isEmpty {
                Text("Dropped:").font(.subheadline.bold())
                ForEach(widget.droppedNames, id: \.self) { name in
                    Text(name).lineLimit(1).truncationMode(.middle)
                }
            }
            TextField("Type here to test the editing lock", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
            Spacer()
        }
        .onChange(of: isFocused) { _, focused in context.setEditing(focused) }
    }
}
```

- [ ] **Step 3: Add the menus and windows**

`App/Sources/MainMenu.swift`:

```swift
import AppKit
import AppInfo

/// The app menu and Edit menu. Never visible (the app has no Dock icon or menu bar of its own),
/// but it is what makes ⌘, ⌘Q and the standard editing shortcuts (⌘C, ⌘V, ⌘Z…) work in the
/// notch's text fields and the Settings window.
@MainActor
enum MainMenu {
    static func make(target: AnyObject, settingsAction: Selector) -> NSMenu {
        let name = AppIdentity.current.name
        let main = NSMenu()

        let appMenu = NSMenu(title: name)
        let settings = appMenu.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: name)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
```

`App/Sources/StatusItemController.swift`:

```swift
import AppKit
import AppInfo

/// The menu bar icon. The same menu is shown when the notch is right-clicked.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let isNotchVisible: () -> Bool
    private let onOpenSettings: () -> Void
    private let onToggleNotch: () -> Void

    init(isNotchVisible: @escaping () -> Bool, onOpenSettings: @escaping () -> Void, onToggleNotch: @escaping () -> Void) {
        self.isNotchVisible = isNotchVisible
        self.onOpenSettings = onOpenSettings
        self.onToggleNotch = onToggleNotch
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: AppIdentity.current.name)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// A fresh menu reflecting the current state.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let toggle = menu.addItem(
            withTitle: isNotchVisible() ? "Hide Notch" : "Show Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(AppIdentity.current.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func toggleNotch() { onToggleNotch() }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
```

`App/Sources/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI
import AppInfo
import SettingsFeature

/// The ordinary Settings window. The app has no Dock icon, so it activates itself to bring the
/// window in front of whatever app the user was in.
@MainActor
final class SettingsWindowController {
    private let preferences: Preferences
    private var window: NSWindow?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(preferences: preferences)))
        window.title = "\(AppIdentity.current.name) Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
```

- [ ] **Step 4: Add the composition root and the final app delegate**

`App/Sources/AppEnvironment.swift`:

```swift
import AppKit
import Observation
import NotchKit
import SettingsFeature

/// The composition root: the one place that builds every object and wires modules together.
/// Modules never reach for each other directly.
@MainActor
final class AppEnvironment {
    private let preferences: Preferences
    private let notch: NotchController
    private let settings: SettingsWindowController
    private let statusItem: StatusItemController

    init() {
        let preferences = Preferences()
        let settings = SettingsWindowController(preferences: preferences)
        let notch = NotchController(widgets: PlaceholderWidget.all(), configuration: preferences.notchConfiguration)
        let statusItem = StatusItemController(
            isNotchVisible: { preferences.isNotchVisible },
            onOpenSettings: { settings.show() },
            onToggleNotch: { preferences.isNotchVisible.toggle() }
        )

        notch.onOpenSettings = { settings.show() }
        notch.onAlongOffsetCommitted = { preferences.alongOffset = $0 }
        notch.contextMenuProvider = { statusItem.makeMenu() }

        self.preferences = preferences
        self.settings = settings
        self.notch = notch
        self.statusItem = statusItem
    }

    func start() {
        statusItem.install()
        notch.start()
        observePreferences()
    }

    func showSettings() {
        settings.show()
    }

    /// Pushes every preference change into the notch. `withObservationTracking` fires once, so it
    /// re-registers itself after each change.
    private func observePreferences() {
        withObservationTracking {
            _ = preferences.notchConfiguration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                notch.apply(preferences.notchConfiguration)
                observePreferences()
            }
        }
    }
}
```

`App/Sources/AppDelegate.swift` (replace the whole file):

```swift
import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    /// Explicit entry point: without a main nib, `NSApplicationMain` would never create the delegate.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        NSApp.mainMenu = MainMenu.make(target: self, settingsAction: #selector(showSettings(_:)))
        environment.start()
        self.environment = environment
    }

    @objc private func showSettings(_ sender: Any?) {
        environment?.showSettings()
    }
}
```

- [ ] **Step 5: Build**

Run: `make build 2>&1 | grep -E "error|warning:"; echo "exit: ${PIPESTATUS[0]}"`
Expected: no error or warning lines; `exit: 0`.

- [ ] **Step 6: Smoke test**

Run: `make run`
Expected:
- A thin black pill sits vertically centred on the **right** edge of the primary display.
- A menu bar icon (`sidebar.right` symbol) appears; its menu shows *Settings…*, *Hide Notch*, *Quit SideNotch*.
- Hovering the pill for a moment unfolds three tiles and a gear.

Then run: `pkill -x SideNotch`.

- [ ] **Step 7: Commit**

```bash
git add App project.yml
git commit -m "Wire app shell: composition root, menu bar, Settings window, placeholders

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Behaviour and performance verification

Checks what unit tests can't (window-server behaviour), measures the spec §7 budget, and records the results.

**Files:**
- Create: `docs/superpowers/verification/2026-09-19-m1-verification.md`
- Modify: only as needed to fix failures found here (each fix goes through superpowers:systematic-debugging and gets its own commit).

**Interfaces:**
- Consumes: the running app from Task 10.
- Produces: a verification record for M1.

- [ ] **Step 1: Run the behaviour checklist**

Launch with `make run`. Work through every row and note pass/fail:

| # | Action | Expected |
|---|---|---|
| 1 | Pointer onto the pill, hold still | Tiles unfold after about 150 ms with a spring |
| 2 | Brush past the pill quickly (under 150 ms) | Nothing opens |
| 3 | From tiles, move the pointer away | Folds after about 250 ms |
| 4 | Leave and come straight back within 250 ms | Stays open |
| 5 | Click the Notes tile (while another app is frontmost) | The Notes placeholder opens; the other app stays frontmost (its menu bar is unchanged) |
| 6 | Click the text field, type, move the pointer away | Stays open (editing lock) |
| 7 | Press Esc | Folds; typing goes back to the previous app |
| 8 | Open Notes, click inside another app's window | Folds |
| 9 | Open Notes, click the back chevron, move away | Returns to tiles, then folds |
| 10 | Drag a Finder file onto the pill | Opens the Shelf placeholder directly with a "Drop here" outline |
| 11 | Drop it | Outline goes; the file name is listed; the Finder file is untouched |
| 12 | Drag a file over the pill and away without dropping | Folds after about 250 ms |
| 13 | Click the wallpaper or a window **near** the pill (not on it) | The click reaches what's underneath |
| 14 | ⌥-drag the pill down, quit (`pkill -x SideNotch`), `make run` | The pill comes back at the new position |
| 15 | Right-click the pill | The same menu as the menu bar icon |
| 16 | Settings › General › Screen edge: Left | The pill moves to the left edge and unfolds to the right |
| 17 | Settings › Display (with a second display) | The pill moves; unplug that display → it returns to the primary |
| 18 | Settings › Reset position | The pill re-centres |
| 19 | Settings › Launch at login on, then off | Toggles without an error (System Settings › General › Login Items lists the app while on) |
| 20 | Menu bar › Hide Notch, then Show Notch | Pill disappears, then returns |
| 21 | Put Safari/Keynote into full screen | The pill is not drawn; hovering the edge where it was still unfolds it |
| 22 | Leave full screen | The pill is drawn again |
| 23 | System Settings › Accessibility › Display › Reduce motion on, then hover | Unfolds instantly, no spring |
| 24 | Gear on the tiles | Notch folds; the Settings window opens in front |
| 25 | Drag a Finder file onto the desktop or a Finder window just beside the pill (within ~3 cm of the edge, not on it) | The drop lands there, not refused |
| 26 | After dropping a file on the pill, click the Shelf text field, type, then press Esc | Typing works; Esc folds the notch |
| 27 | Right-click the pill → Hide Notch; then menu bar → Show Notch; hover the pill once | A single hover unfolds it |

If row 1 or 21 fails (no hover over the pill or over the hidden pill), raise the hit-surface opacity in `NotchRootView` from `0.01` to `0.03`, which is still invisible, and retest. Some window-server builds round very low alpha down to zero, and a zero-alpha pixel passes clicks through.

- [ ] **Step 2: Measure idle cost (release build)**

```bash
pkill -x SideNotch; make CONFIG=Release build
open build/DerivedData/Build/Products/Release/SideNotch.app
sleep 10   # let launch settle; do not touch the pill from here on
PID=$(pgrep -x SideNotch)
top -l 13 -s 5 -pid "$PID" -stats pid,command,cpu,idlew,mem | tail -12
footprint "$PID" | head -3
```

Expected (spec §7): every `%CPU` sample is ≤ 0.5 (should read 0.0), `IDLEW` stays near 0, and `Footprint` is under 80 MB.

- [ ] **Step 3: Measure recovery after use**

Hover to unfold, open a placeholder, fold it again, then re-run the `top` line from Step 2.
Expected: `%CPU` is back to about 0.0 within a second of folding.

- [ ] **Step 4: Record the results**

`docs/superpowers/verification/2026-09-19-m1-verification.md`:

```markdown
# M1 Verification — Notch Shell

**Date:** <YYYY-MM-DD> · **Build:** <git rev-parse --short HEAD> · **Mac:** <model, macOS version>

## Behaviour checklist

| # | Result | Notes |
|---|---|---|
| 1 | ✅/❌ | |
… one row for each of the 24 checks …

## Idle cost (Release)

| Metric | Budget | Measured |
|---|---|---|
| CPU, idle (12 × 5 s samples) | ≤ 0.5 % | |
| Idle wake-ups | ≈ 0 | |
| Physical footprint | < 80 MB | |
| CPU 1 s after folding | ≈ 0 % | |

## Issues found and fixes

- <none, or one line per issue with the commit that fixed it>
```

Fill in every field with the observed values.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/verification
git commit -m "Record M1 verification results

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Finish the branch**

Use superpowers:finishing-a-development-branch to merge `m1-notch-shell` into `main`.
