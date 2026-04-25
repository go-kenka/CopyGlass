import Foundation

enum HistoryRetentionPolicy {
    static let foreverDays = 36_500

    static func cutoffDate(retentionDays: Int, now: Date = Date()) -> Date? {
        guard retentionDays > 0, retentionDays < foreverDays else { return nil }
        return now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
    }
}
