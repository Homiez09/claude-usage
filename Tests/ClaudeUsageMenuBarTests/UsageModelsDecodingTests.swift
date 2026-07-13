import XCTest
@testable import ClaudeUsageMenuBar

final class UsageModelsDecodingTests: XCTestCase {
    /// Captured verbatim from a real GET /api/organizations/{id}/usage response,
    /// including the assorted null/experiment fields the endpoint returns alongside
    /// the fields this app actually cares about.
    private let sampleJSON = """
    {
      "amber_ladder": null,
      "extra_usage": {
        "currency": null,
        "is_enabled": false
      },
      "five_hour": {
        "limit_dollars": null,
        "remaining_dollars": null,
        "resets_at": "2026-07-13T07:30:00.473904+00:00",
        "used_dollars": null,
        "utilization": 41
      },
      "limits": [
        {
          "group": "session",
          "is_active": false,
          "kind": "session",
          "percent": 41,
          "resets_at": "2026-07-13T07:30:00.473904+00:00",
          "scope": null,
          "severity": "normal"
        },
        {
          "group": "weekly",
          "is_active": true,
          "kind": "weekly_all",
          "percent": 43,
          "resets_at": "2026-07-15T16:00:00.473930+00:00",
          "scope": null,
          "severity": "normal"
        },
        {
          "group": "weekly",
          "is_active": false,
          "kind": "weekly_scoped",
          "percent": 16,
          "resets_at": "2026-07-15T16:00:00.474283+00:00",
          "scope": {
            "model": {
              "display_name": "Fable",
              "id": null
            },
            "surface": null
          },
          "severity": "normal"
        }
      ],
      "member_dashboard_available": false,
      "seven_day": {
        "limit_dollars": null,
        "remaining_dollars": null,
        "resets_at": "2026-07-15T16:00:00.473930+00:00",
        "used_dollars": null,
        "utilization": 43
      },
      "spend": {
        "enabled": false,
        "percent": 0
      },
      "tangelo": null
    }
    """

    func testDecodesRealWorldResponse() throws {
        let data = Data(sampleJSON.utf8)
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

        XCTAssertEqual(usage.fiveHour?.utilization, 41)
        XCTAssertEqual(usage.fiveHour?.resetsAt, "2026-07-13T07:30:00.473904+00:00")
        XCTAssertEqual(usage.sevenDay?.utilization, 43)
        XCTAssertEqual(usage.limits.count, 3)

        let weeklyAll = usage.limits.first { $0.kind == "weekly_all" }
        XCTAssertEqual(weeklyAll?.percent, 43)
        XCTAssertEqual(weeklyAll?.group, "weekly")
        XCTAssertNil(weeklyAll?.scope?.model)

        let scoped = usage.limits.first { $0.kind == "weekly_scoped" }
        XCTAssertEqual(scoped?.percent, 16)
        XCTAssertEqual(scoped?.scope?.model?.displayName, "Fable")
    }

    func testDecodesMissingOptionalWindows() throws {
        let json = """
        { "limits": [] }
        """
        let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        XCTAssertNil(usage.fiveHour)
        XCTAssertNil(usage.sevenDay)
        XCTAssertTrue(usage.limits.isEmpty)
    }

    func testDecodesOrganizationList() throws {
        let json = """
        [{"uuid": "403ee795-d4cd-40cc-8305-4028b5f1801d", "name": "Personal"}]
        """
        let orgs = try JSONDecoder().decode([Organization].self, from: Data(json.utf8))
        XCTAssertEqual(orgs.first?.uuid, "403ee795-d4cd-40cc-8305-4028b5f1801d")
    }
}
