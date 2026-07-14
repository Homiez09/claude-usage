import XCTest
@testable import ClaudeUsageMenuBar

final class InstalledAgentSnapshotTests: XCTestCase {
    func testBuildMarksMatchingAgentAsRunning() {
        let agents = [
            InstalledAgent(id: "brain-writer", name: "brain-writer", description: "Writes notes"),
            InstalledAgent(id: "brain-reader", name: "brain-reader", description: "Reads notes")
        ]
        let snapshots = InstalledAgentSnapshotBuilder.build(agents: agents, activeSubagentTypes: ["brain-writer"])

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first { $0.name == "brain-writer" }?.isRunning, true)
        XCTAssertEqual(snapshots.first { $0.name == "brain-reader" }?.isRunning, false)
    }

    func testBuildWithNoActiveTypesMarksNothingRunning() {
        let agents = [InstalledAgent(id: "brain-writer", name: "brain-writer", description: "")]
        let snapshots = InstalledAgentSnapshotBuilder.build(agents: agents, activeSubagentTypes: [])
        XCTAssertEqual(snapshots.first?.isRunning, false)
    }

    func testEncodeJSONRoundTripsThroughDecoder() throws {
        let snapshots = [InstalledAgentSnapshot(name: "brain-writer", description: "Writes notes", isRunning: true)]
        let json = InstalledAgentSnapshotBuilder.encodeJSON(snapshots)
        let decoded = try JSONDecoder().decode([InstalledAgentSnapshot].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, snapshots)
    }

    func testEncodeJSONEmptyArray() {
        XCTAssertEqual(InstalledAgentSnapshotBuilder.encodeJSON([]), "[]")
    }
}
