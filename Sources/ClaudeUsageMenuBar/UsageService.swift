import Foundation

protocol NetworkClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkClient {}

enum UsageServiceError: Error, LocalizedError {
    case noSessionKey
    case noOrganization
    case invalidResponse
    case unauthorized
    case httpError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noSessionKey:
            return "ยังไม่ได้ตั้งค่า Session Key กรุณาเปิดหน้าตั้งค่าเพื่อกรอกค่า"
        case .noOrganization:
            return "หา Organization ของบัญชีนี้ไม่พบ"
        case .invalidResponse:
            return "ไม่ได้รับการตอบกลับที่ถูกต้องจากเซิร์ฟเวอร์"
        case .unauthorized:
            return "Session Key หมดอายุหรือไม่ถูกต้อง กรุณาตั้งค่าใหม่"
        case .httpError(let code):
            return "เซิร์ฟเวอร์ตอบกลับด้วยรหัสข้อผิดพลาด \(code)"
        case .decodingFailed:
            return "รูปแบบข้อมูลที่ได้รับไม่ตรงกับที่คาดไว้"
        }
    }
}

struct ClaudeUsageService {
    static let baseURL = URL(string: "https://claude.ai")!

    let client: NetworkClient

    init(client: NetworkClient = URLSession.shared) {
        self.client = client
    }

    private func makeRequest(path: String, sessionKey: String) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw UsageServiceError.unauthorized
        default:
            throw UsageServiceError.httpError(http.statusCode)
        }
    }

    func fetchOrganizationId(sessionKey: String) async throws -> String {
        let data = try await perform(makeRequest(path: "/api/organizations", sessionKey: sessionKey))
        let orgs: [Organization]
        do {
            orgs = try JSONDecoder().decode([Organization].self, from: data)
        } catch {
            throw UsageServiceError.decodingFailed
        }
        guard let first = orgs.first else {
            throw UsageServiceError.noOrganization
        }
        return first.uuid
    }

    func fetchUsage(sessionKey: String, organizationId: String) async throws -> UsageResponse {
        let data = try await perform(
            makeRequest(path: "/api/organizations/\(organizationId)/usage", sessionKey: sessionKey)
        )
        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageServiceError.decodingFailed
        }
    }
}
