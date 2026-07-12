import XCTest
@testable import TwentyNinerNext

final class MentionProjectionTests: XCTestCase {
    private let me = "me-pubkey"

    private func mention(
        id: String,
        author: String,
        at createdAt: UInt64,
        tags: [[String]],
        content: String = "hi"
    ) -> Mention? {
        MentionProjection.mention(
            id: id,
            pubkey: author,
            createdAt: createdAt,
            kind: 9,
            tags: tags,
            content: content,
            recipient: me
        )
    }

    func testMessagePTaggingMeIsAMention() {
        let result = mention(id: "1", author: "alice", at: 100, tags: [["h", "room"], ["p", me]])
        XCTAssertEqual(result?.id, "1")
        XCTAssertEqual(result?.author, "alice")
        XCTAssertEqual(result?.groupLocalID, "room")
    }

    func testMessageWithoutMyPTagIsNotAMention() {
        XCTAssertNil(mention(id: "1", author: "alice", at: 100, tags: [["h", "room"], ["p", "someone-else"]]))
    }

    func testSelfAuthoredMessageIsNotAMention() {
        XCTAssertNil(mention(id: "1", author: me, at: 100, tags: [["h", "room"], ["p", me]]))
    }

    func testMentionWithoutRoomTagIsDropped() {
        XCTAssertNil(mention(id: "1", author: "alice", at: 100, tags: [["p", me]]))
    }

    func testNonChatKindIsNotAMention() {
        let result = MentionProjection.mention(
            id: "1", pubkey: "alice", createdAt: 100, kind: 1,
            tags: [["h", "room"], ["p", me]], content: "hi", recipient: me
        )
        XCTAssertNil(result)
    }

    func testPTagsExtractsNonEmptyPValues() {
        let tags = [["p", "a"], ["p", ""], ["e", "x"], ["p", "b"]]
        XCTAssertEqual(MentionProjection.pTags(tags), ["a", "b"])
    }
}

@MainActor
final class MentionReadsTests: XCTestCase {
    private func makeReads(seededAt: UInt64) -> MentionReads {
        let defaults = UserDefaults(suiteName: "inbox-tests-\(seededAt)-\(UUID().uuidString)")!
        return MentionReads(store: MentionReadStore(defaults: defaults), now: seededAt)
    }

    func testMentionOlderThanSeedIsTreatedAsRead() {
        let reads = makeReads(seededAt: 1_000)
        XCTAssertFalse(reads.isUnread(id: "old", createdAt: 999))
    }

    func testMentionAtOrAfterSeedStartsUnread() {
        let reads = makeReads(seededAt: 1_000)
        XCTAssertTrue(reads.isUnread(id: "new", createdAt: 1_000))
        XCTAssertTrue(reads.isUnread(id: "newer", createdAt: 2_000))
    }

    func testMarkReadClearsUnread() {
        let reads = makeReads(seededAt: 1_000)
        XCTAssertTrue(reads.isUnread(id: "new", createdAt: 2_000))
        reads.markRead("new")
        XCTAssertFalse(reads.isUnread(id: "new", createdAt: 2_000))
        XCTAssertTrue(reads.readIDs.contains("new"))
    }

    func testReadStateAndSeedPersistAcrossInstances() {
        let defaults = UserDefaults(suiteName: "inbox-persist-\(UUID().uuidString)")!
        let store = MentionReadStore(defaults: defaults)

        let first = MentionReads(store: store, now: 1_000)
        first.markRead("seen")

        // A later launch passes a different `now`, but the persisted seed wins.
        let second = MentionReads(store: store, now: 5_000)
        XCTAssertEqual(second.seededAt, 1_000)
        XCTAssertTrue(second.readIDs.contains("seen"))
        XCTAssertFalse(second.isUnread(id: "seen", createdAt: 2_000))
        XCTAssertTrue(second.isUnread(id: "fresh", createdAt: 2_000))
    }
}
