import XCTest
@testable import TwentyNinerNext

final class ChatComposerTests: XCTestCase {
    func testWhitespaceOnlyDraftHasNoMessage() {
        XCTAssertNil(ChatComposerState.message(from: " \n\t "))
    }

    func testMessageIsTrimmedBeforeSubmission() throws {
        XCTAssertEqual(try XCTUnwrap(ChatComposerState.message(from: "  Hello room  ")), "Hello room")
    }
}
