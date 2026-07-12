import NMPContent
import NMPUI
import XCTest
@testable import TwentyNinerNext

final class ChannelPreviewTests: XCTestCase {
    private let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
    private let profile = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpzfmhxue69uhhqatjwpkx2urpvuhx2ucl9q7qz"
    private let article = "naddr1qq3xummnw3ez6atw94shqupdv9kz6emfdaexumedwa5xjar994hx76tnv5pzpqlkerf45wg3uht9d22ym7hdj9xlnklpryzk5px0hd8nc8xu4j6aqvzqqqr4guzrk365"

    func testUnresolvedProfileHasBoundedPubkeyFallback() {
        XCTAssertEqual(
            ChannelPreviewText.profileName(pubkey: pubkey, profile: nil),
            "3bf0c63fcb…fa459d"
        )
    }

    func testResolvedProfileRefinesToDisplayName() {
        let metadata = NostrProfileMetadata(
            pubkey: pubkey,
            name: "fiatjaf",
            displayName: "fiatjaf resolved"
        )
        XCTAssertEqual(
            ChannelPreviewText.profileName(pubkey: pubkey, profile: metadata),
            "fiatjaf resolved"
        )
    }

    func testMultipleMentionsUseTheSharedParser() {
        let document = parseNostrContent("nostr:\(profile) met nostr:\(profile)")
        XCTAssertEqual(document.references.count, 2)
        XCTAssertEqual(Set(document.references.map(\.target.key)).count, 1)
    }

    func testArticleReferenceUsesAddressTarget() throws {
        let reference = try XCTUnwrap(
            parseNostrContent("nostr:\(article)").references.first
        )
        guard case .address(let kind, _, let identifier, _) = reference.target else {
            return XCTFail("expected an address reference")
        }
        XCTAssertEqual(kind, 30_023)
        XCTAssertEqual(identifier, "nostr-un-app-al-giorno-white-noise")
    }

    func testMalformedReferenceRemainsVisibleAndDoesNotAcquire() {
        let malformed = "nostr:npub1definitelybroken"
        let document = parseNostrContent(malformed)
        XCTAssertTrue(document.references.isEmpty)
        XCTAssertEqual(visibleSource(in: document), malformed)
    }

    func testUnresolvedEventLabelIsBounded() {
        let original = "nostr:" + String(repeating: "n", count: 90)
        let fallback = ChannelPreviewText.referenceFallback(original)
        XCTAssertLessThanOrEqual(fallback.count, 28)
        XCTAssertTrue(fallback.contains("…"))
    }

    private func visibleSource(in document: NostrContentDocument) -> String {
        document.blocks.flatMap(\.inlines).map { inline in
            switch inline {
            case .text(let text, _, _): text
            case .reference(let occurrence, _): occurrence.original
            case .hashtag(_, let original, _, _): original
            case .link(_, let label, _, _): label
            case .softBreak: " "
            case .hardBreak: "\n"
            }
        }.joined()
    }
}
