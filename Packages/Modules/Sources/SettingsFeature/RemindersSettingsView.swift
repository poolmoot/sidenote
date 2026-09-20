import Foundation
import SwiftUI

/// Settings › Reminders: snooze length and the "Tonight"/"Tomorrow" chip hours (spec §3.6).
struct RemindersSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Snooze") {
                Picker("Snooze length", selection: $preferences.snoozeMinutes) {
                    ForEach(Preferences.snoozeOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Chip times") {
                hourPicker("Tonight", selection: $preferences.tonightHour)
                hourPicker("Tomorrow", selection: $preferences.tomorrowHour)
            }
        }
        .formStyle(.grouped)
    }

    private func hourPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<24) { hour in
                Text(Self.hourLabel(hour)).tag(hour)
            }
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return "\(hour):00" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
