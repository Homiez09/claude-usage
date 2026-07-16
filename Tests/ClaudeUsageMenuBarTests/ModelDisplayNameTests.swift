import XCTest
@testable import ClaudeUsageMenuBar

final class ModelDisplayNameTests: XCTestCase {
    func testStripsClaudePrefixAndJoinsVersionParts() {
        XCTAssertEqual(ModelDisplayName.display(for: "claude-sonnet-5"), "Sonnet 5")
        XCTAssertEqual(ModelDisplayName.display(for: "claude-opus-4-8"), "Opus 4.8")
        XCTAssertEqual(ModelDisplayName.display(for: "claude-haiku-4-5"), "Haiku 4.5")
    }

    func testStripsDateSnapshotSuffix() {
        XCTAssertEqual(ModelDisplayName.display(for: "claude-sonnet-4-5-20250929"), "Sonnet 4.5")
    }

    func testFamilyOnlyModelHasNoTrailingSpace() {
        XCTAssertEqual(ModelDisplayName.display(for: "claude-fable-5"), "Fable 5")
    }

    func testUnrecognizedFormatReturnsRawString() {
        XCTAssertEqual(ModelDisplayName.display(for: "<synthetic>"), "<synthetic>")
        XCTAssertEqual(ModelDisplayName.display(for: "gpt-4"), "gpt-4")
        XCTAssertEqual(ModelDisplayName.display(for: "claude"), "claude")
    }
}
