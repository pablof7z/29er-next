import XCTest
@testable import TwentyNinerNext

final class RoomDirectoryTests: XCTestCase {
    func testFirstSnapshotSeedsRoomsAtCurrentTime() {
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: [scoped("old", group: "general", at: 900)],
            baselines: [:],
            now: 1_000
        )

        XCTAssertEqual(snapshot.baselines["general"], 1_000)
        XCTAssertEqual(snapshot.entries["general"]?.unread, 0)
    }

    func testLateHistoryDoesNotBecomeUnread() {
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: [
                scoped("old-a", group: "general", at: 800),
                scoped("old-b", group: "general", at: 900)
            ],
            baselines: ["general": 1_000],
            now: 2_000
        )

        XCTAssertEqual(snapshot.entries["general"]?.unread, 0)
    }

    func testMessagesNewerThanBaselineAreUnread() {
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: [
                scoped("old", group: "general", at: 1_000),
                scoped("new-a", group: "general", at: 1_001),
                scoped("new-b", group: "general", at: 1_002),
                scoped("other", group: "random", at: 1_500)
            ],
            baselines: ["general": 1_000, "random": 2_000],
            now: 3_000
        )

        XCTAssertEqual(snapshot.entries["general"]?.unread, 2)
        XCTAssertEqual(snapshot.entries["random"]?.unread, 0)
    }

    func testEqualTimestampUsesEventIDAsLatestTieBreaker() {
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: [
                scoped("event-a", group: "general", at: 1_000),
                scoped("event-b", group: "general", at: 1_000)
            ],
            baselines: ["general": 900],
            now: 2_000
        )

        XCTAssertEqual(snapshot.entries["general"]?.latest?.id, "event-b")
        XCTAssertEqual(snapshot.entries["general"]?.unread, 2)
    }

    func testMarkReadBaselineUsesLatestMessageOrCurrentTime() {
        XCTAssertEqual(
            RoomDirectoryProjection.readBaseline(
                latest: message("latest", at: 1_500),
                now: 2_000
            ),
            1_500
        )
        XCTAssertEqual(RoomDirectoryProjection.readBaseline(latest: nil, now: 2_000), 2_000)
    }

    func testLatestMessageBaselineClearsUnreadCount() throws {
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: [
                scoped("new-a", group: "general", at: 1_001),
                scoped("new-b", group: "general", at: 1_002)
            ],
            baselines: ["general": 1_000],
            now: 2_000
        )
        let latest = try XCTUnwrap(snapshot.latestByGroup["general"])
        let markedRead = RoomDirectoryProjection.entries(
            latestByGroup: snapshot.latestByGroup,
            timesByGroup: snapshot.timesByGroup,
            baselines: [
                "general": RoomDirectoryProjection.readBaseline(latest: latest, now: 2_000)
            ]
        )

        XCTAssertEqual(markedRead["general"]?.unread, 0)
    }

    func testDirectoryReadStorePersistsBaselines() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "directory-tests-\(UUID().uuidString)")
        )
        let store = DirectoryReadStore(defaults: defaults)
        store.save(["general": 1_000, "random": 2_000])

        XCTAssertEqual(store.load(), ["general": 1_000, "random": 2_000])
    }

    private func scoped(_ id: String, group: String, at createdAt: UInt64) -> ScopedRoomMessage {
        ScopedRoomMessage(groupID: group, message: message(id, at: createdAt))
    }

    private func message(_ id: String, at createdAt: UInt64) -> RoomMessage {
        RoomMessage(id: id, author: "author", createdAt: createdAt, content: id)
    }
}
