import Foundation
import Testing
@testable import RemindersFeature

/// `ReminderTime.resolve` is pure date maths, tested against an injected "now" and `Calendar` —
/// never the wall clock — so every boundary (already past 20:00, a DST shift) is deterministic.
struct ReminderTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func inMinutesAddsMinutesToNow() {
        let calendar = self.calendar
        let now = date(2026, 6, 1, 10, 0, calendar: calendar)
        let resolved = ReminderTime.inMinutes(5).resolve(now: now, calendar: calendar)
        #expect(resolved == date(2026, 6, 1, 10, 5, calendar: calendar))
    }

    @Test func fifteenThirtyAndSixtyMinuteChipsAddExactly() {
        let calendar = self.calendar
        let now = date(2026, 6, 1, 10, 0, calendar: calendar)
        #expect(ReminderTime.inMinutes(15).resolve(now: now, calendar: calendar) == date(2026, 6, 1, 10, 15, calendar: calendar))
        #expect(ReminderTime.inMinutes(30).resolve(now: now, calendar: calendar) == date(2026, 6, 1, 10, 30, calendar: calendar))
        #expect(ReminderTime.inMinutes(60).resolve(now: now, calendar: calendar) == date(2026, 6, 1, 11, 0, calendar: calendar))
    }

    @Test func tonightBefore8pmResolvesToToday8pm() {
        let calendar = self.calendar
        let now = date(2026, 6, 1, 14, 0, calendar: calendar)
        #expect(ReminderTime.tonight().resolve(now: now, calendar: calendar) == date(2026, 6, 1, 20, 0, calendar: calendar))
    }

    @Test func tonightExactlyAt8pmResolvesToTomorrow8pm() {
        // At exactly 20:00, "tonight" has technically arrived, not "coming up" — treated the
        // same as already past, per the store's `<=` overdue rule for a reminder due right now.
        let calendar = self.calendar
        let now = date(2026, 6, 1, 20, 0, calendar: calendar)
        #expect(ReminderTime.tonight().resolve(now: now, calendar: calendar) == date(2026, 6, 2, 20, 0, calendar: calendar))
    }

    @Test func tonightAfter8pmResolvesToTomorrow8pm() {
        let calendar = self.calendar
        let now = date(2026, 6, 1, 21, 30, calendar: calendar)
        #expect(ReminderTime.tonight().resolve(now: now, calendar: calendar) == date(2026, 6, 2, 20, 0, calendar: calendar))
    }

    @Test func tomorrowIsAlwaysNextDayAt9amRegardlessOfCurrentTime() {
        let calendar = self.calendar
        let earlyMorning = date(2026, 6, 1, 6, 0, calendar: calendar)
        #expect(ReminderTime.tomorrow().resolve(now: earlyMorning, calendar: calendar) == date(2026, 6, 2, 9, 0, calendar: calendar))

        let lateNight = date(2026, 6, 1, 23, 45, calendar: calendar)
        #expect(ReminderTime.tomorrow().resolve(now: lateNight, calendar: calendar) == date(2026, 6, 2, 9, 0, calendar: calendar))
    }

    @Test func tonightAndTomorrowHoursAreConfigurable() {
        let calendar = self.calendar
        let now = date(2026, 6, 1, 6, 0, calendar: calendar)
        #expect(ReminderTime.tonight(hour: 22).resolve(now: now, calendar: calendar) == date(2026, 6, 1, 22, 0, calendar: calendar))
        #expect(ReminderTime.tomorrow(hour: 8).resolve(now: now, calendar: calendar) == date(2026, 6, 2, 8, 0, calendar: calendar))
    }

    @Test func presetChipsSubstituteTheConfiguredTonightAndTomorrowHours() {
        let chips = ReminderTime.presetChips(tonightHour: 22, tomorrowHour: 7)
        #expect(chips.first(where: { $0.id == "tonight" })?.time == .tonight(hour: 22))
        #expect(chips.first(where: { $0.id == "tomorrow" })?.time == .tomorrow(hour: 7))
    }

    @Test func presetChipsDefaultToSpecHours() {
        let chips = ReminderTime.presetChips()
        #expect(chips.first(where: { $0.id == "tonight" })?.time == .tonight())
        #expect(chips.first(where: { $0.id == "tomorrow" })?.time == .tomorrow())
    }

    @Test func customPassesTheDateThroughUnchanged() {
        let calendar = self.calendar
        let now = date(2026, 6, 1, 6, 0, calendar: calendar)
        let target = date(2026, 12, 25, 9, 0, calendar: calendar)
        #expect(ReminderTime.custom(target).resolve(now: now, calendar: calendar) == target)
    }

    /// 2026-03-08 is when US Eastern clocks spring forward (2:00am → 3:00am). "Tomorrow" from the
    /// day before must still land on 09:00 wall-clock time the next day, not 09:00 minus/plus the
    /// hour that raw `TimeInterval` addition would produce.
    @Test func tomorrowLandsOnTheIntendedWallClockHourAcrossADSTSpringForward() {
        let calendar = self.calendar
        let now = date(2026, 3, 7, 10, 0, calendar: calendar)
        let resolved = ReminderTime.tomorrow().resolve(now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: resolved)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 8)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
    }

    /// Same DST boundary for "tonight": the day of the spring-forward itself, requested in the
    /// morning, must still resolve to 20:00 wall-clock that same day.
    @Test func tonightLandsOnTheIntendedWallClockHourOnTheDSTDayItself() {
        let calendar = self.calendar
        let now = date(2026, 3, 8, 8, 0, calendar: calendar)
        let resolved = ReminderTime.tonight().resolve(now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: resolved)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 8)
        #expect(components.hour == 20)
        #expect(components.minute == 0)
    }
}
