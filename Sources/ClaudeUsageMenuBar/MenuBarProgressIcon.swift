import AppKit

/// Rasterizes the menu bar icon directly using AppKit drawing context (NSGraphicsContext).
/// This completely bypasses SwiftUI's ImageRenderer, eliminating all its internal
/// caching/memory buildup bugs, resulting in near-zero memory footprint and ultra-low CPU usage.
@MainActor
enum MenuBarIconRenderer {
    static func render(
        sessionPercent: Int?,
        weeklyPercent: Int?,
        countdownText: String?,
        hasError: Bool,
        activityPhase: Double? = nil,
        barWidth: Double = 26.0,
        showSessionBar: Bool = true,
        showWeeklyBar: Bool = true
    ) -> NSImage {
        let logoSize: CGFloat = 14
        let spacing: CGFloat = 4
        
        // Calculate text width
        let textFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.white
        ]
        let hasText = countdownText != nil && !(countdownText?.isEmpty ?? true)
        let textWidth = hasText ? (countdownText!.size(withAttributes: textAttrs).width) : 0
        
        // Calculate total size
        let hasBars = showSessionBar || showWeeklyBar
        var totalWidth: CGFloat = logoSize
        if hasBars {
            totalWidth += spacing + CGFloat(barWidth)
        }
        if hasText {
            totalWidth += spacing + textWidth
        }
        totalWidth += 2 // Padding
        
        let size = NSSize(width: totalWidth, height: 16)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // 1. Draw Logo
        let logoBounceOffset: CGFloat
        if let phase = activityPhase {
            logoBounceOffset = CGFloat(sin(phase * .pi)) * 2.0 // Bounce up (y goes up in macOS AppKit coordinate space!)
        } else {
            logoBounceOffset = 0
        }
        
        // AppKit coordinates have origin (0,0) at bottom-left!
        let logoY = 1.0 + logoBounceOffset
        
        if let logo = ClaudeLogo.image {
            logo.draw(in: NSRect(x: 1, y: logoY, width: logoSize, height: logoSize))
        } else {
            // Draw a fallback sparkles system image
            if let sparkle = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
                sparkle.isTemplate = true
                NSColor.orange.set()
                sparkle.draw(in: NSRect(x: 1, y: logoY, width: logoSize, height: logoSize))
            }
        }
        
        var currentX = logoSize + spacing
        
        // 2. Draw Progress Bars
        if hasBars {
            let sessionVal = sessionPercent ?? 0
            let weeklyVal = weeklyPercent ?? 0
            
            if showSessionBar && showWeeklyBar {
                // Top bar (Session)
                drawBar(percent: sessionVal, x: currentX, y: 9, width: CGFloat(barWidth), height: 5, hasError: hasError)
                // Bottom bar (Weekly)
                drawBar(percent: weeklyVal, x: currentX, y: 2, width: CGFloat(barWidth), height: 5, hasError: hasError)
            } else {
                // Single bar centered
                let singleBarPercent = showSessionBar ? sessionVal : weeklyVal
                drawBar(percent: singleBarPercent, x: currentX, y: 4, width: CGFloat(barWidth), height: 8, hasError: hasError)
            }
            
            currentX += CGFloat(barWidth) + spacing
        }
        
        // 3. Draw Text
        if hasText, let text = countdownText {
            // Center text vertically
            let textY = (16 - textFont.capHeight) / 2.0 - 1.0
            text.draw(at: NSPoint(x: currentX, y: textY), withAttributes: textAttrs)
        }
        
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
    
    private static func drawBar(percent: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, hasError: Bool) {
        // Draw outer border (white)
        let borderPath = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: 2, yRadius: 2)
        NSColor.white.setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        // Draw fill
        let fraction = CGFloat(min(max(percent, 0), 100)) / 100.0
        let fillWidth = max(2.0, (width - 2) * fraction)
        let fillRect = NSRect(x: x + 1, y: y + 1, width: fillWidth, height: height - 2)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1)
        
        let fillColor: NSColor
        if hasError {
            fillColor = .systemRed
        } else {
            switch percent {
            case ..<70:
                fillColor = .systemBlue
            case 70..<90:
                fillColor = .systemOrange
            default:
                fillColor = .systemRed
            }
        }
        fillColor.setFill()
        fillPath.fill()
    }
}
