import AppKit
import SwiftUI

private enum MenuTab: String, CaseIterable, Identifiable {
    case usage = "Usage"
    case history = "History"

    var id: String { rawValue }
}

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var activityMonitor: ClaudeCodeActivityMonitor
    @State private var selectedTab: MenuTab = .usage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .frame(width: 360)
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
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("เปิดบน iPhone (WiFi เดียวกัน)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack {
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(address, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("คัดลอกที่อยู่")
                }
            }
        }
    }

    @ViewBuilder
    private var activityStatusRow: some View {
        let active = activityMonitor.activeSessions
        if active.isEmpty {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text("Claude Code ว่างอยู่")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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
    }

    private var header: some View {
        HStack {
            Text("Plan usage limits")
                .font(.headline)
            Spacer()
            if selectedTab == .usage {
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading)
            } else {
                Button {
                    Task { await store.historyStore.refresh() }
                } label: {
                    if store.historyStore.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.historyStore.isLoading)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ยังไม่ได้ตั้งค่า Session Key")
                .font(.subheadline)
            Button("ตั้งค่าตอนนี้") {
                SettingsWindowPresenter.shared.show(store: store)
            }
        }
        .padding(.vertical, 4)
    }

    private func errorView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func usageContent(_ usage: UsageResponse) -> some View {
        if let session = usage.fiveHour {
            UsageRow(
                title: "Current session",
                resetsAt: FlexibleISO8601.date(from: session.resetsAt),
                percent: session.utilization ?? 0
            )
        }

        let weeklyLimits = usage.limits.filter { $0.group == "weekly" }
        if !weeklyLimits.isEmpty {
            Divider()
            Text("Weekly limits")
                .font(.subheadline)
                .bold()

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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Button("ตั้งค่า...") {
                SettingsWindowPresenter.shared.show(store: store)
            }
            Button("ออกจากแอป") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func displayName(for entry: LimitEntry) -> String {
        entry.scope?.model?.displayName ?? "All models"
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body)
                    if resetsAt != nil {
                        Text(ResetDescriber.describe(resetsAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text("\(percent)% used")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: Double(min(max(percent, 0), 100)), total: 100)
                .tint(color(for: percent))
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
