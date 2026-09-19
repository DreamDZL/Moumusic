import XCTest
@testable import KumoneCore

final class PlaylistSectionOrderTests: XCTestCase {
    func testMissingAndInvalidValuesFallBackToDefaultSections() {
        XCTAssertEqual(
            PlaylistSectionOrder.normalized(["qq", "unknown"]),
            [.qq, .netease, .local]
        )
    }

    func testOrderPersistsAsRawValues() {
        let suiteName = "PlaylistSectionOrderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PlaylistSectionOrder.save([.qq, .local, .netease], to: defaults)
        XCTAssertEqual(PlaylistSectionOrder.load(from: defaults), [.qq, .local, .netease])
    }
}
