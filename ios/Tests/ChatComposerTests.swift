import XCTest
@testable import TwentyNinerNext

final class ChatComposerTests: XCTestCase {
    private func recipient(_ pubkey: String, name: String) -> ComposerRecipient {
        ComposerRecipient(pubkey: pubkey, displayName: name, pictureURL: nil, activity: nil)
    }

    func testWhitespaceOnlyDraftHasNoMessage() {
        XCTAssertNil(ChatComposerState.message(from: " \n\t "))
    }

    func testMessageIsTrimmedBeforeSubmission() throws {
        XCTAssertEqual(try XCTUnwrap(ChatComposerState.message(from: "  Hello room  ")), "Hello room")
    }

    func testRequestKeepsReplyAuthorFirstAndDeduplicatesManualSelection() throws {
        let agent = recipient("agent", name: "agent1")
        let other = recipient("other", name: "agent2")
        let reply = ComposerReply(eventID: "event", author: agent, preview: "Earlier")

        let request = try XCTUnwrap(
            ChatComposerState.request(
                draft: "  Hello  ",
                selectedRecipients: [other, agent],
                reply: reply
            )
        )

        XCTAssertEqual(request.content, "Hello")
        XCTAssertEqual(request.recipients.map(\.pubkey), ["agent", "other"])
        XCTAssertEqual(request.reply, reply)
    }

    func testMentionLabelRemovesAnExistingAtPrefix() {
        XCTAssertEqual(recipient("agent", name: "@agent1").mentionLabel, "@agent1")
    }
}
