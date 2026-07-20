import NMP
import XCTest
@testable import TwentyNinerNext

final class TTS29ParsingTests: XCTestCase {
    private let groupID = "group"

    private func row(
        id: String,
        pubkey: String = "author",
        createdAt: UInt64 = 100,
        kind: UInt16 = 9,
        tags: [[String]],
        content: String = "Spoken body."
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
        let event = row(
            id: "1",
            tags: [
                ["tts29", "item", "1"],
                ["h", groupID],
                ["audio", "https://cdn.example/a.mp3", hex("a"), "audio/mpeg", "1"]
            ],
            content: "Body"
        )
        XCTAssertNil(TTS29ItemParsing.item(from: event))
    }

    func testParsesTitleAudioAttachmentsAndAgent() {
        let event = row(
            id: "item1",
            tags: itemTags(title: "Daemon proposal", extra: [
                ["summary", "A short summary"],
                ["agent", "Indigo"],
                ["attachment", "https://cdn.example/diagram.png", hex("b"), "image/png", "999", "Diagram"]
            ]),
            content: "The spoken body."
        )
        let item = try? XCTUnwrap(TTS29ItemParsing.item(from: event))
        XCTAssertEqual(item?.title, "Daemon proposal")
        XCTAssertEqual(item?.summary, "A short summary")
        XCTAssertEqual(item?.agentName, "Indigo")
        XCTAssertEqual(item?.groupID, groupID)
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
            tags: itemTags(title: "Q", extra: [
                ["question", "q1", "single", "Pick one"],
                ["label", "q1", "Choice"],
                ["description", "q1", "Choose carefully"],
                ["option", "q1", "opt_a", "Alpha", "First"],
                ["option", "q1", "opt_b", "Beta"]
            ])
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
        let parentID = hex("1")
        let child = row(
            id: "child",
            tags: itemTags(title: "Child", extra: [["e", parentID, "", "attach"]])
        )
        XCTAssertEqual(TTS29ItemParsing.item(from: child)?.parentID, parentID)

        let reply = row(
            id: "child2",
            tags: itemTags(
                title: "Child",
                extra: [["e", parentID, "", "attach", "extra"]]
            )
        )
        XCTAssertNil(TTS29ItemParsing.item(from: reply))
    }

    func testContractBoundsArtifactsAndRejectsDuplicateSingularTags() {
        let twelve = (0..<12).map { index in
            [
                "attachment", "https://cdn.example/\(index).bin", hex("b"),
                "application/octet-stream", "1", "File \(index)"
            ]
        }
        XCTAssertEqual(
            TTS29ItemParsing.item(
                from: row(id: "bounded", tags: itemTags(title: "Bounded", extra: twelve))
            )?.attachments.count,
            12
        )
        XCTAssertNil(
            TTS29ItemParsing.item(
                from: row(
                    id: "overflow",
                    tags: itemTags(title: "Overflow", extra: twelve + [twelve[0]])
                )
            )
        )
        XCTAssertNil(
            TTS29ItemParsing.item(
                from: row(
                    id: "duplicate-title",
                    tags: itemTags(title: "One", extra: [["title", "Two"]])
                )
            )
        )
        XCTAssertNil(
            TTS29ItemParsing.item(
                from: row(
                    id: "http-audio",
                    tags: itemTags(title: "Bad").map {
                        $0.first == "audio"
                            ? ["audio", "http://cdn.example/a.mp3", hex("a"), "audio/mpeg", "1"]
                            : $0
                    }
                )
            )
        )
    }

    // MARK: - Catalog

    func testCatalogNestsNarratedChildren() {
        let parentID = hex("1")
        let childID = hex("2")
        let grandchildID = hex("3")
        let parent = row(id: parentID, createdAt: 1, tags: itemTags(title: "Parent"))
        let child = row(
            id: childID,
            createdAt: 2,
            tags: itemTags(title: "Child", extra: [["e", parentID, "", "attach"]])
        )
        let grandchild = row(
            id: grandchildID,
            createdAt: 3,
            tags: itemTags(title: "Grandchild", extra: [["e", childID, "", "attach"]])
        )
        let catalog = TTS29Catalog(rows: [parent, child, grandchild])
        let assembled = catalog.item(id: parentID)
        XCTAssertEqual(assembled?.children.map(\.id), [childID])
        XCTAssertEqual(assembled?.children.first?.children.map(\.id), [grandchildID])
        XCTAssertEqual(assembled?.child(labeled: "Child")?.id, childID)
        XCTAssertNil(catalog.item(id: childID), "narrated children are not top-level cards")
        XCTAssertTrue(catalog.isHiddenMessage(id: childID))
    }

