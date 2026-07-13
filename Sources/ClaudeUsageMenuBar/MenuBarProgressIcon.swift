import AppKit
import SwiftUI

/// The menu bar icon: Claude logo, two stacked battery-style progress bars
/// (current session on top, weekly "all models" usage below), and a compact
/// countdown to the next session reset.
private struct MenuBarProgressIcon: View {
    let sessionPercent: Int
    let weeklyPercent: Int
    let countdownText: String?
    let hasError: Bool
    /// Non-nil while Claude Code is actively working; drives the logo's bounce.
    let activityPhase: Double?

    private let logoSize: CGFloat = 14

    private var logoBounceOffset: CGFloat {
        guard let phase = activityPhase else { return 0 }
        return CGFloat(sin(phase * .pi)) * -2.5
    }
    private let barWidth: CGFloat = 26
    private let barHeight: CGFloat = 6
    private let barSpacing: CGFloat = 2

    private func fraction(_ percent: Int) -> CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }

    private func fillColor(for percent: Int) -> Color {
        if hasError { return .red }
        switch percent {
        case ..<70: return .blue
        case 70..<90: return .orange
        default: return .red
        }
    }

    private func bar(percent: Int) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white, lineWidth: 1)
                .frame(width: barWidth, height: barHeight)
            RoundedRectangle(cornerRadius: 1)
                .fill(fillColor(for: percent))
                .frame(width: max(2, (barWidth - 2) * fraction(percent)), height: barHeight - 2)
                .padding(.leading, 1)
        }
    }

    private var logoView: some View {
        Group {
            if let logo = ClaudeLogo.image {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Placeholder until a real Claude logo PNG is supplied — see ClaudeLogo.swift.
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: logoSize, height: logoSize)
        .offset(y: logoBounceOffset)
    }

    var body: some View {
        HStack(spacing: 4) {
            logoView
            VStack(alignment: .leading, spacing: barSpacing) {
                bar(percent: sessionPercent)
                bar(percent: weeklyPercent)
            }
            if let countdownText {
                Text(countdownText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
    }
}

/// Rasterizes `MenuBarProgressIcon` to a concrete, non-template `NSImage`.
///
/// `MenuBarExtra`/`NSStatusItem` auto-tints template images and plain SwiftUI
/// Shapes to a flat monochrome silhouette (so they adapt to light/dark menu
/// bars) — that's what made an earlier vector-only attempt at a colored ring
/// render as a barely-visible sliver. Pre-rendering to a bitmap and setting
/// `isTemplate = false` (the same technique third-party menu bar apps like
/// Bartender or Stats use) is what actually gets real color into the bar.
@MainActor
enum MenuBarIconRenderer {
    static func render(
        sessionPercent: Int?,
        weeklyPercent: Int?,
        countdownText: String?,
        hasError: Bool,
        activityPhase: Double? = nil
    ) -> NSImage {
        let view = MenuBarProgressIcon(
            sessionPercent: sessionPercent ?? 0,
            weeklyPercent: weeklyPercent ?? 0,
            countdownText: countdownText,
            hasError: hasError,
            activityPhase: activityPhase
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 60, height: 16))
        image.isTemplate = false
        return image
    }
}
