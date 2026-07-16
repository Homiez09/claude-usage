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
}
