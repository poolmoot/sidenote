import SwiftUI
import AppKit
import NotchWidgetAPI
import DesignSystem
import AppInfo

/// The Reminders widget's root view: a text field and chip row to create one, an overdue section
/// on top, then upcoming reminders below. Spec §3.5.
struct RemindersView: View {
    let store: RemindersStore
    let context: WidgetContext

    @State private var draftText = ""
    @State private var isCustomPickerShowing = false
    @State private var customDate = Date()
    @FocusState private var isTextFieldFocused: Bool
    /// Fixed once, when the view appears, rather than read as `.now` inside `body`: a literal
    /// `.now` there would be a new `Date` on every redraw, which is harmless for `TimelineView`
    /// itself (it only uses `from:` as the schedule's starting point) but is exactly the kind of
    /// "expensive/non-deterministic work inside `body`" this codebase avoids elsewhere.
    @State private var timelineAnchor = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            composer
            if store.notificationsDenied {
                permissionBanner
            }
            Divider()
            list
        }
        .onChange(of: isTextFieldFocused) { _, _ in updateEditingLock() }
        .onChange(of: isCustomPickerShowing) { _, _ in updateEditingLock() }
        // ⌘Z needs a responder somewhere in the tree even while nothing is focused; a
        // zero-opacity button carrying the shortcut is simpler than an NSEvent monitor and
        // doesn't intercept anything else. Disabled (rather than always live) so `canUndoLastDone`
        // is the actual gate on whether ⌘Z does anything.
        .background(
            Button("Undo", action: store.undoLastDone)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndoLastDone)
                .opacity(0)
                .allowsHitTesting(false)
        )
        .onAppear {
            // Picks up a permission change made outside the app (e.g. the user granted or
            // revoked notifications in System Settings since this widget was last open), not
            // just a denial found at launch.
            Task { await store.reconcile() }
        }
        // Spec §3.5: undo doesn't reach back past the last time the widget was open.
        .onDisappear {
            context.setEditing(false)
            store.clearUndo()
            store.flush()
        }
    }

    /// The editing lock is held while either the text field has focus or the custom date picker
    /// is up — a `DatePicker` doesn't report through `@FocusState` the way a text field does, so
    /// "is the custom picker showing" stands in for "is the user mid-pick", same lock either way.
    private func updateEditingLock() {
        context.setEditing(isTextFieldFocused || isCustomPickerShowing)
    }

    private var header: some View {
        Text(countLabel)
            .font(.caption)
            .foregroundStyle(Palette.secondaryText)
    }

    private var countLabel: String {
        let count = store.overdue.count + store.upcoming.count
        return count == 0 ? "No reminders" : "\(count) reminder\(count == 1 ? "" : "s")"
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Remind me to…", text: $draftText)
                .textFieldStyle(.plain)
                .padding(6)
                .background(Palette.tileFill, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Palette.primaryText)
                .focused($isTextFieldFocused)
                // Owner ruling: Return must not silently create a reminder on some implicit
                // default chip — the user picks a time explicitly, always.
                .onSubmit {}

            chipRow

            if isCustomPickerShowing {
                customPicker
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(ReminderTime.presetChips) { chip in
                chipButton(chip.label) { addReminder(time: chip.time) }
            }
            chipButton("Custom…") { isCustomPickerShowing.toggle() }
        }
    }

    private func chipButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.tileFill, in: Capsule())
            .foregroundStyle(Palette.primaryText)
            .contentShape(Capsule())
    }

    private var customPicker: some View {
        HStack {
            DatePicker("", selection: $customDate)
                .labelsHidden()
                .datePickerStyle(.compact)
            Button("Set") { addReminder(time: .custom(customDate)) }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .font(.caption.bold())
                .foregroundStyle(Palette.primaryText)
        }
    }

    private func addReminder(time: ReminderTime) {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let fireDate = time.resolve(now: Date(), calendar: .current)
        store.add(text: text, fireDate: fireDate)
        draftText = ""
        isCustomPickerShowing = false
    }

    // MARK: Permission banner (spec §6)

    private var permissionBanner: some View {
        HStack(spacing: 6) {
            Text("Notifications are off for \(AppIdentity.current.name).")
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Button("Open Settings", action: openNotificationSettings)
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .font(.caption2.bold())
                .foregroundStyle(Palette.primaryText)
        }
        .padding(6)
        .background(Palette.tileFill, in: RoundedRectangle(cornerRadius: 6))
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: List

    private var list: some View {
        Group {
            if store.overdue.isEmpty && store.upcoming.isEmpty {
                emptyState
            } else {
                // Relative labels ("in 12 min") are only recomputed while this view exists on
                // screen — folding the widget tears the whole tree down, and with it this
                // `TimelineView`, so nothing ticks while the notch is folded (spec §3.5).
                ScrollView {
                    TimelineView(.periodic(from: timelineAnchor, by: 60)) { timeline in
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if !store.overdue.isEmpty {
                                sectionLabel("Overdue", color: .red)
                                ForEach(store.overdue) { reminder in
                                    ReminderRow(reminder: reminder, now: timeline.date, isOverdue: true, store: store)
                                }
                            }
                            if !store.upcoming.isEmpty {
                                if !store.overdue.isEmpty {
                                    sectionLabel("Upcoming", color: Palette.secondaryText)
                                }
                                ForEach(store.upcoming) { reminder in
                                    ReminderRow(reminder: reminder, now: timeline.date, isOverdue: false, store: store)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No reminders yet")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// One row: the reminder's text, a relative time computed from the `TimelineView`'s tick, and
/// Done / Snooze. `now` is passed in rather than read from the clock here, so every row in a
/// given tick shows a consistent time and nothing re-reads the clock per row, per redraw.
private struct ReminderRow: View {
    let reminder: Reminder
    let now: Date
    let isOverdue: Bool
    let store: RemindersStore

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.text)
                    .font(.callout)
                    .foregroundStyle(isOverdue ? Color.red : Palette.primaryText)
                    .lineLimit(1)
                Text(relativeLabel)
                    .font(.caption2)
                    .foregroundStyle(isOverdue ? Color.red.opacity(0.85) : Palette.secondaryText)
            }
            Spacer()
            Button("Done") { store.markDone(id: reminder.id) }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .font(.caption.bold())
                .foregroundStyle(Palette.primaryText)
            Button("Snooze") { store.snooze(id: reminder.id) }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(6)
        .contentShape(Rectangle())
    }

    /// "in 12 min" / "in 3 h" / "in 2 d" for something upcoming, "overdue" once its time has
    /// passed. Display-only formatting, hand-checked like the rest of this view rather than
    /// unit-tested.
    private var relativeLabel: String {
        let secondsRemaining = reminder.fireDate.timeIntervalSince(now)
        guard secondsRemaining > 0 else { return "overdue" }
        let minutes = Int((secondsRemaining / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            let remainderMinutes = minutes % 60
            return remainderMinutes == 0 ? "in \(hours) h" : "in \(hours) h \(remainderMinutes) min"
        }
        let days = hours / 24
        return "in \(days) d"
    }
}
