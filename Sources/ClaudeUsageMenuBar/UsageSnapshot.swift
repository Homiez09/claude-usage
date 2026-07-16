import Foundation

/// The payload served at `/api/usage` by the local web server. Deliberately
/// carries only already-computed percentages/timestamps — never the raw
/// session key — so the iPhone page can't leak the credential even if the
/// local network request were intercepted.
struct UsageSnapshot: Codable, Equatable {
    struct Row: Codable, Equatable {
        let title: String
        let percent: Int
        let resetsAt: String?
    }

    let hasSessionKey: Bool
    let errorMessage: String?
    let lastUpdated: String?
    let rows: [Row]
    /// Display names of Claude Code sessions currently active on this Mac.
    let activeAgentSessions: [String]
    /// เพซการใช้งาน session ปัจจุบัน (%/ชม.) — nil ถ้าข้อมูลยังไม่พอประเมิน
    let sessionRatePerHour: Double?
    /// ISO8601 ของเวลาที่คาดว่า session จะแตะ 100% ถ้าคงเพซนี้ไว้
    let sessionProjectedFullAt: String?

    init(
        hasSessionKey: Bool,
        errorMessage: String?,
        lastUpdated: String?,
        rows: [Row],
        activeAgentSessions: [String],
        sessionRatePerHour: Double? = nil,
        sessionProjectedFullAt: String? = nil
    ) {
        self.hasSessionKey = hasSessionKey
        self.errorMessage = errorMessage
        self.lastUpdated = lastUpdated
        self.rows = rows
        self.activeAgentSessions = activeAgentSessions
        self.sessionRatePerHour = sessionRatePerHour
        self.sessionProjectedFullAt = sessionProjectedFullAt
    }
}

enum UsageSnapshotBuilder {
    private static let iso8601 = ISO8601DateFormatter()

    static func build(
        hasSessionKey: Bool,
        usage: UsageResponse?,
        errorMessage: String?,
        lastUpdated: Date?,
        activeAgentSessions: [String] = [],
        sessionRatePerHour: Double? = nil,
        sessionProjectedFullAt: Date? = nil
    ) -> UsageSnapshot {
        var rows: [UsageSnapshot.Row] = []

        if let usage {
            if let session = usage.fiveHour {
                rows.append(
                    UsageSnapshot.Row(
                        title: "Current session",
                        percent: session.utilization ?? 0,
                        resetsAt: session.resetsAt
                    )
                )
            }

            for entry in usage.limits where entry.group == "weekly" {
                rows.append(
                    UsageSnapshot.Row(
                        title: entry.scope?.model?.displayName ?? "All models",
                        percent: entry.percent,
                        resetsAt: entry.resetsAt
                    )
                )
            }
        }

        return UsageSnapshot(
            hasSessionKey: hasSessionKey,
            errorMessage: errorMessage,
            lastUpdated: lastUpdated.map { iso8601.string(from: $0) },
            rows: rows,
            activeAgentSessions: activeAgentSessions,
            sessionRatePerHour: sessionRatePerHour,
            sessionProjectedFullAt: sessionProjectedFullAt.map { iso8601.string(from: $0) }
        )
    }

    static func encodeJSON(_ snapshot: UsageSnapshot) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
