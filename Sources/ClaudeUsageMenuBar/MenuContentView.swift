import AppKit
import SwiftUI

private enum MenuTab: String, CaseIterable, Identifiable {
    case usage = "Usage"
    case history = "History"

    var id: String { rawValue }
}

/// Accent palette shared by both the Mac dropdown and (conceptually) the web
/// page — warm "Claude orange" as the brand accent, with the usual
/// blue/orange/red traffic-light scale for utilization.
private enum Palette {
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
}

/// Consistent card chrome (thin material + rounded corners + hairline border)
/// used for every grouped block in the dropdown.
private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var activityMonitor: ClaudeCodeActivityMonitor
    @State private var selectedTab: MenuTab = .usage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if selectedTab == .usage {
                activityStatusRow
            }

            Picker("", selection: $selectedTab) {
                ForEach(MenuTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedTab {
            case .usage:
                usageTab
            case .history:
                UsageHistoryView(store: store.historyStore)
                    .task { await store.historyStore.refreshIfNeeded() }
            }

            footer
        }
        .padding(16)
        .frame(width: 370)
        .background(
            LinearGradient(
                colors: [Palette.brand.opacity(0.05), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var usageTab: some View {
        if !store.hasSessionKey {
            emptyState
        } else if let usage = store.usage {
            usageContent(usage)
        } else if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if let errorMessage = store.errorMessage {
            errorView(errorMessage)
        }

        localAddressSection
    }

    @ViewBuilder
    private var localAddressSection: some View {
        if let address = store.localWebServerAddress {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("เปิดบน iPhone (WiFi เดียวกัน)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(address, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(Palette.brand)
                }
                .buttonStyle(.plain)
                .help("คัดลอกที่อยู่")
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var activityStatusRow: some View {
        let active = activityMonitor.activeSessions
        HStack(spacing: 6) {
            if active.isEmpty {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text("Claude Code ว่างอยู่")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(active) { session in
                        HStack(spacing: 6) {
                            PulsingDot()
                            Text(session.displayName)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(active.isEmpty ? Color.secondary.opacity(0.08) : Color.green.opacity(0.12))
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.brandGradient)
                    .frame(width: 30, height: 30)
                if let logo = ClaudeLogo.image {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "sparkle")
                        .foregroundColor(.white)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude Usage")
                    .font(.system(.headline, design: .rounded))
                Text(selectedTab == .usage ? "Plan usage limits" : "Local cost history")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if selectedTab == .usage {
                RefreshButton(isLoading: store.isLoading) {
                    Task { await store.refresh() }
                }
            } else {
                RefreshButton(isLoading: store.historyStore.isLoading) {
                    Task { await store.historyStore.refresh() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ยังไม่ได้ตั้งค่า Session Key")
                .font(.subheadline.weight(.medium))
            Button("ตั้งค่าตอนนี้") {
                SettingsWindowPresenter.shared.show(store: store)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func errorView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func usageContent(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = usage.fiveHour {
                UsageRow(
                    title: "Current session",
                    resetsAt: FlexibleISO8601.date(from: session.resetsAt),
                    percent: session.utilization ?? 0
                )
            }

            let weeklyLimits = usage.limits.filter { $0.group == "weekly" }
            if !weeklyLimits.isEmpty {
                Text("WEEKLY LIMITS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)

                ForEach(weeklyLimits) { entry in
                    UsageRow(
                        title: displayName(for: entry),
                        resetsAt: FlexibleISO8601.date(from: entry.resetsAt),
                        percent: entry.percent
                    )
                }
            }

            if let errorMessage = store.errorMessage {
                errorView(errorMessage)
            }

            if let lastUpdated = store.lastUpdated {
                Text("Last updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                SettingsWindowPresenter.shared.show(store: store)
            } label: {
                Label("ตั้งค่า", systemImage: "gearshape")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("ออกจากแอป", systemImage: "power")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 2)
    }

    private func displayName(for entry: LimitEntry) -> String {
        entry.scope?.model?.displayName ?? "All models"
    }
}

/// Small circular refresh control shared by both tabs' headers.
private struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 26, height: 26)
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// A small green dot that pulses continuously — the "actively working"
/// indicator next to each running Claude Code session's name.
private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.4 : 0.8)
            .opacity(isPulsing ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

private struct UsageRow: View {
    let title: String
    let resetsAt: Date?
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(.body, design: .rounded).weight(.medium))
                    if resetsAt != nil {
                        Text(ResetDescriber.describe(resetsAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text("\(percent)%")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundColor(color(for: percent))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Palette.fill(for: percent))
                        .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                }
            }
            .frame(height: 7)
        }
    }

    private func color(for percent: Int) -> Color {
        switch percent {
        case ..<70: return .blue
        case 70..<90: return .orange
        default: return .red
        }
    }
}
