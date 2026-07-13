import XCTest
@testable import TwentyNinerNext

final class MessageContentTests: XCTestCase {
    func testPlainTextIsASingleTextSegment() {
        XCTAssertEqual(MessageContent.segments(of: "just a message"), [.text("just a message")])
    }

    func testEmptyStringHasNoSegments() {
        XCTAssertEqual(MessageContent.segments(of: ""), [])
    }

    func testHTTPSURLBecomesALink() {
        let segments = MessageContent.segments(of: "see https://njump.me/abc now")
        guard case .link(let display, let url) = segments[1] else {
            return XCTFail("expected a link segment, got \(segments)")
        }
        XCTAssertEqual(display, "https://njump.me/abc")
        XCTAssertEqual(url.absoluteString, "https://njump.me/abc")
        XCTAssertEqual(segments.first, .text("see "))
        XCTAssertEqual(segments.last, .text(" now"))
    }

    func testNostrEntityIsShortenedAndKeptDistinctFromLinks() {
        let npub = "nostr:npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
        let segments = MessageContent.segments(of: "hi \(npub)!")
        guard case .entity(let token, let label) = segments[1] else {
            return XCTFail("expected an entity segment, got \(segments)")
        }
        XCTAssertEqual(token, npub)
        XCTAssertEqual(label, "npub180cvv…jh6w6")
        // The trailing "!" must survive as its own text run.
        XCTAssertEqual(segments.last, .text("!"))
    }

    func testEntityWinsOverLinkDetectionOnOverlap() {
        // A bare nostr: URI must render as an entity, never a web link.
        let segments = MessageContent.segments(of: "nostr:note1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqq")
        XCTAssertEqual(segments.count, 1)
        guard case .entity = segments[0] else {
            return XCTFail("expected an entity segment, got \(segments)")
        }
    }

    func testMultipleLinksAndText() {
        let segments = MessageContent.segments(of: "a http://x.io b https://y.io")
        let links = segments.filter { if case .link = $0 { return true } else { return false } }
        XCTAssertEqual(links.count, 2)
    }

    func testNonWebURLIsNotLinked() {
        XCTAssertEqual(
            MessageContent.segments(of: "download ftp://example.com/file"),
            [.text("download ftp://example.com/file")]
        )
    }

    func testAttributedStringCarriesLinkAttribute() {
        let attributed = MessageContent.attributed("go https://example.com")
        let hasLink = attributed.runs.contains { $0.link != nil }
        XCTAssertTrue(hasLink)
    }

    func testShortEntityShownWhole() {
        XCTAssertEqual(MessageContent.entityLabel(for: "nostr:note1abc"), "note1abc")
    }

    func testUppercaseEntitySchemeIsRemovedFromLabel() {
        XCTAssertEqual(MessageContent.entityLabel(for: "NOSTR:note1abc"), "note1abc")
    }
}
