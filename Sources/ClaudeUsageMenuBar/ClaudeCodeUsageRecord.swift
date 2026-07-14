import Foundation

/// One assistant turn's token usage, pulled from a local Claude Code transcript.
/// Deliberately carries no conversation content — only the numbers needed for
/// aggregation and cost estimation.
struct ClaudeCodeUsageRecord {
    let messageID: String
    let date: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    init(
        messageID: String = "",
        date: Date,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int
    ) {
        self.messageID = messageID
        self.date = date
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Estimated cost had this usage been billed at standard API rates.
    /// Returns 0 for models with no known pricing rather than guessing.
    var estimatedCostUSD: Double {
        guard let pricing = PricingCatalog.pricing(for: model) else { return 0 }
        let millionTokens = 1_000_000.0
        return Double(inputTokens) / millionTokens * pricing.inputPerMTok
            + Double(outputTokens) / millionTokens * pricing.outputPerMTok
            + Double(cacheCreationTokens) / millionTokens * pricing.cacheWritePerMTok
            + Double(cacheReadTokens) / millionTokens * pricing.cacheReadPerMTok
    }
}
