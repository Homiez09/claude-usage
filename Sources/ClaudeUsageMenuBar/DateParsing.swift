import Foundation

enum FlexibleISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return withFractional.date(from: string) ?? withoutFractional.date(from: string)
    }
}

enum ResetDescriber {
    static func describe(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "Resetting now"
        }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 24 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE h:mm a"
            return "Resets \(formatter.string(from: date))"
        }
        if hours > 0 {
            return "Resets in \(hours) hr \(minutes) min"
        }
        return "Resets in \(minutes) min"
    }

    /// Compact "2h17m" form for the menu bar icon, where there's no room for
    /// the full "Resets in ..." sentence.
    static func shortCountdown(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "0m"
        }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 24 {
            let days = hours / 24
            return "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }
}
