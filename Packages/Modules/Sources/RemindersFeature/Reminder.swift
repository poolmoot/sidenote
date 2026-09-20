import Foundation

/// One reminder: text to be reminded of, when to fire, and whether it's still pending. Spec §4.6.
public struct Reminder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var fireDate: Date
    public var status: Status
    public let createdAt: Date

    public enum Status: String, Codable, Sendable {
        case pending
        case done
    }

    public init(
        id: UUID = UUID(),
        text: String,
        fireDate: Date,
        status: Status = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.fireDate = fireDate
        self.status = status
        self.createdAt = createdAt
    }
}

/// The on-disk shape of `reminders.json`. `version` enables future migrations. Spec §4.5.
public struct RemindersDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var reminders: [Reminder]

    public init(version: Int = 1, reminders: [Reminder] = []) {
        self.version = version
        self.reminders = reminders
    }
}
