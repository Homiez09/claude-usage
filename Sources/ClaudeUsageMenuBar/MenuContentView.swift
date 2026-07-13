import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

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
            footer
        }
        .padding(16)
        .frame(width: 320)
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

    private var header: some View {
        HStack {
            Text("Plan usage limits")
                .font(.headline)
            Spacer()
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
