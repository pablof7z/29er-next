import NMP
import XCTest
@testable import TwentyNinerNext

final class TTS29ParsingTests: XCTestCase {
    private func row(
        id: String,
        pubkey: String = "author",
        createdAt: UInt64 = 100,
        kind: UInt16 = 9,
        tags: [[String]],
        content: String = ""
    ) -> Row {
        Row(
            id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags,
            content: content, sig: "", sources: []
        )
    }

    // MARK: - Item parsing

    func testPlainMessageIsNotASpokenItem() {
        let plain = row(id: "1", tags: [["h", "group"]], content: "hello")
        XCTAssertNil(TTS29ItemParsing.item(from: plain))
    }

    func testMarkerWithoutTitleIsRejected() {
        let event = row(id: "1", tags: [["tts29", "item", "1"], ["h", "g"]])
        XCTAssertNil(TTS29ItemParsing.item(from: event))
    }

    func testParsesTitleAudioAttachmentsAndAgent() {
        let event = row(
            id: "item1",
            tags: [
                ["tts29", "item", "1"],
                ["h", "g"],
                ["title", "Daemon proposal"],
                ["summary", "A short summary"],
                ["agent", "Indigo"],
                ["audio", "https://cdn.example/a.mp3", "abc", "audio/mpeg", "1234"],
                ["attachment", "https://cdn.example/diagram.png", "def", "image/png", "999", "Diagram"]
            ],
            content: "The spoken body."
        )
        let item = try? XCTUnwrap(TTS29ItemParsing.item(from: event))
        XCTAssertEqual(item?.title, "Daemon proposal")
        XCTAssertEqual(item?.summary, "A short summary")
        XCTAssertEqual(item?.agentName, "Indigo")
        XCTAssertEqual(item?.groupID, "g")
        XCTAssertEqual(item?.audio?.url, "https://cdn.example/a.mp3")
        XCTAssertEqual(item?.audio?.byteCount, 1234)
        XCTAssertEqual(item?.attachments.count, 1)
        XCTAssertEqual(item?.attachments.first?.label, "Diagram")
        XCTAssertEqual(item?.attachments.first?.kind, .image)
        XCTAssertEqual(item?.body, "The spoken body.")
    }

    func testParsesSingleChoiceQuestion() {
        let event = row(
            id: "item1",
            tags: [
                ["tts29", "item", "1"],
                ["title", "Q"],
                ["question", "q1", "single", "Pick one"],
                ["label", "q1", "Choice"],
                ["description", "q1", "Choose carefully"],
                ["option", "q1", "opt_a", "Alpha", "First"],
                ["option", "q1", "opt_b", "Beta"]
            ]
        )
        let item = TTS29ItemParsing.item(from: event)
        let question = item?.questions.first
        XCTAssertEqual(question?.kind, .single)
        XCTAssertEqual(question?.shortTitle, "Choice")
        XCTAssertEqual(question?.description, "Choose carefully")
        XCTAssertEqual(question?.options.map(\.id), ["opt_a", "opt_b"])
        XCTAssertEqual(question?.options.first?.description, "First")
    }

    func testAttachParentIDRequiresExactlyFourElements() {
        let child = row(
            id: "child",
            tags: [["tts29", "item", "1"], ["title", "Child"], ["e", "parent", "", "attach"]]
        )
        XCTAssertEqual(TTS29ItemParsing.item(from: child)?.parentID, "parent")

        let reply = row(
            id: "child2",
            tags: [["tts29", "item", "1"], ["title", "Child"], ["e", "parent", "", "attach", "extra"]]
        )
        XCTAssertNil(TTS29ItemParsing.item(from: reply)?.parentID)
    }

    // MARK: - Catalog

