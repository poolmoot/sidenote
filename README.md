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
