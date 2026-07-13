import Foundation

enum UsageHistoryGranularity: String, CaseIterable, Identifiable {
    case day = "รายวัน"
    case month = "รายเดือน"
    case year = "รายปี"

    var id: String { rawValue }

    var calendarComponents: Set<Calendar.Component> {
        switch self {
        case .day: return [.year, .month, .day]
        case .month: return [.year, .month]
        case .year: return [.year]
        }
    }

    var dateFormat: String {
        switch self {
        case .day: return "d MMM yyyy"
        case .month: return "MMMM yyyy"
        case .year: return "yyyy"
        }
    }

    /// Stable English identifier for the local web server's `?granularity=`
    /// query parameter — `rawValue` is Thai display text, not URL-friendly.
    var queryKey: String {
        switch self {
        case .day: return "day"
        case .month: return "month"
        case .year: return "year"
        }
    }

    init?(queryKey: String) {
        switch queryKey {
        case "day": self = .day
        case "month": self = .month
        case "year": self = .year
        default: return nil
        }
    }
}

struct UsageHistoryBucket: Identifiable {
    let periodStart: Date
    let label: String
    let totalCostUSD: Double
    let totalTokens: Int

    var id: Date { periodStart }
}

enum ClaudeCodeUsageAggregator {
    /// Buckets records by day/month/year, newest period first.
    static func aggregate(
        _ records: [ClaudeCodeUsageRecord],
        by granularity: UsageHistoryGranularity,
        calendar: Calendar = .current
    ) -> [UsageHistoryBucket] {
        var totals: [Date: (cost: Double, tokens: Int)] = [:]

        for record in records {
            let components = calendar.dateComponents(granularity.calendarComponents, from: record.date)
            let periodStart = calendar.date(from: components) ?? record.date
            var entry = totals[periodStart] ?? (0, 0)
            entry.cost += record.estimatedCostUSD
            entry.tokens += record.totalTokens
            totals[periodStart] = entry
        }

        let formatter = DateFormatter()
        formatter.dateFormat = granularity.dateFormat

        return totals
            .sorted { $0.key > $1.key }
            .map { periodStart, totals in
                UsageHistoryBucket(
                    periodStart: periodStart,
                    label: formatter.string(from: periodStart),
                    totalCostUSD: totals.cost,
                    totalTokens: totals.tokens
                )
            }
    }
}
