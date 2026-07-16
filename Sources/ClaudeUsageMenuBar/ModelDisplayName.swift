import Foundation

/// แปลง model id ดิบจาก transcript ให้อ่านง่าย —
/// "claude-sonnet-4-5-20250929" → "Sonnet 4.5", "claude-fable-5" → "Fable 5"
/// รูปแบบที่ไม่รู้จัก (เช่น id ตระกูลเก่า "claude-3-5-sonnet") คืนค่าดิบตามเดิม
/// แทนที่จะเดา
enum ModelDisplayName {
    static func display(for model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        guard parts.count >= 2, parts.removeFirst() == "claude" else { return model }

        // ตัด date snapshot ต่อท้าย (ตัวเลข 8 หลัก เช่น 20250929)
        if let last = parts.last, last.count == 8, Int(last) != nil {
            parts.removeLast()
        }
        guard let family = parts.first, Int(family) == nil, !parts.isEmpty else { return model }

        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}
