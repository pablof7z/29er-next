import XCTest
@testable import TwentyNinerNext

final class ObservationPresentationTests: XCTestCase {
    func testChannelListShowsRoomActivityFailure() {
        XCTAssertEqual(
            ChannelListPresentation.activityNotice(error: "offline"),
            NoticeContent(
                symbol: "exclamationmark.triangle.fill",
                title: "Room activity unavailable",
                message: "offline"
            )
        )
        XCTAssertNil(ChannelListPresentation.activityNotice(error: nil))
    }

    func testEmptyInboxDistinguishesUnavailableFromZero() {
        XCTAssertEqual(
            InboxPresentation.make(unreadCount: 0, mentionError: "offline", profileError: nil),
            InboxPresentation(content: .unavailable("offline"), notice: nil)
        )
        XCTAssertEqual(
            InboxPresentation.make(unreadCount: 0, mentionError: nil, profileError: "ignored"),
            InboxPresentation(content: .zero, notice: nil)
        )
    }

    func testPopulatedInboxPrioritizesMentionFailureNotice() {
        let presentation = InboxPresentation.make(
            unreadCount: 1,
            mentionError: "mentions stale",
            profileError: "profiles stale"
        )

        XCTAssertEqual(presentation.content, .mentions)
        XCTAssertEqual(presentation.notice?.title, "Inbox may be out of date")
        XCTAssertEqual(presentation.notice?.message, "mentions stale")
    }

    func testPopulatedInboxFallsBackToProfileFailureNotice() {
        let presentation = InboxPresentation.make(
            unreadCount: 1,
            mentionError: nil,
            profileError: "profiles stale"
        )

        XCTAssertEqual(presentation.content, .mentions)
        XCTAssertEqual(presentation.notice?.title, "Profiles unavailable")
        XCTAssertEqual(presentation.notice?.message, "profiles stale")
        XCTAssertEqual(presentation.notice?.symbol, "exclamationmark.triangle.fill")
    }

    func testChatTimelinePresentationOrder() {
        XCTAssertEqual(
            ChatTimelinePresentation.make(
                messageCount: 0,
                hasReceivedSnapshot: false,
                error: "offline",
                profileError: nil
            ),
            .unavailable("offline")
        )
        XCTAssertEqual(
            ChatTimelinePresentation.make(
                messageCount: 0,
                hasReceivedSnapshot: false,
                error: nil,
                profileError: nil
            ),
            .loading
        )
        XCTAssertEqual(
            ChatTimelinePresentation.make(
                messageCount: 0,
                hasReceivedSnapshot: true,
                error: nil,
                profileError: nil
            ),
            .empty
        )
    }

    func testPopulatedChatShowsProfileFailureNotice() {
        let presentation = ChatTimelinePresentation.make(
            messageCount: 1,
            hasReceivedSnapshot: true,
            error: nil,
            profileError: "profiles stale"
        )

        guard case .messages(let notice) = presentation else {
            return XCTFail("Expected populated timeline presentation")
        }
        XCTAssertEqual(notice?.title, "Profiles unavailable")
        XCTAssertEqual(notice?.message, "profiles stale")
        XCTAssertEqual(notice?.symbol, "exclamationmark.triangle.fill")
    }

    func testRoomPeopleMembershipPresentationOrder() {
        var input = RoomPeoplePresentation.Input()
        input.membershipError = "members stale"
        XCTAssertEqual(
            RoomPeoplePresentation.make(input).membership,
            .unavailable(
                NoticeContent(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Member list unavailable",
                    message: "members stale"
                )
            )
        )

        input.membershipError = nil
        XCTAssertEqual(RoomPeoplePresentation.make(input).membership, .loading)

        input.hasReceivedMembership = true
        guard case .metadataMissing(let notice) = RoomPeoplePresentation.make(input).membership else {
            return XCTFail("Expected missing metadata presentation")
        }
        XCTAssertEqual(notice.title, "Member list unavailable")

        input.hasMembershipMetadata = true
        XCTAssertEqual(RoomPeoplePresentation.make(input).membership, .ready)
    }

    func testRoomPeopleShowsEveryIndependentFailureInStableOrder() {
        var input = RoomPeoplePresentation.Input()
        input.adminError = "admins stale"
        input.profileError = "profiles stale"
        input.activityError = "activity stale"

        let notices = RoomPeoplePresentation.make(input).notices

        XCTAssertEqual(
            notices.map(\.title),
            ["Backend admins unavailable", "Profiles unavailable", "Live status unavailable"]
        )
        XCTAssertEqual(
            notices.map(\.message),
            ["admins stale", "profiles stale", "activity stale"]
        )
        XCTAssertEqual(
            notices.map(\.symbol),
            [
                "person.badge.key",
                "person.crop.circle.badge.exclamationmark",
                "bolt.slash"
            ]
        )
    }

    func testRoomPeopleEmptyStateRequiresBothSnapshotsAndNoMetadata() {
        var input = RoomPeoplePresentation.Input()
        input.hasReceivedMembership = true
        input.hasReceivedActivities = true
        XCTAssertTrue(RoomPeoplePresentation.make(input).showEmptyState)

        input.hasMembershipMetadata = true
        XCTAssertFalse(RoomPeoplePresentation.make(input).showEmptyState)
        input.hasMembershipMetadata = false
        input.activeCount = 1
        XCTAssertFalse(RoomPeoplePresentation.make(input).showEmptyState)
    }
}
