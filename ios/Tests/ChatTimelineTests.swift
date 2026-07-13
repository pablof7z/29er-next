import XCTest
@testable import TwentyNinerNext

final class ChatTimelineTests: XCTestCase {
    private let day: UInt64 = 86_400
    // 2023-11-14 22:13:20 UTC — a stable, known instant.
    private let base: UInt64 = 1_700_000_000

    private func message(_ id: String, author: String, at createdAt: UInt64) -> RoomMessage {
        RoomMessage(id: id, author: author, createdAt: createdAt, content: "m-\(id)")
    }

    private func membership(_ id: String, at createdAt: UInt64) -> RoomMembershipEvent {
        RoomMembershipEvent(id: id, pubkey: "member", createdAt: createdAt, change: .joined)
    }

    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return calendar
    }

    func testConsecutiveSameAuthorMessagesShareOneHeader() throws {
        let messages = [
            message("1", author: "alice", at: base),
            message("2", author: "alice", at: base + 60),
            message("3", author: "alice", at: base + 120)
        ]

        let entries = ChatTimeline.entries(for: messages, calendar: try calendar())
        let headers = entries.compactMap { entry -> Bool? in
            if case .message(_, let showsHeader) = entry { return showsHeader }
            return nil
        }

        XCTAssertEqual(headers, [true, false, false])
    }

    func testAuthorChangeStartsANewHeader() throws {
        let messages = [
            message("1", author: "alice", at: base),
            message("2", author: "bob", at: base + 30),
            message("3", author: "alice", at: base + 60)
        ]

        let entries = ChatTimeline.entries(for: messages, calendar: try calendar())
        let headers = entries.compactMap { entry -> Bool? in
            if case .message(_, let showsHeader) = entry { return showsHeader }
            return nil
        }

        XCTAssertEqual(headers, [true, true, true])
    }

    func testGapBeyondGroupingWindowBreaksTheGroup() throws {
        let messages = [
            message("1", author: "alice", at: base),
            message("2", author: "alice", at: base + ChatTimeline.groupingWindow + 1)
        ]

        let entries = ChatTimeline.entries(for: messages, calendar: try calendar())
        let headers = entries.compactMap { entry -> Bool? in
            if case .message(_, let showsHeader) = entry { return showsHeader }
            return nil
        }

        XCTAssertEqual(headers, [true, true])
    }

    func testMembershipEventAppearsInOrderAndBreaksMessageGrouping() throws {
        let items: [RoomTimelineItem] = [
            .message(message("1", author: "alice", at: base)),
            .membership(membership("join", at: base + 30)),
            .message(message("2", author: "alice", at: base + 60))
        ]

        let entries = ChatTimeline.entries(for: items, calendar: try calendar())
        let content = entries.filter {
            if case .daySeparator = $0 { return false }
            return true
        }

        XCTAssertEqual(content.map(\.id), ["1", "join", "2"])
        guard case .message(_, showsHeader: true) = content[0],
              case .membership = content[1],
              case .message(_, showsHeader: true) = content[2] else {
            return XCTFail("Membership activity should separate message groups")
        }
    }

    func testDaySeparatorInsertedAtEachDayBoundary() throws {
        let messages = [
            message("1", author: "alice", at: base),
            message("2", author: "alice", at: base + day)
        ]

        let entries = ChatTimeline.entries(for: messages, calendar: try calendar())
        let separatorCount = entries.filter {
            if case .daySeparator = $0 { return true }
            return false
        }.count

        // One at the very top (previousDay starts nil) + one at the crossing.
        XCTAssertEqual(separatorCount, 2)
        if case .daySeparator = entries.first {
            // Expected: the timeline opens with a day boundary.
        } else {
            XCTFail("Timeline should open with a day separator")
        }
    }

    func testSameDayProducesExactlyOneLeadingSeparator() throws {
        let messages = [
            message("1", author: "alice", at: base),
            message("2", author: "bob", at: base + 30)
        ]

        let entries = ChatTimeline.entries(for: messages, calendar: try calendar())
        let separatorCount = entries.filter {
            if case .daySeparator = $0 { return true }
            return false
        }.count

        XCTAssertEqual(separatorCount, 1)
    }
}
