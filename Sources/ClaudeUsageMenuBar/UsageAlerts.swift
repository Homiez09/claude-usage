import Foundation
import UserNotifications

/// ตัดสินใจว่า refresh รอบนี้ควรยิงแจ้งเตือนอะไรบ้าง เมื่อเปอร์เซ็นต์การใช้งาน
/// ข้าม threshold ขาขึ้น (80% / 95%) — เป็น pure logic แยกจากการยิง
/// notification จริง (`UsageNotifier`) เพื่อให้เทสต์ได้ตรงๆ ตามแนวทางของโปรเจกต์
enum UsageAlertPlanner {
    static let thresholds = [80, 95]

    struct Alert: Equatable {
        /// คีย์คงที่ต่อ limit หนึ่งตัว เช่น "session", "weekly_all-All models"
        let key: String
        /// ชื่อที่แสดงในข้อความแจ้งเตือน เช่น "Current session", "Opus"
        let title: String
        let percent: Int
        let threshold: Int
    }

    /// `firedThresholds` คือ threshold สูงสุดที่เคยยิงไปแล้วต่อคีย์ (สถานะจาก
    /// รอบก่อน) — ยิงเฉพาะตอนข้าม threshold ที่สูงกว่าเดิม และ re-arm ให้ยิงใหม่
    /// ได้เมื่อเปอร์เซ็นต์ตกกลับลงมา (โควตารีเซ็ต)
    static func plan(
        current: [(key: String, title: String, percent: Int)],
        firedThresholds: [String: Int]
    ) -> (alerts: [Alert], newState: [String: Int]) {
        var newState = firedThresholds
        var alerts: [Alert] = []

        for entry in current {
            guard let crossed = thresholds.filter({ entry.percent >= $0 }).max() else {
                // ตกกลับลงใต้ threshold ต่ำสุด → พร้อมแจ้งรอบใหม่
                newState[entry.key] = nil
                continue
            }
            if crossed > (firedThresholds[entry.key] ?? Int.min) {
                alerts.append(Alert(key: entry.key, title: entry.title, percent: entry.percent, threshold: crossed))
            }
            newState[entry.key] = crossed
        }
        return (alerts, newState)
    }

    /// ควรแจ้ง "โควตารีเซ็ตแล้ว" ไหม — เฉพาะตอน % ตกฮวบกลับมาต่ำหลังจากเคย
    /// ขึ้นถึงระดับที่แจ้งเตือนไว้ (ใกล้เต็ม) เท่านั้น ไม่งั้นการรีเซ็ตปกติ
    /// ทุกๆ 5 ชั่วโมงที่ผู้ใช้ไม่ได้รออะไรอยู่จะกลายเป็นสแปม
    static func shouldNotifyReset(previousPercent: Int?, currentPercent: Int) -> Bool {
        guard let previousPercent, let lowestThreshold = thresholds.min() else { return false }
        return previousPercent >= lowestThreshold && currentPercent <= 20
    }
}

/// ยิง macOS notification จากผลของ `UsageAlertPlanner`
///
/// หมายเหตุ: `UNUserNotificationCenter` ใช้ได้เฉพาะตอนรันจาก .app bundle
/// (ผ่าน `./build_app.sh`) — ตอน `swift run` ไม่มี bundle identifier จะข้าม
/// เงียบๆ แทนที่จะ crash
@MainActor
final class UsageNotifier {
    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private var authorizationRequested = false

    func requestAuthorizationIfNeeded() {
        guard Self.canNotify, !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(_ alerts: [UsageAlertPlanner.Alert]) {
        guard Self.canNotify, !alerts.isEmpty else { return }
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.threshold >= 95 ? "โควตาใกล้เต็มมาก" : "โควตาใกล้เต็ม"
            content.body = "\(alert.title) ใช้ไปแล้ว \(alert.percent)%"
            content.sound = .default
            center.add(
                UNNotificationRequest(
                    identifier: "usage-\(alert.key)-\(alert.threshold)",
                    content: content,
                    trigger: nil
                )
            )
        }
    }

    func sendSessionEnded(_ sessions: [SessionEndPlanner.EndedSession]) {
        guard Self.canNotify, !sessions.isEmpty else { return }
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        for session in sessions {
            let content = UNMutableNotificationContent()
            content.title = "Claude Code ทำงานเสร็จแล้ว"
            let minutes = max(1, Int(session.activeDuration / 60))
            content.body = "\(session.displayName) หยุดทำงานแล้ว (ทำต่อเนื่อง ~\(minutes) นาที)"
            content.sound = .default
            // identifier ต่อ session — ถ้า session เดิมจบซ้ำ (active ใหม่แล้วจบอีก)
            // จะแทนที่อันเก่าแทนที่จะกองใน Notification Center
            center.add(
                UNNotificationRequest(
                    identifier: "session-end-\(session.id)",
                    content: content,
                    trigger: nil
                )
            )
        }
    }

    func sendQuotaReset() {
        guard Self.canNotify else { return }
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "โควตารีเซ็ตแล้ว"
        content.body = "Session ใหม่เริ่มแล้ว ใช้งาน Claude ได้เต็มที่"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "quota-reset", content: content, trigger: nil)
        )
    }
}
