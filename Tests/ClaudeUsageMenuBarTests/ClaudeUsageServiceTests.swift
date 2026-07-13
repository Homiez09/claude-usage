import XCTest
@testable import ClaudeUsageMenuBar

private struct MockNetworkClient: NetworkClient {
    var handler: (URLRequest) throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

private func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

final class ClaudeUsageServiceTests: XCTestCase {
    func testFetchUsageSuccess() async throws {
        let json = """
        { "five_hour": { "utilization": 41, "resets_at": "2026-07-13T07:30:00+00:00" }, "limits": [] }
        """
        let client = MockNetworkClient { request in
            XCTAssertEqual(request.url?.path, "/api/organizations/org-123/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=test-session")
            return (Data(json.utf8), makeResponse(url: request.url!, statusCode: 200))
        }
        let service = ClaudeUsageService(client: client)

        let usage = try await service.fetchUsage(sessionKey: "test-session", organizationId: "org-123")
        XCTAssertEqual(usage.fiveHour?.utilization, 41)
    }

    func testFetchOrganizationIdSuccess() async throws {
        let json = """
        [{"uuid": "org-123"}]
        """
        let client = MockNetworkClient { request in
            XCTAssertEqual(request.url?.path, "/api/organizations")
            return (Data(json.utf8), makeResponse(url: request.url!, statusCode: 200))
        }
        let service = ClaudeUsageService(client: client)

        let orgId = try await service.fetchOrganizationId(sessionKey: "test-session")
        XCTAssertEqual(orgId, "org-123")
    }

    func testFetchOrganizationIdEmptyListThrows() async {
        let client = MockNetworkClient { request in
            (Data("[]".utf8), makeResponse(url: request.url!, statusCode: 200))
        }
        let service = ClaudeUsageService(client: client)

        do {
            _ = try await service.fetchOrganizationId(sessionKey: "test-session")
            XCTFail("Expected noOrganization error")
        } catch UsageServiceError.noOrganization {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnauthorizedMapsToUnauthorizedError() async {
        let client = MockNetworkClient { request in
            (Data(), makeResponse(url: request.url!, statusCode: 401))
        }
        let service = ClaudeUsageService(client: client)

        do {
            _ = try await service.fetchUsage(sessionKey: "bad-session", organizationId: "org-123")
            XCTFail("Expected unauthorized error")
        } catch UsageServiceError.unauthorized {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerErrorMapsToHttpError() async {
        let client = MockNetworkClient { request in
            (Data(), makeResponse(url: request.url!, statusCode: 500))
        }
        let service = ClaudeUsageService(client: client)

        do {
            _ = try await service.fetchUsage(sessionKey: "test-session", organizationId: "org-123")
            XCTFail("Expected httpError")
        } catch UsageServiceError.httpError(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedJSONMapsToDecodingFailed() async {
        let client = MockNetworkClient { request in
            (Data("not json".utf8), makeResponse(url: request.url!, statusCode: 200))
        }
        let service = ClaudeUsageService(client: client)

        do {
            _ = try await service.fetchUsage(sessionKey: "test-session", organizationId: "org-123")
            XCTFail("Expected decodingFailed")
        } catch UsageServiceError.decodingFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPResponseThrowsInvalidResponse() async {
        let client = MockNetworkClient { request in
            (Data(), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        let service = ClaudeUsageService(client: client)

        do {
            _ = try await service.fetchUsage(sessionKey: "test-session", organizationId: "org-123")
            XCTFail("Expected invalidResponse")
        } catch UsageServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
