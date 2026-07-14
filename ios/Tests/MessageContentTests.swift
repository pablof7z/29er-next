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

    func testAudioURLWithQueryBecomesAnAttachmentSegment() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/episode.mp3?token=abc"))
        let segments = MessageContent.segments(of: "listen \(url.absoluteString) now")
        XCTAssertEqual(
            segments,
            [.text("listen "), .audio(display: url.absoluteString, url: url), .text(" now")]
        )
    }

    func testAudioExtensionMatchingIgnoresCaseAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/Mix.FLAC#chapter"))
        XCTAssertTrue(MessageContent.isSupportedAudioURL(url))
    }

    func testSupportedAppleAudioExtensions() throws {
        for extensionName in ["aac", "aif", "aiff", "caf", "flac", "m4a", "m4b", "mp3", "wav"] {
            let url = try XCTUnwrap(URL(string: "https://cdn.example.com/audio.\(extensionName)"))
            XCTAssertTrue(MessageContent.isSupportedAudioURL(url), extensionName)
        }
    }

    func testAmbiguousAndUnsupportedMediaRemainLinks() throws {
        for extensionName in ["mp4", "m3u8", "ogg", "opus"] {
            let url = try XCTUnwrap(URL(string: "https://cdn.example.com/media.\(extensionName)"))
            XCTAssertEqual(
                MessageContent.segments(of: url.absoluteString),
                [.link(display: url.absoluteString, url: url)]
            )
        }
    }

    func testBlocksPreserveTextAndMultipleAudioAttachmentsInOrder() throws {
        let first = try XCTUnwrap(URL(string: "https://a.example/one.mp3"))
        let second = try XCTUnwrap(URL(string: "https://b.example/two.m4a"))
        XCTAssertEqual(
            MessageContent.blocks(of: "Intro \(first) middle \(second) outro"),
            [
                .inline([.text("Intro")]),
                .audio(display: first.absoluteString, url: first),
                .inline([.text("middle")]),
                .audio(display: second.absoluteString, url: second),
                .inline([.text("outro")])
            ]
        )
    }

    func testAudioOnlyMessageHasNoVisibleURLTextBlock() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example/audio.wav"))
        XCTAssertEqual(
            MessageContent.blocks(of: "  \(url.absoluteString)\n"),
            [.audio(display: url.absoluteString, url: url)]
        )
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

    func testImageLinksAreClassifiedForInlinePresentation() {
        let raw = "look https://cdn.example.com/photo.webp?width=1200"
        XCTAssertEqual(
            MessageContent.imageURLs(in: raw).map(\.absoluteString),
            ["https://cdn.example.com/photo.webp?width=1200"]
        )
    }

    func testOrdinaryLinksAreNotClassifiedAsImages() {
        XCTAssertFalse(MessageContent.isImageURL(URL(string: "https://example.com/app")!))
    }

    func testShortEntityShownWhole() {
        XCTAssertEqual(MessageContent.entityLabel(for: "nostr:note1abc"), "note1abc")
    }

    func testUppercaseEntitySchemeIsRemovedFromLabel() {
        XCTAssertEqual(MessageContent.entityLabel(for: "NOSTR:note1abc"), "note1abc")
    }
}
