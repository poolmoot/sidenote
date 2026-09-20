import Foundation
import Testing
@testable import RemindersFeature

struct CountdownLabelTests {
    @Test func aFiveMinuteReminderReadsFiveMinutesExactly() {
        #expect(CountdownLabel.text(forSecondsRemaining: 300) == "in 5:00")
    }

    @Test func secondsTickDownBelowTenMinutes() {
        #expect(CountdownLabel.text(forSecondsRemaining: 299) == "in 4:59")
        #expect(CountdownLabel.text(forSecondsRemaining: 61) == "in 1:01")
        #expect(CountdownLabel.text(forSecondsRemaining: 9) == "in 0:09")
    }

    @Test func longerWaitsUseWholeUnitsRoundedDown() {
        #expect(CountdownLabel.text(forSecondsRemaining: 600) == "in 10 min")
        #expect(CountdownLabel.text(forSecondsRemaining: 659) == "in 10 min")     // never claims 11
        #expect(CountdownLabel.text(forSecondsRemaining: 3600) == "in 1 h")
        #expect(CountdownLabel.text(forSecondsRemaining: 3600 * 8) == "in 8 h")
        #expect(CountdownLabel.text(forSecondsRemaining: 3600 * 8 + 1800) == "in 8 h 30 min")
        #expect(CountdownLabel.text(forSecondsRemaining: 86_400 * 2) == "in 2 d")
        #expect(CountdownLabel.text(forSecondsRemaining: 86_400 * 2 + 3600 * 3) == "in 2 d 3 h")
    }

    @Test func aPassedReminderIsOverdue() {
        #expect(CountdownLabel.text(forSecondsRemaining: 0) == "overdue")
        #expect(CountdownLabel.text(forSecondsRemaining: -60) == "overdue")
    }
}
