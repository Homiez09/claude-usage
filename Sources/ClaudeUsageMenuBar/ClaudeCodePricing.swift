import Foundation

/// Published Anthropic API pricing per model, in USD per million tokens.
/// Cache write/read rates aren't published per-model — they're a fixed multiple
/// of the input rate (write ≈1.25x for 5-minute TTL, read ≈0.1x), per Anthropic's
/// prompt-caching pricing documentation.
struct ModelPricing {
    let inputPerMTok: Double
    let outputPerMTok: Double

    var cacheWritePerMTok: Double { inputPerMTok * 1.25 }
    var cacheReadPerMTok: Double { inputPerMTok * 0.1 }
}

/// This estimates what local Claude Code usage would have cost under standard
/// API (pay-per-token) pricing — it is NOT an actual bill. Claude Code on a
/// Pro/Max subscription draws from a flat quota, not per-token billing; this
/// number is a reference point for how much usage you're generating, in the
/// same spirit as the community `ccusage` tool.
enum PricingCatalog {
    static let byModel: [String: ModelPricing] = [
        "claude-fable-5": ModelPricing(inputPerMTok: 10.00, outputPerMTok: 50.00),
        "claude-mythos-5": ModelPricing(inputPerMTok: 10.00, outputPerMTok: 50.00),
        "claude-opus-4-8": ModelPricing(inputPerMTok: 5.00, outputPerMTok: 25.00),
        "claude-opus-4-7": ModelPricing(inputPerMTok: 5.00, outputPerMTok: 25.00),
        "claude-opus-4-6": ModelPricing(inputPerMTok: 5.00, outputPerMTok: 25.00),
        "claude-opus-4-5": ModelPricing(inputPerMTok: 5.00, outputPerMTok: 25.00),
        "claude-opus-4-1": ModelPricing(inputPerMTok: 5.00, outputPerMTok: 25.00),
        "claude-opus-4-0": ModelPricing(inputPerMTok: 5.00, outputPerMTok: 25.00),
        "claude-sonnet-5": ModelPricing(inputPerMTok: 3.00, outputPerMTok: 15.00),
        "claude-sonnet-4-6": ModelPricing(inputPerMTok: 3.00, outputPerMTok: 15.00),
        "claude-sonnet-4-5": ModelPricing(inputPerMTok: 3.00, outputPerMTok: 15.00),
        "claude-sonnet-4-0": ModelPricing(inputPerMTok: 3.00, outputPerMTok: 15.00),
        "claude-haiku-4-5": ModelPricing(inputPerMTok: 1.00, outputPerMTok: 5.00),
    ]

    /// Looks up by exact model string first, then by alias prefix so dated
    /// snapshot IDs (e.g. "claude-sonnet-4-5-20250929") resolve to their base
    /// alias's published rate. Returns nil for unrecognized models rather than
    /// guessing a price.
    static func pricing(for model: String) -> ModelPricing? {
        if let exact = byModel[model] {
            return exact
        }
        for (alias, pricing) in byModel where model.hasPrefix(alias + "-") {
            return pricing
        }
        return nil
    }
}
