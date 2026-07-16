import Foundation
import ServiceManagement

/// ห่อ `SMAppService.mainApp` สำหรับ toggle "เปิดอัตโนมัติตอน login" —
/// ใช้ได้เฉพาะตอนรันจาก .app bundle (ผ่าน `./build_app.sh`) เพราะ
/// ServiceManagement ลงทะเบียนด้วย bundle identifier
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        guard isAvailable else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
