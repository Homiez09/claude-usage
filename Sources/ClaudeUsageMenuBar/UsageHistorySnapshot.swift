import Foundation

/// The payload served at `/api/history` — per-period equivalent-API-cost
/// estimate, mirroring the Mac app's History tab. Never carries conversation
/// content, only aggregated numbers already computed from local transcripts.
struct UsageHistorySnapshot: Codable, Equatable {
    struct Period: Codable, Equatable {
        let label: String
        /// ISO8601 ของจุดเริ่มช่วง — ให้หน้าเว็บเทียบได้ว่า period ไหนคือ
        /// วันนี้/เดือนนี้ โดยไม่ต้องแกะ `label` ที่ format ตาม locale ของ Mac
        let periodStart: String
        let costUSD: Double
        let tokens: Int
    }

    let granularity: String
    let periods: [Period]
}

enum UsageHistorySnapshotBuilder {
    private static let iso8601 = ISO8601DateFormatter()

    static func build(buckets: [UsageHistoryBucket], granularity: UsageHistoryGranularity) -> UsageHistorySnapshot {
        UsageHistorySnapshot(
            granularity: granularity.queryKey,
            periods: buckets.map {
                UsageHistorySnapshot.Period(
                    label: $0.label,
                    periodStart: iso8601.string(from: $0.periodStart),
                    costUSD: $0.totalCostUSD,
                    tokens: $0.totalTokens
                )
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
