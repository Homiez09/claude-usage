import Foundation

/// The payload served at `/api/history` — per-period equivalent-API-cost
/// estimate, mirroring the Mac app's History tab. Never carries conversation
/// content, only aggregated numbers already computed from local transcripts.
struct UsageHistorySnapshot: Codable, Equatable {
    struct Period: Codable, Equatable {
        let label: String
        let costUSD: Double
        let tokens: Int
    }

    let granularity: String
    let periods: [Period]
}

enum UsageHistorySnapshotBuilder {
    static func build(buckets: [UsageHistoryBucket], granularity: UsageHistoryGranularity) -> UsageHistorySnapshot {
        UsageHistorySnapshot(
            granularity: granularity.queryKey,
            periods: buckets.map {
                UsageHistorySnapshot.Period(label: $0.label, costUSD: $0.totalCostUSD, tokens: $0.totalTokens)
            }
        )
    }

    static func encodeJSON(_ snapshot: UsageHistorySnapshot) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
