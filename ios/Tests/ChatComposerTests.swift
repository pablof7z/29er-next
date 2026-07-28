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
        XCTAssertTrue(request.attachments.isEmpty)
    }

    func testAttachmentOnlyDraftCanBeSubmitted() throws {
        let attachment = ComposerAttachment(
            filename: "diagram.png",
            contentType: "image/png",
            data: Data("image".utf8)
        )

        let request = try XCTUnwrap(
            ChatComposerState.request(
                draft: " \n ",
                selectedRecipients: [],
                reply: nil,
                attachments: [attachment]
            )
        )

        XCTAssertEqual(request.content, "")
        XCTAssertEqual(request.attachments, [attachment])
    }

    func testUploadedURLsAreAppendedWithoutChangingDraftSemantics() throws {
        let first = try XCTUnwrap(URL(string: "https://relay.example/a.png"))
        let second = try XCTUnwrap(URL(string: "https://relay.example/b.pdf"))

        XCTAssertEqual(
            ChatComposerState.messageContent(
                draft: "  Look at these  ",
                attachmentURLs: [first, second]
            ),
            "Look at these\n\nhttps://relay.example/a.png\nhttps://relay.example/b.pdf"
        )
        XCTAssertEqual(
            ChatComposerState.messageContent(draft: "", attachmentURLs: [first]),
            "https://relay.example/a.png"
        )
    }

    func testMentionLabelRemovesAnExistingAtPrefix() {
        XCTAssertEqual(recipient("agent", name: "@agent1").mentionLabel, "@agent1")
    }

    func testVoiceActionAppearsWithoutSubstantiveText() {
        XCTAssertTrue(ChatComposerState.showsVoiceAction(draft: " \n ", attachments: []))
    }

    func testVoiceActionYieldsToTextOrAttachments() {
        let attachment = ComposerAttachment(
            filename: "draft.m4a",
            contentType: "audio/mp4",
            data: Data("audio".utf8)
        )

        XCTAssertFalse(ChatComposerState.showsVoiceAction(draft: "hello", attachments: []))
        XCTAssertFalse(ChatComposerState.showsVoiceAction(draft: "", attachments: [attachment]))
    }

    func testEveryoneIsNotSelectedUntilAllPickableRecipientsAreTagged() {
        let a = recipient("a", name: "agent1")
        let b = recipient("b", name: "agent2")

        XCTAssertFalse(
            ChatComposerState.everyoneIsSelected(
                pickable: [a, b],
                selectedRecipients: [a],
                requiredRecipientID: nil
            )
        )
        XCTAssertTrue(
            ChatComposerState.everyoneIsSelected(
                pickable: [a, b],
                selectedRecipients: [a, b],
                requiredRecipientID: nil
            )
        )
    }

    func testEveryoneIsSelectedCountsTheRequiredReplyRecipientEvenIfNotInSelection() {
        let a = recipient("a", name: "agent1")
        let b = recipient("b", name: "agent2")

        XCTAssertTrue(
            ChatComposerState.everyoneIsSelected(
                pickable: [a, b],
                selectedRecipients: [b],
                requiredRecipientID: "a"
            )
        )
    }

    func testTogglingEveryoneAddsEveryPickableRecipientOnce() {
        let a = recipient("a", name: "agent1")
        let b = recipient("b", name: "agent2")
        let c = recipient("c", name: "agent3")

        let toggled = ChatComposerState.togglingEveryone(
            pickable: [a, b, c],
            selectedRecipients: [b],
            requiredRecipientID: nil
        )

        XCTAssertEqual(Set(toggled.map(\.pubkey)), ["a", "b", "c"])
    }

    func testTogglingEveryoneAgainClearsBackToJustTheRequiredRecipient() {
        let a = recipient("a", name: "agent1")
        let b = recipient("b", name: "agent2")

        let toggled = ChatComposerState.togglingEveryone(
            pickable: [a, b],
            selectedRecipients: [a, b],
            requiredRecipientID: "a"
        )

        XCTAssertEqual(toggled.map(\.pubkey), ["a"])
    }

    func testTogglingEveryoneAgainWithNoRequiredRecipientClearsEntirely() {
        let a = recipient("a", name: "agent1")
        let b = recipient("b", name: "agent2")

        let toggled = ChatComposerState.togglingEveryone(
            pickable: [a, b],
            selectedRecipients: [a, b],
            requiredRecipientID: nil
        )

        XCTAssertTrue(toggled.isEmpty)
    }
}
