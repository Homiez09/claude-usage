import AppKit
import CoreImage

/// สร้างภาพ QR code ด้วย CoreImage (ไม่ต้องพึ่ง dependency ภายนอก) —
/// ใช้แสดงลิงก์หน้าเว็บ local ให้ iPhone สแกนแทนการพิมพ์ IP เอง
enum QRCodeGenerator {
    static func image(for string: String, scale: CGFloat = 8) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
