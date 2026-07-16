import Foundation

struct BurnRateSample: Equatable {
    let time: Date
    let percent: Int
}

/// ประเมิน "เพซการใช้งาน" ของ session ปัจจุบันจากจุดข้อมูล (เวลา, เปอร์เซ็นต์)
/// ที่เก็บจากการ poll แต่ละรอบ แล้วคาดการณ์ว่าจะแตะ 100% เมื่อไหร่
enum BurnRateEstimator {
    /// ช่วงเวลาขั้นต่ำระหว่างจุดแรกกับจุดสุดท้ายก่อนจะกล้าประเมิน — สั้นกว่านี้
    /// ความละเอียดของเปอร์เซ็นต์ (จำนวนเต็ม) ทำให้ค่าที่ได้เหวี่ยงเกินไป
    static let minimumSpan: TimeInterval = 180

    /// เปอร์เซ็นต์ต่อชั่วโมง หรือ nil ถ้าข้อมูลยังไม่พอ/เพซไม่ได้ไต่ขึ้น
    static func ratePerHour(samples: [BurnRateSample]) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return nil }
        let climbed = last.percent - first.percent
        guard climbed > 0 else { return nil }
        return Double(climbed) / span * 3600
    }

    /// เวลาที่คาดว่า session จะแตะ 100% ถ้าใช้เพซปัจจุบันต่อไป
    static func projectedFullDate(samples: [BurnRateSample]) -> Date? {
        guard let rate = ratePerHour(samples: samples), let last = samples.last else { return nil }
        let remaining = Double(100 - last.percent)
        guard remaining > 0 else { return last.time }
        return last.time.addingTimeInterval(remaining / rate * 3600)
    }
}
