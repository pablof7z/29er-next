import NMP
import XCTest
@testable import TwentyNinerNext

final class NIP29ViewProjectionTests: XCTestCase {
    func testShortPubkeyFormattingIsConsistent() {
        XCTAssertEqual(PubkeyDisplay.shortHex("short"), "short")
        XCTAssertEqual(
            PubkeyDisplay.shortHex("0123456789abcdef0123456789abcdef"),
            "01234567…89abcdef"
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

    // These four replace `testKind9000BecomesJoinedMembershipEvent` and
    // `testKind9001BecomesLeftMembershipEvent`, which asserted the bug: they
    // pinned kind:9000 to `.joined` and kind:9001 to `.left`, so the timeline
    // rendered a moderator's removal as "left the room". 9000/9001 are
    // put-user and remove-user; 9021/9022 are join and leave.
    func testKind9000IsAModeratorAddingSomebody() throws {
        let event = try XCTUnwrap(
            NIP29ViewProjection.membershipEvent(
                eventID: "added-1",
                author: "moderator-pubkey",
                createdAt: 1_700_000_000,
                kind: 9_000,
                tags: [["h", "29er-next"], ["p", "member-pubkey"]]
            )
        )

        XCTAssertEqual(event.change, .added)
        XCTAssertEqual(event.pubkey, "member-pubkey", "the subject is the p tag, not the author")
    }

    func testKind9001IsAModeratorRemovingSomebodyNotThatPersonLeaving() throws {
        let event = try XCTUnwrap(
            NIP29ViewProjection.membershipEvent(
                eventID: "removed-1",
                author: "moderator-pubkey",
                createdAt: 1_700_000_100,
                kind: 9_001,
                tags: [["p", "member-pubkey"]]
            )
        )

        XCTAssertEqual(event.change, .removed)
        XCTAssertNotEqual(event.change, .left)
        XCTAssertEqual(event.pubkey, "member-pubkey")
    }

    func testKind9021IsSelfJoinAndNamesItsOwnAuthor() throws {
        let event = try XCTUnwrap(
            NIP29ViewProjection.membershipEvent(
                eventID: "joined-1",
                author: "joiner-pubkey",
                createdAt: 1_700_000_200,
                kind: 9_021,
                tags: []
            )
        )

        XCTAssertEqual(event.change, .joined)
        XCTAssertEqual(event.pubkey, "joiner-pubkey", "9021 carries no p tag")
    }

    func testKind9022IsSelfLeaveAndNamesItsOwnAuthor() throws {
        let event = try XCTUnwrap(
            NIP29ViewProjection.membershipEvent(
                eventID: "left-1",
                author: "leaver-pubkey",
                createdAt: 1_700_000_300,
                kind: 9_022,
                tags: []
            )
        )

        XCTAssertEqual(event.change, .left)
        XCTAssertEqual(event.pubkey, "leaver-pubkey")
    }

    func testModerationEventRequiresNonemptyPTag() {
        XCTAssertNil(
            NIP29ViewProjection.membershipEvent(
                eventID: "malformed",
                author: "moderator-pubkey",
                createdAt: 1_700_000_000,
                kind: 9_000,
                tags: [["p", ""], ["h", "29er-next"]]
            )
        )
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
                    ["state", "working"],
                    ["host", "laptop"],
                    ["slug", "codex-slate-falcon-434"],
                    ["rel-cwd", "Work/29er-next"],
                    ["h", "nostr-multi-platform"],
                    ["expiration", "1700000090"]
                ],
                content: "wiring selected-room activity"
            )
        )

        XCTAssertEqual(activity.id, "0123456789abcdef0123456789abcdef:session-7")
        XCTAssertEqual(activity.authorLabel, "codex-slate-falcon-434")
        XCTAssertEqual(activity.title, "Rebuild 29er")
        XCTAssertEqual(activity.activityLabel, "wiring selected-room activity")
        XCTAssertTrue(activity.isBusy)
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
                    ["state", "idle"]
                ],
                content: ""
            )
        )
    }

    func testPeopleJoinMembershipAndActivityByPubkey() throws {
        let activity = try XCTUnwrap(makeActivity(pubkey: "member-a", createdAt: 200))

        let people = NIP29ViewProjection.people(
            memberPubkeys: ["member-a"],
            activities: [activity]
        )

        XCTAssertEqual(people.members.count, 1)
        XCTAssertEqual(people.members.first?.pubkey, "member-a")
        XCTAssertEqual(people.members.first?.activity?.eventID, "status-200")
        XCTAssertEqual(people.activity(for: "member-a")?.eventID, "status-200")
        XCTAssertTrue(people.activeHere.isEmpty)
    }

    func testStatusOnlyPubkeyIsActiveHereNotMember() throws {
        let activity = try XCTUnwrap(makeActivity(pubkey: "session-pubkey", createdAt: 200))

        let people = NIP29ViewProjection.people(memberPubkeys: [], activities: [activity])

        XCTAssertTrue(people.members.isEmpty)
        XCTAssertEqual(people.activeHere.map(\.pubkey), ["session-pubkey"])
    }

    func testPeopleStayFlatWithOneLatestActivityPerPubkey() throws {
        let older = try XCTUnwrap(makeActivity(pubkey: "session-pubkey", createdAt: 100))
        let newer = try XCTUnwrap(makeActivity(pubkey: "session-pubkey", createdAt: 200))

        let people = NIP29ViewProjection.people(memberPubkeys: [], activities: [older, newer])

        XCTAssertEqual(people.activeHere.count, 1)
        XCTAssertEqual(people.activeHere.first?.activity?.eventID, "status-200")
        XCTAssertEqual(people.activity(for: "session-pubkey")?.eventID, "status-200")
        XCTAssertNil(people.activity(for: "someone-else"))
    }

    private func makeActivity(pubkey: String, createdAt: UInt64) -> AgentActivity? {
        NIP29ViewProjection.activity(
            eventID: "status-\(createdAt)",
            pubkey: pubkey,
            createdAt: createdAt,
            kind: 30_315,
            tags: [
                ["d", "session-\(createdAt)"],
                ["state", "working"],
                ["expiration", "\(createdAt + 90)"]
            ],
            content: "working"
        )
    }
}
