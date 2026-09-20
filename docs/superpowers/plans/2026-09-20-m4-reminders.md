# M4 — Reminders Plan

**Goal:** Replace the last placeholder with the reminders widget from spec §3.5: write what to be reminded of, pick when, and get a macOS notification even if the app isn't running.

**Spec:** `docs/superpowers/specs/2026-09-19-sidenotch-design.md` — §3.5 (behaviour), §4.2 (modules), §4.5 (persistence), §4.6 (`Reminder`), §4.7 (scheduling), §6 (errors).

## Constraints
- Swift 6, macOS 26, no polling, Swift Testing, app name only in `Config/Branding.xcconfig`.
- `RemindersFeature` imports only `NotchWidgetAPI`, `Persistence`, `DesignSystem` and `AppInfo`. Never `NotchKit`.
- Add the module to `Package.swift` with its first file, and the product to `project.yml`.
- Commits end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Test-first for all logic; the view and real notifications are checked by hand.

## Files
```
Packages/Modules/Sources/RemindersFeature/
  Reminder.swift            Reminder (spec §4.6) + RemindersDocument { version: 1, reminders }
  ReminderTime.swift        pure date maths for the chips: .in(minutes:), .tonight, .tomorrow, .custom(Date)
                            resolved against an injected "now" and Calendar
  ReminderScheduler.swift   protocol (requestAuthorization, schedule, cancel, pendingIDs) + a
                            UNUserNotificationCenter implementation + notification category/actions
  RemindersStore.swift      @MainActor @Observable: reminders, add(text:fireDate:), markDone(id),
                            snooze(id), remove(id), overdue, reconcile(), nextDueDate, flush()
  RemindersWidget.swift     NotchWidget: .reminders, "Reminders", "bell", 320×420, badge = .dot when overdue
  RemindersView.swift       text field + chip row + "Custom…" date picker; list of upcoming with
                            relative times; overdue section on top with Done / Snooze
Packages/Modules/Tests/RemindersFeatureTests/
  ReminderTimeTests.swift, RemindersStoreTests.swift (with a FakeScheduler + fixed clock)
App/Sources/AppEnvironment.swift       build RemindersStore + widget; set the notification delegate;
                                       reconcile on launch; flush on terminate
App/Sources/PlaceholderWidget.swift    delete (no placeholders left) — remove the file and its uses
App/Sources/NotificationDelegate.swift UNUserNotificationCenterDelegate: Done / Snooze actions and
                                       opening the widget when the body is clicked
project.yml                            + product RemindersFeature
Config/App.entitlements                unchanged (notifications need no entitlement)
```

## Behaviour
1. **Creating:** type the text, then tap a chip — **5 min · 15 min · 30 min · 1 h · Tonight · Tomorrow** — or **Custom…** for a date and time. Chips resolve against the current time: "Tonight" is 20:00 today, or tomorrow's 20:00 when it is already past; "Tomorrow" is 09:00 the next day. All of this lives in `ReminderTime` and is tested with a fixed clock, including a DST boundary.
2. **Permission:** the first time a reminder is created, ask for notification permission. If it is denied, the reminder is still saved and shown in the list, and the widget shows one line explaining that notifications are off, with a button that opens System Settings (spec §6).
3. **Scheduling:** one notification request per reminder, id = the reminder's id, category `REMINDER` with actions **Done** and **Snooze**. Snooze moves `fireDate` to now + the snooze length (default 10 minutes) and reschedules. Done sets the status and cancels the request.
4. **Reconcile on launch:** schedule pending future reminders that have no request, cancel requests with no reminder, and leave already-passed pending reminders as overdue.
5. **Overdue:** reminders whose time has passed and that are still pending show at the top with Done / Snooze, and the folded pill shows a dot (`WidgetBadge.dot`) while any exist. The badge must update when the set changes.
6. **List:** upcoming reminders sorted by `fireDate`, each with a relative time ("in 12 min"). Recompute those labels **only while the widget is open**, on a single `TimelineView(.periodic(from:by:60))` or equivalent that exists only in that view — never a timer owned by the store, and nothing while folded.
7. **Due while running:** one non-repeating `Task.sleep` scheduled for the soonest pending reminder, re-armed whenever the set changes, so the dot appears without polling. Cancel it when nothing is pending.
8. **Errors:** scheduling failures are logged through `AppIdentity.logger("reminders")`; the reminder is still saved.

## Tests (first)
- `ReminderTime` with a fixed clock and calendar: each chip resolves to the expected date; "Tonight" before/after 20:00; "Tomorrow" at 09:00; custom passes through; a DST-shift day still lands on the intended wall-clock time.
- `RemindersStore` with `FakeScheduler` + fixed clock: add schedules exactly one request; done cancels it; snooze moves the date and reschedules; remove cancels; overdue is computed from the clock; `reconcile()` schedules missing, cancels orphans, and keeps overdue pending; the set survives a reload through `JSONFileStore`; `nextDueDate` is the soonest pending one; a denied permission still stores the reminder.

## Done when
- `make test` passes (all targets), `make build` clean, no-polling grep prints `no polling` (the widget's minute ticker and the single next-due sleep are the only time-based code, both scoped as described).
- Hand check (owner): create "test" + 5 min → a notification arrives; Snooze pushes it 10 minutes; Done removes it; a reminder created then app quit still fires; the pill shows a dot while something is overdue.