    func testCatalogNestsNarratedChildren() {
        let parent = row(id: "p", createdAt: 1, tags: [["tts29", "item", "1"], ["title", "Parent"]])
        let child = row(
            id: "c",
            createdAt: 2,
            tags: [["tts29", "item", "1"], ["title", "Child"], ["e", "p", "", "attach"]]
        )
        let grandchild = row(
            id: "gc",
            createdAt: 3,
            tags: [["tts29", "item", "1"], ["title", "Grandchild"], ["e", "c", "", "attach"]]
        )
        let catalog = TTS29Catalog(rows: [parent, child, grandchild])
        let assembled = catalog.item(id: "p")
        XCTAssertEqual(assembled?.children.map(\.id), ["c"])
        XCTAssertEqual(assembled?.children.first?.children.map(\.id), ["gc"])
        XCTAssertEqual(assembled?.child(labeled: "Child")?.id, "c")
    }

    func testCatalogDropsOrphanChildren() {
        let child = row(
            id: "c",
            tags: [["tts29", "item", "1"], ["title", "Child"], ["e", "missing", "", "attach"]]
        )
        let catalog = TTS29Catalog(rows: [child])
        XCTAssertNotNil(catalog.item(id: "c"))
        XCTAssertTrue(catalog.item(id: "c")?.children.isEmpty ?? false)
    }

    func testAnswerWinnerIsLatestByAuthor() {
        let item = row(id: "item", tags: [["tts29", "item", "1"], ["title", "Q"]])
        let older = row(
            id: "a1", pubkey: "viewer", createdAt: 10,
            tags: [["tts29", "answer", "1"], ["e", "item", "", "root"], ["answer", "q1", "opt_a"]]
        )
        let newer = row(
            id: "a2", pubkey: "viewer", createdAt: 20,
            tags: [["tts29", "answer", "1"], ["e", "item", "", "root"], ["answer", "q1", "opt_b"]]
        )
        let catalog = TTS29Catalog(rows: [item, older, newer])
        let winner = catalog.answer(itemID: "item", author: "viewer")
        XCTAssertEqual(winner?.values(for: "q1"), ["opt_b"])
    }

    // MARK: - Answer composer

    func testAnswerTagsAreSpecCompliant() {
        let tags = TTS29AnswerComposer.tags(
            itemID: "item1",
            groupID: "g",
            answers: [TTS29Answer(questionID: "q1", values: ["opt_a"])]
        )
        XCTAssertEqual(tags[0], ["tts29", "answer", "1"])
        XCTAssertEqual(tags[1], ["e", "item1", "", "root"])
        XCTAssertEqual(tags[2], ["h", "g"])
        XCTAssertEqual(tags[3], ["answer", "q1", "opt_a"])
    }

    // MARK: - Transcript

    func testTranscriptSegmentsMarkdownBlocks() {
        let transcript = TTS29Transcript("# Heading\n\nA paragraph.\n\n- one\n- two")
        XCTAssertEqual(transcript.blocks.count, 4)
        XCTAssertEqual(transcript.blocks.first?.kind, .heading(1))
    }

    func testFocusAdvancesWithProgress() {
        let transcript = TTS29Transcript("First sentence here. Second sentence here. Third one here.")
        let start = transcript.focus(at: 0)
        let end = transcript.focus(at: 0.99)
        XCTAssertEqual(start?.sentence, 0)
        XCTAssertNotNil(end)
        XCTAssertGreaterThanOrEqual(end!.sentence, start!.sentence)
    }

    func testSpeakableWeightCountsAlphanumericsOnly() {
        XCTAssertEqual(TTS29Transcript.speakableWeight("a, b! c?"), 3)
    }

    // MARK: - Identity

    func testIdentityIsDeterministicPerAuthor() {
        let a = TTS29Identity(agentName: "", author: "deadbeefcafebabe1234")
        let b = TTS29Identity(agentName: "", author: "deadbeefcafebabe1234")
        XCTAssertEqual(a.gradientColors, b.gradientColors)
        XCTAssertEqual(a.initials, b.initials)
        XCTAssertEqual(a.shortAuthor, "deadbe…1234")
    }

    func testIdentityPrefersAgentNameForDisplay() {
        let identity = TTS29Identity(agentName: "Indigo Claude", author: "abc")
        XCTAssertEqual(identity.displayName, "Indigo Claude")
        XCTAssertEqual(identity.initials, "IC")
    }
}
