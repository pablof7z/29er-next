import XCTest
@testable import TwentyNinerNext

final class ChatTimelineViewportTests: XCTestCase {
    func testContentBottomAtViewportBottomIsScrolledToBottom() {
        XCTAssertTrue(
            ChatTimelineViewport.isScrolledToBottom(
                contentFrame: CGRect(x: 0, y: -2400, width: 400, height: 3200),
                viewportHeight: 800
            )
        )
    }

    func testContentBottomBelowViewportIsNotScrolledToBottom() {
        XCTAssertFalse(
            ChatTimelineViewport.isScrolledToBottom(
                contentFrame: CGRect(x: 0, y: -2200, width: 400, height: 3200),
                viewportHeight: 800
            )
        )
    }

    func testShortContentThatFitsEntirelyIsScrolledToBottom() {
        // All messages fit in the viewport with room to spare -- nothing to
        // scroll to, so this counts as "at the bottom".
        XCTAssertTrue(
            ChatTimelineViewport.isScrolledToBottom(
                contentFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
                viewportHeight: 800
            )
        )
    }

    func testContentBottomStaysScrolledToBottomWellPastVirtualizedRows() {
        // Regression: previously this signal came from a 1pt sentinel inside
        // the lazily-instantiated row list, which could freeze at a stale
        // value once scrolled far enough that the sentinel was
        // de-instantiated. The content frame is always the LazyVStack's own
        // (always-tracked) bounds, so a deep scroll position still resolves
        // correctly.
        XCTAssertFalse(
            ChatTimelineViewport.isScrolledToBottom(
                contentFrame: CGRect(x: 0, y: 200, width: 400, height: 40000),
                viewportHeight: 800
            )
        )
    }

    func testHistoryPrependAnchorUsesTopVisibleMessage() {
        XCTAssertEqual(
            ChatTimelineViewport.topVisibleMessageID(
                visibleIndices: [3, 4, 5],
                messageIDs: ["a", "b", "c", "d", "e", "f"]
            ),
            "d"
        )
        XCTAssertNil(
            ChatTimelineViewport.topVisibleMessageID(
                visibleIndices: [],
                messageIDs: ["a"]
            )
        )
    }
}
