import NMPContent
import XCTest
@testable import TwentyNinerNext

final class NIP27MessageContentTests: XCTestCase {
    private let npub =
        "npub14f8usejl26twx0dhuxjh9cas7keav9vr0v8nvtwtrjqx3vycc76qqh9nsy"
    private let nprofile =
        "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gppemhxue69uhhytnc9e3k7mf0qyt8wumn8ghj7er2vfshxtnnv9jxkc3wvdhk6tclr7lsh"
    private let note =
        "note1m99r7nwc0wdrkzldrqan96gklg5usqspq7z9696j6unf0ljnpxjspqfw99"
    private let nevent =
        "nevent1qqsdhet4232flykq3048jzc9msmaa3hnxuesxy3lnc33vd0wt9xwk6szyqewrqnkx4zsaweutf739s0cu7et29zrntqs5elw70vlm8zudr3y24sqsgy"
    private let naddr =
        "naddr1qqxnzd3exgersv33xymnsve3qgs8suecw4luyht9ekff89x4uacneapk8r5dyk0gmn6uwwurf6u9rusrqsqqqa282m3gxt"

    func testNostrEntityIsShortenedAndKeptDistinctFromLinks() {
        let token = "nostr:\(npub)"
        let segments = MessageContent.segments(of: "hi \(token)!")
        guard case .entity(let original, let label, _) = segments[1] else {
            return XCTFail("expected an entity segment, got \(segments)")
        }
        XCTAssertEqual(original, token)
        XCTAssertEqual(label, "npub14f8us…h9nsy")
        XCTAssertEqual(segments.last, .text("!"))
    }

    func testEntityWinsOverLinkDetectionOnOverlap() {
        let segments = MessageContent.segments(of: "nostr:\(note)")
        XCTAssertEqual(segments.count, 1)
        guard case .entity = segments[0] else {
            return XCTFail("expected an entity segment, got \(segments)")
        }
    }

    func testEverySupportedReferenceUsesNMPContentTypedTargetsInOrder() {
        let fixtures: [(String, (NostrReferenceTarget) -> Bool)] = [
            (npub, { if case .profile = $0 { return true }; return false }),
            (nprofile, { if case .profile = $0 { return true }; return false }),
            (note, { if case .event = $0 { return true }; return false }),
            (nevent, { if case .event = $0 { return true }; return false }),
            (naddr, { if case .address = $0 { return true }; return false }),
        ]
        let tokens = fixtures.map { "nostr:\($0.0)" }
        let entities: [(String, NostrReferenceTarget)] = MessageContent
            .segments(of: tokens.joined(separator: " | "))
            .compactMap { segment -> (String, NostrReferenceTarget)? in
                guard case .entity(let original, _, let target) = segment else { return nil }
                return (original, target)
            }

        XCTAssertEqual(entities.map { $0.0 }, tokens)
        for (index, entity) in entities.enumerated() {
            XCTAssertTrue(fixtures[index].1(entity.1), fixtures[index].0)
        }
    }

    func testMalformedTruncatedAndMixedCaseReferencesRemainText() {
        let malformed = "nostr:npub1notvalid"
        let truncated = "nostr:\(npub.dropLast())"
        let mixedCase = "nostr:nPub\(npub.dropFirst(4))"

        for token in [malformed, truncated, mixedCase] {
            XCTAssertEqual(MessageContent.segments(of: token), [.text(token)])
        }
    }

    func testMarkdownCodeAndLinkLabelsDoNotBecomeReferences() {
        let token = "nostr:\(npub)"
        for source in ["`\(token)`", "[\(token)](https://example.com)"] {
            XCTAssertFalse(
                MessageContent.segments(of: source).contains {
                    if case .entity = $0 { return true }
                    return false
                }
            )
        }
    }

    func testUnicodeAdjacentReferenceUsesExactUTF8SourceRange() {
        let token = "nostr:\(npub)"
        XCTAssertEqual(
            MessageContent.segments(of: "👋 \(token) καλημέρα"),
            [
                .text("👋 "),
                .entity(
                    token: token,
                    label: "npub14f8us…h9nsy",
                    target: .profile(
                        pubkey:
                            "aa4fc8665f5696e33db7e1a572e3b0f5b3d615837b0f362dcb1c8068b098c7b4"
                    )
                ),
                .text(" καλημέρα"),
            ]
        )
    }

    func testAttributedMentionUsesTypedNMPContentProfileTarget() {
        let attributed = MessageContent.attributed(
            "**nostr:\(npub)**",
            resolveMention: { pubkey in
                pubkey
                    == "aa4fc8665f5696e33db7e1a572e3b0f5b3d615837b0f362dcb1c8068b098c7b4"
                    ? "Alice"
                    : nil
            }
        )

        XCTAssertEqual(String(attributed.characters), "@Alice")
        XCTAssertTrue(
            attributed.runs.compactMap(\.inlinePresentationIntent).contains {
                $0.contains(.stronglyEmphasized)
            }
        )
    }
}
