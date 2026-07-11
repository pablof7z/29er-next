import XCTest
@testable import TwentyNinerNext

final class NIP29ViewProjectionTests: XCTestCase {
    func testGroupProjectionUsesNIP29MetadataTags() throws {
        let group = try XCTUnwrap(
            NIP29ViewProjection.group(
                eventID: "event-1",
                kind: 39_000,
                tags: [
                    ["d", "general"],
                    ["name", "General"],
                    ["about", "The main room"],
                    ["picture", "https://example.com/room.png"],
                    ["public"],
                    ["open"],
                ]
            )
        )

        XCTAssertEqual(group.id, "general")
        XCTAssertEqual(group.name, "General")
        XCTAssertEqual(group.about, "The main room")
        XCTAssertEqual(group.pictureURL?.absoluteString, "https://example.com/room.png")
        XCTAssertTrue(group.isPublic)
        XCTAssertTrue(group.isOpen)
    }

    func testGroupProjectionFallsBackToIdentifier() throws {
        let group = try XCTUnwrap(
            NIP29ViewProjection.group(
                eventID: "event-2",
                kind: 39_000,
                tags: [["d", "ops"]]
            )
        )

        XCTAssertEqual(group.name, "ops")
        XCTAssertEqual(group.initials, "O")
    }

    func testNonMetadataEventIsNotAGroup() {
        XCTAssertNil(
            NIP29ViewProjection.group(
                eventID: "event-3",
                kind: 9,
                tags: [["d", "general"]]
            )
        )
    }

    func testKindNineBecomesRoomMessage() throws {
        let message = try XCTUnwrap(
            NIP29ViewProjection.message(
                eventID: "message-1",
                pubkey: "0123456789abcdef0123456789abcdef",
                createdAt: 1_700_000_000,
                kind: 9,
                content: "hello"
            )
        )

        XCTAssertEqual(message.content, "hello")
        XCTAssertEqual(message.authorLabel, "01234567…89abcdef")
    }

    func testKind30315BecomesLiveAgentActivity() throws {
        let activity = try XCTUnwrap(
            NIP29ViewProjection.activity(
                eventID: "status-event",
                pubkey: "0123456789abcdef0123456789abcdef",
                createdAt: 1_700_000_000,
                kind: 30_315,
                tags: [
                    ["d", "session-7"],
                    ["title", "Rebuild 29er"],
                    ["status", "busy"],
                    ["host", "laptop"],
                    ["slug", "codex-slate-falcon-434"],
                    ["rel-cwd", "Work/29er-next"],
                    ["h", "nostr-multi-platform"],
                    ["expiration", "1700000090"],
                ],
                content: "wiring selected-room activity"
            )
        )

        XCTAssertEqual(activity.id, "0123456789abcdef0123456789abcdef:session-7")
        XCTAssertEqual(activity.authorLabel, "codex-slate-falcon-434")
        XCTAssertEqual(activity.title, "Rebuild 29er")
        XCTAssertEqual(activity.activityLabel, "wiring selected-room activity")
        XCTAssertTrue(activity.isBusy)
        XCTAssertEqual(activity.expiresAt, 1_700_000_090)
    }

    func testKind30315WithoutLivenessBoundaryIsNotLiveActivity() {
        XCTAssertNil(
            NIP29ViewProjection.activity(
                eventID: "status-event",
                pubkey: "pubkey",
                createdAt: 1_700_000_000,
                kind: 30_315,
                tags: [
                    ["d", "session-7"],
                    ["status", "idle"],
                ],
                content: ""
            )
        )
    }
}
