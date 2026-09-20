import Foundation

/// The text under a reminder: how long until it fires.
///
/// Pure and tested, because "in 6 min" for a five-minute reminder is exactly the kind of small lie
/// that makes a timer feel broken. Under ten minutes it counts seconds, so a reminder set for five
/// minutes reads 5:00 and walks down; above that, whole units, always rounded *down* so the label
/// never claims more time than is left.
enum CountdownLabel {
    /// Seconds below which the label counts down in `M:SS`.
    static let secondsThreshold: TimeInterval = 600

    static func text(forSecondsRemaining remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "overdue" }
        let seconds = Int(remaining.rounded())
        if remaining < secondsThreshold {
            return String(format: "in %d:%02d", seconds / 60, seconds % 60)
        }
        let minutes = seconds / 60
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0 ? "in \(days) d" : "in \(days) d \(restHours) h"
    }
}
