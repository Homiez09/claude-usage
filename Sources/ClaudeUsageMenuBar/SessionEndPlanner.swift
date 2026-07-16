import Foundation

/// ตัดสินใจว่า poll รอบนี้มี Claude Code session ไหน "เพิ่งทำงานเสร็จ" บ้าง —
/// คือเคย active ต่อเนื่องนานพอแล้วรอบนี้กลายเป็น idle — เป็น pure logic
/// แยกจากการยิง notification จริง (`UsageNotifier`) เพื่อให้เทสต์ได้ตรงๆ
/// ตามแนวทางของโปรเจกต์
///
/// ทำงานบนผลสแกนที่ `ClaudeCodeActivityMonitor` มีอยู่แล้วในแต่ละ poll
/// จึงไม่มี I/O หรือ timer เพิ่ม — state ทั้งหมดคือ dict เล็กๆ
/// `[sessionID: เวลาที่เริ่ม active]`
enum SessionEndPlanner {
    /// ต้อง active ต่อเนื่องอย่างน้อยเท่านี้ถึงนับว่าเป็น "งาน" ที่ควรแจ้งตอนจบ
    /// — กันเคสถาม-ตอบสั้นๆ ที่ transcript เงียบเพราะผู้ใช้กำลังอ่านคำตอบ
    /// ไม่ใช่เพราะงานเสร็จ (ค่านี้รวม active window ~45s ของ monitor แล้ว)
    static let minimumActiveDuration: TimeInterval = 120

    struct EndedSession: Equatable {
        let id: String
        let displayName: String
        let activeDuration: TimeInterval
    }

    /// `activeSince` คือสถานะจากรอบก่อน (session ไหนเริ่ม active เมื่อไหร่) —
    /// คืน session ที่เพิ่งจบพร้อมสถานะใหม่สำหรับรอบถัดไป Subagent ไม่นับ
    /// เพราะการจบของมันไม่ใช่เหตุการณ์ระดับผู้ใช้ (session แม่ยังทำงานต่อ)
    static func plan(
        activeSince: [String: Date],
        sessions: [ClaudeCodeSessionStatus],
        minimumActiveDuration: TimeInterval = SessionEndPlanner.minimumActiveDuration,
        now: Date = Date()
    ) -> (ended: [EndedSession], newActiveSince: [String: Date]) {
        var newActiveSince: [String: Date] = [:]
        var ended: [EndedSession] = []

        for session in sessions where !session.isSubagent {
            if session.isActive {
                newActiveSince[session.id] = activeSince[session.id] ?? now
            } else if let since = activeSince[session.id] {
                let duration = now.timeIntervalSince(since)
                if duration >= minimumActiveDuration {
                    ended.append(EndedSession(
                        id: session.id,
                        displayName: session.displayName,
                        activeDuration: duration
                    ))
                }
            }
        }
        return (ended, newActiveSince)
    }
}
