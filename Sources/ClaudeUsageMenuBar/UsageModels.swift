import Foundation

struct UsageResponse: Decodable {
    let fiveHour: LimitWindow?
    let sevenDay: LimitWindow?
    let limits: [LimitEntry]

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }
}

struct LimitWindow: Decodable {
    let utilization: Int?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct LimitEntry: Decodable, Identifiable {
    let group: String
    let kind: String
    let percent: Int
    let resetsAt: String?
    let severity: String
    let scope: LimitScope?

    var id: String { kind + "-" + (scope?.model?.displayName ?? "") }

    enum CodingKeys: String, CodingKey {
        case group, kind, percent, severity, scope
        case resetsAt = "resets_at"
    }
}

struct LimitScope: Decodable {
    let model: ModelInfo?
}

struct ModelInfo: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct Organization: Decodable {
    let uuid: String
}
