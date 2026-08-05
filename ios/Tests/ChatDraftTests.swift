import NMP
import XCTest
@testable import TwentyNinerNext

/// What a chat message's rows are, now that NMP composes them.
///
/// These assert on the wire rows on purpose. The bug they replace was
/// invisible from Swift's side -- the app published a well-formed event that
/// no NIP-C7 client threaded, because a `q` row is NIP-18's QUOTE marker and
/// its whole job is keeping the referenced event out of the thread.
final class ChatDraftTests: XCTestCase {
    private let parentAuthor = String(repeating: "a", count: 64)
    private let mentioned = String(repeating: "b", count: 64)

    private func parentRow() -> Row {
        Row(
            id: String(repeating: "c", count: 64),
            pubkey: parentAuthor,
            createdAt: 1_700_000_000,
            kind: 9,
            tags: [],
            content: "the message being replied to",
            sig: String(repeating: "0", count: 128),
            sources: ["wss://nip29.example"]
        )
    }

    private func rows(_ payload: WritePayload) -> [[String]] {
        guard case .event(_, let tags, _, _) = payload else { return [] }
        return tags
    }

    private func kind(_ payload: WritePayload) -> UInt16? {
        guard case .event(let kind, _, _, _) = payload else { return nil }
        return kind
    }

    /// NMP names the reply with `e`. The app's old `q` row is gone, and the
    /// kind is NMP's rather than a constant this app states.
    func testReplyPointsWithEAndNeverWithQ() throws {
        let payload = try ChatDraft.payload(
            content: "hi",
            recipientPubkeys: [],
            replyTarget: parentRow()
        )
        let tags = rows(payload)

        XCTAssertEqual(kind(payload), 9)
        XCTAssertTrue(tags.contains { $0.first == "e" && $0.count > 1 && $0[1] == parentRow().id })
        XCTAssertFalse(tags.contains { $0.first == "q" })
    }

    /// The parent author is tagged once, by NMP, even when the composer also
    /// auto-mentions them -- which it does for every reply.
    func testTheParentAuthorIsNeverTaggedTwice() throws {
        let payload = try ChatDraft.payload(
            content: "hi",
            recipientPubkeys: [parentAuthor, mentioned],
            replyTarget: parentRow()
        )
        let tagged = rows(payload).filter { $0.first == "p" }.compactMap { $0.count > 1 ? $0[1] : nil }

        XCTAssertEqual(tagged.filter { $0 == parentAuthor }.count, 1)
        XCTAssertTrue(tagged.contains(mentioned))
    }

    /// A message that is not a reply carries only the rows naming who it
    /// addresses -- and duplicates in the recipient list collapse.
    func testTopLevelMessageCarriesOneRowPerAddressee() throws {
        let payload = try ChatDraft.payload(
            content: "hi",
            recipientPubkeys: [mentioned, mentioned, ""],
            replyTarget: nil
        )

        XCTAssertEqual(kind(payload), RoomKind.chat)
        XCTAssertEqual(rows(payload), [["p", mentioned]])
    }
}
