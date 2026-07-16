import SwiftUI

/// ชุดสีที่ใช้ร่วมกันทุก view ฝั่ง Mac (และล้อกับตัวแปร CSS ของหน้าเว็บ) —
/// ส้ม "Claude orange" เป็นสีแบรนด์ ส่วนระดับการใช้งานใช้สเกลไฟจราจร
/// น้ำเงิน/ส้ม/แดง ตามเปอร์เซ็นต์
enum Palette {
    static let brand = Color(red: 0.82, green: 0.42, blue: 0.20)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.90, green: 0.50, blue: 0.24), Color(red: 0.75, green: 0.32, blue: 0.14)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func fill(for percent: Int) -> LinearGradient {
        switch percent {
        case ..<70:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
        case 70..<90:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
        }
    }

    static func tint(for percent: Int) -> Color {
        switch percent {
        case ..<70: return .blue
        case 70..<90: return .orange
        default: return .red
        }
    }
}
