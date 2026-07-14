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
        let store = DirectoryReadStore(defaults: defaults, hostRelay: "wss://one.example.com")
        store.save(["general": 1_000, "random": 2_000])

        XCTAssertEqual(store.load(), ["general": 1_000, "random": 2_000])
    }

    func testReadBaselinesAreNamespacedBySelectedHost() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "directory-host-tests-\(UUID().uuidString)")
        )
        let first = DirectoryReadStore(defaults: defaults, hostRelay: "wss://one.example.com")
        let second = DirectoryReadStore(defaults: defaults, hostRelay: "wss://two.example.com")

        first.save(["general": 1_000])
        second.save(["general": 2_000])

        XCTAssertEqual(first.load(), ["general": 1_000])
        XCTAssertEqual(second.load(), ["general": 2_000])
    }

    func testBaselineHistoryKeepsNewestBoundedRooms() {
        var baselines = Dictionary(
            uniqueKeysWithValues: (0...RoomDirectoryProjection.maximumBaselines).map {
                ("room-\($0)", UInt64($0))
            }
        )
        baselines["same-time-a"] = 2_000
        baselines["same-time-b"] = 2_000

        let bounded = RoomDirectoryProjection.prunedBaselines(baselines)

        XCTAssertEqual(bounded.count, RoomDirectoryProjection.maximumBaselines)
        XCTAssertNil(bounded["room-0"])
        XCTAssertEqual(bounded["same-time-a"], 2_000)
        XCTAssertEqual(bounded["same-time-b"], 2_000)
    }

    func testSnapshotPrunesPersistedBaselineHistory() {
        let baselines = Dictionary(
            uniqueKeysWithValues: (0...RoomDirectoryProjection.maximumBaselines).map {
                ("room-\($0)", UInt64($0))
            }
        )
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: [scoped("fresh", group: "fresh-room", at: 2_000)],
            baselines: baselines,
            now: 2_000
        )

        XCTAssertEqual(snapshot.baselines.count, RoomDirectoryProjection.maximumBaselines)
        XCTAssertEqual(snapshot.baselines["fresh-room"], 2_000)
    }

    private func scoped(_ id: String, group: String, at createdAt: UInt64) -> ScopedRoomMessage {
        ScopedRoomMessage(groupID: group, message: message(id, at: createdAt))
    }

    private func message(_ id: String, at createdAt: UInt64) -> RoomMessage {
        RoomMessage(id: id, author: "author", createdAt: createdAt, content: id)
    }
}
