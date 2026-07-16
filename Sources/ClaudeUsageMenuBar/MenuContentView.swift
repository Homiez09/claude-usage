import AppKit
import SwiftUI

private enum MenuTab: String, CaseIterable, Identifiable {
    case usage = "Usage"
    case history = "History"
    case subagents = "Subagents"

    var id: String { rawValue }
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
    @State private var installedAgents: [InstalledAgent] = []
    @State private var showQRCode = false
    @State private var qrImage: NSImage?

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
            case .subagents:
                installedAgentsTab
                    // Re-scan every time this tab is shown — agent definition
                    // files change rarely, so there's no need for a
                    // continuous FSEvents watcher like the transcript
                    // scanners use.
                    .task(id: selectedTab) {
                        if selectedTab == .subagents {
                            installedAgents = InstalledAgentScanner.scan()
                        }
                    }
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

        quickStatsSection
        localAddressSection
    }

    /// การ์ดสรุปย่อ "วันนี้ / เดือนนี้" จาก historyStore (ประมาณการเทียบเท่า
    /// ราคา API เช่นเดียวกับแท็บ History) — historyStore ถูก refresh อัตโนมัติ
    /// อยู่แล้วโดย `UsageStore` จึงไม่ต้องสแกนเพิ่มที่นี่
    @ViewBuilder
    private var quickStatsSection: some View {
        let calendar = Calendar.current
        let today = store.historyStore.buckets(for: .day)
            .first { calendar.isDateInToday($0.periodStart) }
        let thisMonth = store.historyStore.buckets(for: .month)
            .first { calendar.isDate($0.periodStart, equalTo: Date(), toGranularity: .month) }

        if today != nil || thisMonth != nil {
            HStack(spacing: 8) {
                QuickStatCard(
                    icon: "sun.max.fill",
                    title: "วันนี้",
                    costUSD: today?.totalCostUSD ?? 0,
                    tokens: today?.totalTokens ?? 0
                )
                QuickStatCard(
                    icon: "calendar",
                    title: "เดือนนี้",
                    costUSD: thisMonth?.totalCostUSD ?? 0,
                    tokens: thisMonth?.totalTokens ?? 0
                )
            }
        }
    }

    @ViewBuilder
    private var localAddressSection: some View {
        if let address = store.localWebServerAddress {
            VStack(spacing: 10) {
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
                        if showQRCode {
                            showQRCode = false
                        } else {
                            qrImage = QRCodeGenerator.image(for: address)
                            showQRCode = true
                        }
                    } label: {
                        Image(systemName: "qrcode")
                            .foregroundColor(showQRCode ? .white : Palette.brand)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(showQRCode ? Palette.brand : Palette.brand.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("แสดง QR code ให้ iPhone สแกน")
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

                if showQRCode, let qrImage {
                    VStack(spacing: 5) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 128, height: 128)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                            )
                        Text("สแกนด้วยกล้อง iPhone")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var activityStatusRow: some View {
        let active = activityMonitor.activeSessions
        let topLevel = active.filter { !$0.isSubagent }
        // A subagent's `id` is "<parentSessionID>/<agentFileBaseName>" — a
        // subagent can occasionally show up active while its parent
        // transcript hasn't been touched recently enough to still count as
        // active, so those are rendered on their own rather than dropped.
        let orphanSubagents = active.filter { session in
            session.isSubagent && !topLevel.contains { session.id.hasPrefix("\($0.id)/") }
        }

        HStack(spacing: 6) {
            if active.isEmpty {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text("Claude Code ว่างอยู่")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topLevel) { session in
                        sessionRow(session, subagents: subagents(for: session, in: active))
                    }
                    if !orphanSubagents.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(orphanSubagents) { SubagentIcon(session: $0) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active.isEmpty ? Color.secondary.opacity(0.08) : Color.green.opacity(0.12))
        )
    }

    private func subagents(for parent: ClaudeCodeSessionStatus, in all: [ClaudeCodeSessionStatus]) -> [ClaudeCodeSessionStatus] {
        all.filter { $0.isSubagent && $0.id.hasPrefix("\(parent.id)/") }
    }

    /// Catalog of installed subagent *types* (`~/.claude/agents/*.md`), not
    /// a log of past runs — see `InstalledAgentScanner`. Whatever's shown
    /// here also determines what `Agent(subagent_type:)` can spawn.
    ///
    /// `activeSubagentTypes` cross-references `activityMonitor.activeSessions`
    /// (already live-updating for free via FSEvents — see
    /// `ClaudeCodeActivityMonitor`) against each installed agent's `name` to
    /// show a "running now" badge, without any extra file scanning.
    private var installedAgentsTab: some View {
        let activeSubagentTypes = Set(activityMonitor.activeSessions.compactMap(\.subagentType))

        return Group {
            if installedAgents.isEmpty {
                Text("ไม่พบ agent ที่ติดตั้งไว้ที่ ~/.claude/agents")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(installedAgents) { agent in
                            InstalledAgentRow(agent: agent, isRunning: activeSubagentTypes.contains(agent.name))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func sessionRow(_ session: ClaudeCodeSessionStatus, subagents: [ClaudeCodeSessionStatus]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                BouncingDot()
                Text(session.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let caption = subtitle(for: session) {
                HStack(spacing: 6) {
                    Spacer().frame(width: 12)
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            if !subagents.isEmpty {
                HStack(spacing: 4) {
                    Spacer().frame(width: 12)
                    ForEach(subagents) { SubagentIcon(session: $0) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.brand.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Palette.brand.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Palette.brand.opacity(0.18), radius: 5, y: 1)
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
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            switch selectedTab {
            case .usage:
                RefreshButton(isLoading: store.isLoading) {
                    Task { await store.refresh() }
                }
            case .history:
                RefreshButton(isLoading: store.historyStore.isLoading) {
                    Task { await store.historyStore.refresh() }
                }
            case .subagents:
                EmptyView()
            }
        }
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .usage: return "Plan usage limits"
        case .history: return "Local cost history"
        case .subagents: return "Installed subagents"
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
                burnRateLine
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

    /// บรรทัดเพซใต้ Current session — โชว์เมื่อข้อมูลพอประเมิน (poll ห่างกัน
    /// อย่างน้อย 3 นาทีและ % ไต่ขึ้น ดู `BurnRateEstimator`)
    @ViewBuilder
    private var burnRateLine: some View {
        if let rate = store.sessionBurnRatePerHour, let projected = store.sessionProjectedFullAt {
            let willFillBeforeReset = store.sessionResetsAt.map { projected < $0 } ?? false
            let rateText = String(format: "%.1f", rate)
            HStack(spacing: 5) {
                Image(systemName: willFillBeforeReset ? "flame.fill" : "speedometer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(willFillBeforeReset ? .orange : .secondary)
                Text(willFillBeforeReset
                    ? "เพซ ~\(rateText)%/ชม. — จะเต็มก่อนรีเซ็ต ~\(projected.formatted(date: .omitted, time: .shortened))"
                    : "เพซ ~\(rateText)%/ชม. ไม่น่าเต็มก่อนรีเซ็ต")
                    .font(.caption2.weight(willFillBeforeReset ? .semibold : .regular))
                    .foregroundColor(willFillBeforeReset ? .orange : .secondary)
            }
            .padding(.top, -4)
        }
    }

    private var memoryUsageString: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let mb = Double(info.resident_size) / 1024.0 / 1024.0
            return String(format: "%.1f MB", mb)
        }
        return "N/A"
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

            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text(memoryUsageString)
            }
            .font(.caption2)
            .foregroundColor(.secondary)

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

    /// Second line under a session's name: for a subagent, its type (e.g.
    /// "general-purpose") plus the model, if known; for a top-level session,
    /// just the model.
    private func subtitle(for session: ClaudeCodeSessionStatus) -> String? {
        let parts = session.isSubagent
            ? [session.subagentType, session.model]
            : [session.model]
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}

/// การ์ดสถิติย่อหนึ่งใบ (ไอคอน + หัวข้อ + ค่าใช้จ่าย + โทเคน) ใช้ในแถว
/// "วันนี้ / เดือนนี้" ของแท็บ Usage
private struct QuickStatCard: View {
    let icon: String
    let title: String
    let costUSD: Double
    let tokens: Int

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.brand.opacity(0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.brand)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(costUSD, format: .currency(code: "USD"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                Text("\(Self.compactTokens(tokens)) tokens")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private static func compactTokens(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000: return "\(tokens)"
        case ..<1_000_000: return String(format: "%.1fK", Double(tokens) / 1_000)
        default: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
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

/// A small badge with the Claude logo for one active subagent — hover shows
/// its name (and model, if known) as a tooltip via `.help()`, since there's
/// no room to spell out every subagent's name inline next to its parent
/// session.
private struct SubagentIcon: View {
    let session: ClaudeCodeSessionStatus
    @State private var isPulsing = false

    var body: some View {
        Group {
            if let logo = ClaudeLogo.image {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "sparkle")
                    .foregroundColor(.white)
            }
        }
        .frame(width: 13, height: 13)
        .padding(4)
        .background(Circle().fill(Color.green.opacity(0.15)))
        .overlay(Circle().strokeBorder(Color.green.opacity(0.35), lineWidth: 1))
        .opacity(isPulsing ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .help(tooltip)
    }

    private var tooltip: String {
        var text = session.displayName
        if let model = session.model {
            text += " · \(model)"
        }
        return text
    }
}

/// A small green dot that bounces up and down continuously — the "actively
/// working" indicator next to a top-level session's name, distinct from
/// `PulsingDot`'s blink so a real session reads as "moving" rather than
/// "blinking" at a glance.
private struct BouncingDot: View {
    @State private var isBouncing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .offset(y: isBouncing ? -3 : 3)
            .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: isBouncing)
            .onAppear { isBouncing = true }
    }
}

/// One row in the "Subagents" tab: icon, agent name, its description from
/// `~/.claude/agents/<name>.md`'s frontmatter, and a live "running now"
/// badge when a session with this exact `subagent_type` is currently active.
private struct InstalledAgentRow: View {
    let agent: InstalledAgent
    let isRunning: Bool
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let logo = ClaudeLogo.image {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "sparkle")
                        .foregroundColor(.white)
                }
            }
            .frame(width: 15, height: 15)
            .padding(4)
            .background(Circle().fill(isRunning ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1)))

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !agent.description.isEmpty {
                    Text(agent.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            if isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
                        .onAppear { isPulsing = true }
                    Text("กำลังทำงาน")
                        .font(.system(size: 9).weight(.medium))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 3)
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
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Palette.tint(for: percent))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.tint(for: percent).opacity(0.12)))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Palette.fill(for: percent))
                        .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                        .shadow(color: Palette.tint(for: percent).opacity(0.35), radius: 3, y: 1)
                }
            }
            .frame(height: 7)
        }
    }
}
