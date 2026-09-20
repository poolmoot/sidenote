import Foundation

/// Pure date maths for the reminder chips (spec §3.5). Resolved against an injected "now" and
/// `Calendar` rather than the wall clock, so every boundary — "already past 20:00", a DST shift —
/// can be pinned down in a test. `bySettingHour(_:minute:second:of:)` is used throughout instead
/// of raw `TimeInterval` arithmetic: it operates on wall-clock components in the calendar's own
/// time zone, so "20:00" still means 20:00 on a day the clocks moved.
public enum ReminderTime: Equatable, Sendable {
    /// `minutes` from now. Named `inMinutes` rather than `.in(minutes:)` (as sketched in the plan)
    /// because `in` is a Swift keyword and an enum case can't be spelled that way without
    /// backticks at every call site.
    case inMinutes(Int)
    /// 20:00 today, or tomorrow if it's already past that hour today. The hour is a parameter
    /// (default 20) so it stays configurable per spec §3.5's "Chip times are configurable".
    case tonight(hour: Int = 20)
    /// 09:00 tomorrow, regardless of the current time. Configurable the same way as `.tonight`.
    case tomorrow(hour: Int = 9)
    /// A caller-supplied exact date, passed straight through.
    case custom(Date)

    /// The date this chip resolves to, given the current moment and calendar.
    public func resolve(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .inMinutes(let minutes):
            return calendar.date(byAdding: .minute, value: minutes, to: now)
                ?? now.addingTimeInterval(TimeInterval(minutes) * 60)

        case .tonight(let hour):
            let todayAtHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
            if todayAtHour > now { return todayAtHour }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        case .tomorrow(let hour):
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        case .custom(let date):
            return date
        }
    }
}

/// One button in the chip row: a label to show and the time it resolves to. Spec §4.2 lists this
/// as `TimeChip`.
public struct TimeChip: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let time: ReminderTime

    public init(id: String, label: String, time: ReminderTime) {
        self.id = id
        self.label = label
        self.time = time
    }
}

public extension ReminderTime {
    /// The fixed chip row from spec §3.5, in display order. "Custom…" isn't included here — it
    /// opens a date picker rather than resolving to a fixed `ReminderTime` on tap.
    static let presetChips: [TimeChip] = [
        TimeChip(id: "5min", label: "5 min", time: .inMinutes(5)),
        TimeChip(id: "30min", label: "30 min", time: .inMinutes(30)),
        TimeChip(id: "tonight", label: "Tonight", time: .tonight()),
        TimeChip(id: "tomorrow", label: "Tomorrow", time: .tomorrow()),
    ]
}
