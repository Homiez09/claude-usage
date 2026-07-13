import SwiftUI

/// Shows local Claude Code token usage (from `~/.claude/projects/**/*.jsonl`)
/// aggregated by day/month/year, with an estimated equivalent-API-cost figure.
/// This is a personal usage reference, not an actual bill — Claude Code on a
/// subscription plan draws from a flat quota, not per-token pricing.
struct UsageHistoryView: View {
    @ObservedObject var store: ClaudeCodeHistoryStore
    @State private var granularity: UsageHistoryGranularity = .day

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $granularity) {
                ForEach(UsageHistoryGranularity.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("ประมาณการเทียบเท่าราคา API ไม่ใช่บิลจริง")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let buckets = store.buckets(for: granularity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(buckets) { bucket in
                            HistoryRow(
                                bucket: bucket,
                                currencyFormatter: Self.currencyFormatter,
                                tokenFormatter: Self.tokenFormatter
                            )
                        }
                    }
                }
                .frame(minHeight: 420, maxHeight: 520)
            }

            if let lastScanned = store.lastScanned {
                Text("Last scanned: \(lastScanned.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct HistoryRow: View {
    let bucket: UsageHistoryBucket
    let currencyFormatter: NumberFormatter
    let tokenFormatter: NumberFormatter

    var body: some View {
        HStack {
            Text(bucket.label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(currencyFormatter.string(from: NSNumber(value: bucket.totalCostUSD)) ?? "$0.00")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(tokenFormatter.string(from: NSNumber(value: bucket.totalTokens)) ?? "0") tokens")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
