import XCTest
@testable import ClaudeUsageMenuBar

final class InstalledAgentScannerTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("installed-agent-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testScanParsesNameAndDescriptionFromFrontmatter() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let content = """
        ---
        name: brain-writer
        description: Sub-agent for writing notes into the Second Brain.
        tools: Read, Write, Edit
        ---

        System prompt body, never parsed.
        """
        try content.write(to: dir.appendingPathComponent("brain-writer.md"), atomically: true, encoding: .utf8)

        let agents = InstalledAgentScanner.scan(directory: dir)

        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].name, "brain-writer")
        XCTAssertEqual(agents[0].description, "Sub-agent for writing notes into the Second Brain.")
    }

    func testScanSortsByNameCaseInsensitively() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "---\nname: zeta\ndescription: last\n---\n".write(
            to: dir.appendingPathComponent("zeta.md"), atomically: true, encoding: .utf8
        )
        try "---\nname: Alpha\ndescription: first\n---\n".write(
            to: dir.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8
        )

        let agents = InstalledAgentScanner.scan(directory: dir)

        XCTAssertEqual(agents.map(\.name), ["Alpha", "zeta"])
    }

    func testScanIgnoresNonMarkdownFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "not an agent".write(to: dir.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        XCTAssertTrue(InstalledAgentScanner.scan(directory: dir).isEmpty)
    }

    func testScanFallsBackToFileNameWhenNameFieldMissing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "---\ndescription: no name field\n---\n".write(
            to: dir.appendingPathComponent("mystery-agent.md"), atomically: true, encoding: .utf8
        )

        let agents = InstalledAgentScanner.scan(directory: dir)

        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].name, "mystery-agent")
        XCTAssertEqual(agents[0].description, "no name field")
    }

    func testScanHandlesFileWithoutFrontmatter() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "Just a plain markdown file, no frontmatter.".write(
            to: dir.appendingPathComponent("plain.md"), atomically: true, encoding: .utf8
        )

        let agents = InstalledAgentScanner.scan(directory: dir)

        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].name, "plain")
        XCTAssertEqual(agents[0].description, "")
    }

    func testScanEmptyDirectoryReturnsEmpty() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(InstalledAgentScanner.scan(directory: dir).isEmpty)
    }

    func testScanMissingDirectoryReturnsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertTrue(InstalledAgentScanner.scan(directory: missing).isEmpty)
    }

    func testParseFrontmatterFieldsSplitsOnlyFirstColon() {
        let fields = InstalledAgentScanner.parseFrontmatterFields("description: Trace WF_BPM_TASK: write logic")
        XCTAssertEqual(fields["description"], "Trace WF_BPM_TASK: write logic")
    }

    func testParseFrontmatterFieldsStripsSurroundingQuotes() {
        let fields = InstalledAgentScanner.parseFrontmatterFields(#"name: "quoted-name""#)
        XCTAssertEqual(fields["name"], "quoted-name")
    }

    func testExtractFrontmatterReturnsNilWithoutLeadingDelimiter() {
        XCTAssertNil(InstalledAgentScanner.extractFrontmatter(from: "no frontmatter here"))
    }
}