    func testCatalogDropsOrphanChildren() {
        let missingID = hex("1")
        let childID = hex("2")
        let child = row(
            id: childID,
            tags: itemTags(title: "Child", extra: [["e", missingID, "", "attach"]])
        )
        let catalog = TTS29Catalog(rows: [child])
        XCTAssertNil(catalog.item(id: childID))
        XCTAssertTrue(catalog.isHiddenMessage(id: childID))
    }

    func testCatalogBoundsDepthAndDropsCycles() {
        let ids = ["1", "2", "3", "4", "5", "6"].map(hex)
        let root = row(id: ids[0], createdAt: 1, tags: itemTags(title: "Root"))
        let branch = (1...4).map { index in
            row(
                id: ids[index],
                createdAt: UInt64(index + 1),
                tags: itemTags(
                    title: "Level \(index)",
                    extra: [["e", ids[index - 1], "", "attach"]]
                )
            )
        }
        let cycleA = row(
            id: ids[4],
            tags: itemTags(title: "Cycle A", extra: [["e", ids[5], "", "attach"]])
        )
        let cycleB = row(
            id: ids[5],
            tags: itemTags(title: "Cycle B", extra: [["e", ids[4], "", "attach"]])
        )

        let catalog = TTS29Catalog(rows: [root] + branch + [cycleA, cycleB])
        let levelThree = catalog.item(id: ids[0])?
            .children.first?.children.first?.children.first
        XCTAssertEqual(levelThree?.id, ids[3])
        XCTAssertTrue(levelThree?.children.isEmpty == true)
        XCTAssertNil(catalog.item(id: ids[4]))
        XCTAssertNil(catalog.item(id: ids[5]))
        XCTAssertTrue(catalog.isHiddenMessage(id: ids[4]))
        XCTAssertTrue(catalog.isHiddenMessage(id: ids[5]))
    }

    func testAnswerWinnerIsLatestByAuthor() {
        let itemID = hex("1")
        let questionTags = [
            ["question", "q1", "single", "Pick one"],
            ["option", "q1", "opt_a", "Alpha"],
            ["option", "q1", "opt_b", "Beta"]
        ]
        let item = row(id: itemID, tags: itemTags(title: "Q", extra: questionTags))
        let older = row(
            id: "a1", pubkey: "viewer", createdAt: 10,
            tags: answerTags(itemID: itemID, value: "opt_a")
        )
        let newer = row(
            id: "a2", pubkey: "viewer", createdAt: 20,
            tags: answerTags(itemID: itemID, value: "opt_b")
        )
        let invalid = row(
            id: "a3", pubkey: "viewer", createdAt: 30,
            tags: answerTags(itemID: itemID, value: "unknown")
        )
        let catalog = TTS29Catalog(rows: [item, older, newer, invalid])
        let winner = catalog.answer(itemID: itemID, author: "viewer")
        XCTAssertEqual(winner?.values(for: "q1"), ["opt_b"])
        XCTAssertTrue(catalog.isHiddenMessage(id: newer.id))
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

    private func itemTags(title: String, extra: [[String]] = []) -> [[String]] {
        [
            ["tts29", "item", "1"],
            ["h", groupID],
            ["title", title],
            ["audio", "https://cdn.example/a.mp3", hex("a"), "audio/mpeg", "1234"]
        ] + extra
    }

    private func answerTags(itemID: String, value: String) -> [[String]] {
        [
            ["tts29", "answer", "1"],
            ["h", groupID],
            ["e", itemID, "", "root"],
            ["answer", "q1", value]
        ]
    }

    private func hex(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}
