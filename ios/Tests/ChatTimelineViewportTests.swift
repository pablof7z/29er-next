import XCTest
@testable import TwentyNinerNext

final class ChatTimelineViewportTests: XCTestCase {
    func testBottomAnchorInsideViewportIsVisible() {
        XCTAssertTrue(
            ChatTimelineViewport.bottomAnchorIsVisible(
                frame: CGRect(x: 0, y: 799, width: 1, height: 1),
                viewportHeight: 800
            )
        )
    }

    func testBottomAnchorBelowViewportIsNotVisible() {
        XCTAssertFalse(
            ChatTimelineViewport.bottomAnchorIsVisible(
                frame: CGRect(x: 0, y: 801, width: 1, height: 1),
                viewportHeight: 800
            )
        )
    }

    func testBottomAnchorAboveViewportIsNotVisible() {
        XCTAssertFalse(
            ChatTimelineViewport.bottomAnchorIsVisible(
                frame: CGRect(x: 0, y: -2, width: 1, height: 1),
                viewportHeight: 800
            )
        )
    }
}
