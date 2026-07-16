import SwiftUI

/// มุมมองของแท็บ History — สลับได้สามแบบ: ตามช่วงเวลา (วัน/เดือน/ปี),
/// ตามโมเดล, ตามโปรเจกต์
private enum HistoryViewMode: String, CaseIterable, Identifiable {
    case periods = "ช่วงเวลา"
    case models = "โมเดล"
    case projects = "โปรเจกต์"

    var id: String { rawValue }
}

/// Shows local Claude Code token usage (from `~/.claude/projects/**/*.jsonl`)
/// aggregated by day/month/year, with an estimated equivalent-API-cost figure.
/// This is a personal usage reference, not an actual bill — Claude Code on a
/// subscription plan draws from a flat quota, not per-token pricing.
struct UsageHistoryView: View {
    @ObservedObject var store: ClaudeCodeHistoryStore
    @State private var granularity: UsageHistoryGranularity = .day
    @State private var mode: HistoryViewMode = .periods

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
            Picker("", selection: $mode) {
                ForEach(HistoryViewMode.allCases) { option in
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
                switch mode {
                case .periods:
                    periodsSection
                case .models:
                    breakdownList(
                        items: store.modelBreakdown().map { ($0.name, $0.costUSD, $0.tokens) },
                        icon: "cpu"
                    )
                case .projects:
                    breakdownList(
                        items: store.projectBreakdown().map { ($0.name, $0.costUSD, $0.tokens) },
                        icon: "folder"
                    )
                }
            }

            if let lastScanned = store.lastScanned {
                Text("Last scanned: \(lastScanned.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var periodsSection: some View {
        Picker("", selection: $granularity) {
            ForEach(UsageHistoryGranularity.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        let buckets = store.buckets(for: granularity)
        let maxCost = buckets.map(\.totalCostUSD).max() ?? 0

        HistoryBarChart(
            buckets: Array(buckets.prefix(14).reversed()),
            currencyFormatter: Self.currencyFormatter
        )

        ScrollView {
            VStack(spacing: 6) {
                ForEach(buckets) { bucket in
                    BreakdownRow(
                        icon: "clock",
                        label: bucket.label,
                        costUSD: bucket.totalCostUSD,
                        tokens: bucket.totalTokens,
                        fraction: maxCost > 0 ? bucket.totalCostUSD / maxCost : 0,
                        currencyFormatter: Self.currencyFormatter,
                        tokenFormatter: Self.tokenFormatter
                    )
                }
            }
        }
        .frame(minHeight: 300, maxHeight: 400)
    }

    @ViewBuilder
    private func breakdownList(items: [(name: String, costUSD: Double, tokens: Int)], icon: String) -> some View {
        if items.isEmpty {
            Text("ไม่มีข้อมูล")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            let maxCost = items.map(\.costUSD).max() ?? 0
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items, id: \.name) { item in
                        BreakdownRow(
                            icon: icon,
                            label: item.name,
                            costUSD: item.costUSD,
                            tokens: item.tokens,
                            fraction: maxCost > 0 ? item.costUSD / maxCost : 0,
                            currencyFormatter: Self.currencyFormatter,
                            tokenFormatter: Self.tokenFormatter
                        )
                    }
                }
            }
            .frame(minHeight: 340, maxHeight: 440)
        }
    }
}

/// กราฟแท่งย่อของช่วงล่าสุด (เรียงเก่า→ใหม่ ซ้าย→ขวา) — แท่งขวาสุดคือช่วง
/// ปัจจุบันจึงเน้นด้วยสีแบรนด์เต็ม ที่เหลือจางลง hover ดูรายละเอียดได้จาก
/// tooltip
private struct HistoryBarChart: View {
    let buckets: [UsageHistoryBucket]
    let currencyFormatter: NumberFormatter

    private static let chartHeight: CGFloat = 52

    var body: some View {
        if buckets.count > 1 {
            let maxCost = buckets.map(\.totalCostUSD).max() ?? 0
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(buckets) { bucket in
                    let isCurrent = bucket.id == buckets.last?.id
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Palette.brandGradient)
                        .opacity(isCurrent ? 1.0 : 0.4)
                        .frame(height: barHeight(for: bucket, maxCost: maxCost))
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .help("\(bucket.label) · \(currencyFormatter.string(from: NSNumber(value: bucket.totalCostUSD)) ?? "")")
                }
            }
            .frame(height: Self.chartHeight, alignment: .bottom)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05))
            )
        }
    }

    private func barHeight(for bucket: UsageHistoryBucket, maxCost: Double) -> CGFloat {
        guard maxCost > 0 else { return 3 }
        return max(3, Self.chartHeight * CGFloat(bucket.totalCostUSD / maxCost))
    }
}

/// แถวสรุปหนึ่งรายการ (ช่วงเวลา/โมเดล/โปรเจกต์) พร้อมแถบพื้นหลังบอกสัดส่วน
/// เทียบกับรายการที่แพงสุดในลิสต์ ให้ทั้งลิสต์อ่านเป็นกราฟแท่งแนวนอนได้ในตัว
private struct BreakdownRow: View {
    let icon: String
    let label: String
    let costUSD: Double
    let tokens: Int
    /// สัดส่วนค่าใช้จ่ายเทียบกับรายการแพงสุด (0–1)
    let fraction: Double
    let currencyFormatter: NumberFormatter
    let tokenFormatter: NumberFormatter

    var body: some View {
        HStack {
            Circle()
                .fill(Palette.brand.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.brand)
                )
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(currencyFormatter.string(from: NSNumber(value: costUSD)) ?? "$0.00")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("\(tokenFormatter.string(from: NSNumber(value: tokens)) ?? "0") tokens")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            GeometryReader { geo in
                Rectangle()
                    .fill(Palette.brand.opacity(0.10))
                    .frame(width: max(0, geo.size.width * fraction))
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        )
    }
}
