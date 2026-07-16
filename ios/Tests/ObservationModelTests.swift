import NMP
import XCTest
@testable import TwentyNinerNext

private enum FixtureQueryError: LocalizedError {
    case openingFailed

    var errorDescription: String? { "Fixture query opening failed." }
}

private actor QueryOpeningProbe {
    private var openings = 0
    private let target: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(target: Int = 1) {
        self.target = target
    }

    func recordOpening() {
        openings += 1
        guard openings >= target else { return }
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitForOpening() async {
        guard openings < target else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
final class ObservationModelTests: XCTestCase {
    func testRoomChatDemandIsBoundedAndPinnedToSelectedHost() throws {
        let demand = try roomChatDemand(
            host: "wss://nip29.f7z.io",
            groupID: "29er-next"
        )

        XCTAssertEqual(demand.selection.kinds, [9, 9_000, 9_001])
        XCTAssertNil(demand.selection.limit)
        XCTAssertEqual(demand.selection.tags["h"], .literal(["29er-next"]))
        assertPinned(demand, to: "wss://nip29.f7z.io")
        XCTAssertEqual(RoomChatWindow.initialRows, 200)
        XCTAssertEqual(RoomChatWindow.pageSize, 200)
        XCTAssertEqual(RoomChatWindow.maxRows, 1_000)
    }

    func testActivityDemandIsIndependentBoundedAndPinned() throws {
        let demand = try roomActivityDemand(
            host: "wss://nip29.f7z.io",
            groupID: "29er-next"
        )

        XCTAssertEqual(demand.selection.kinds, [30_315])
        XCTAssertEqual(demand.selection.limit, 100)
        XCTAssertEqual(demand.selection.tags["h"], .literal(["29er-next"]))
        assertPinned(demand, to: "wss://nip29.f7z.io")
    }

    func testMembershipDemandIsIndependentBoundedStrictAndPinned() {
        let demand = roomMembershipDemand(
            host: "wss://nip29.f7z.io",
            groupID: "29er-next"
        )

        XCTAssertEqual(demand.selection.kinds, [39_002])
        XCTAssertEqual(demand.selection.limit, 20)
        XCTAssertEqual(demand.selection.tags["d"], .literal(["29er-next"]))
        XCTAssertEqual(demand.cache, .strict)
        assertPinned(demand, to: "wss://nip29.f7z.io")
    }

    func testDirectoryDemandIsBoundedStrictAndPinned() {
        let demand = roomDirectoryDemand(host: "wss://nip29.f7z.io")

        XCTAssertEqual(demand.selection.kinds, [9])
        XCTAssertEqual(demand.selection.limit, 500)
        XCTAssertEqual(demand.cache, .strict)
        assertPinned(demand, to: "wss://nip29.f7z.io")
    }

    func testAdminDemandUsesTheSameSelectedHostBoundary() {
        let demand = roomAdminDemand(
            host: "wss://nip29.f7z.io",
            groupID: "29er-next"
        )

        XCTAssertEqual(demand.selection.kinds, [39_001])
        XCTAssertEqual(demand.selection.limit, 20)
        XCTAssertEqual(demand.selection.tags["d"], .literal(["29er-next"]))
        XCTAssertEqual(demand.cache, .strict)
        assertPinned(demand, to: "wss://nip29.f7z.io")
    }

    private func assertPinned(_ demand: NMPDemand, to host: String) {
        guard case .pinned(let relays) = demand.source else {
            return XCTFail("Expected selected-host pinned authority")
        }
        XCTAssertEqual(relays, [host])
    }

    func testDirectoryReportsQueryOpeningFailure() async throws {
        let engine = try NMPEngine(config: .init())
        let model = RoomDirectoryModel(
            engine: engine,
            hostRelay: "wss://nip29.f7z.io",
            store: try directoryStore(),
            queryOpening: .failing
        )

        await model.observe()

        XCTAssertEqual(model.observationError, "Fixture query opening failed.")
        engine.shutdown()
    }

    func testInboxReportsBothQueryOpeningFailures() async throws {
        let engine = try NMPEngine(config: .init())
        let model = InboxModel(
            engine: engine,
            recipient: "recipient",
            reads: try mentionReads(),
            queryOpening: .failing
        )

        await model.observe()

        XCTAssertEqual(model.mentionError, "Fixture query opening failed.")
        XCTAssertEqual(model.profileError, "Fixture query opening failed.")
        engine.shutdown()
    }

    func testRoomReportsEveryQueryOpeningFailure() async throws {
        let engine = try NMPEngine(config: .init())
        let model = RoomTimelineModel(
            engine: engine,
            groupID: "room",
            hostRelay: "wss://nip29.f7z.io",
            queryOpening: .failing
        )

        await model.observe()

        XCTAssertEqual(model.state, .observing)
        XCTAssertEqual(model.chatError, "Fixture query opening failed.")
        XCTAssertEqual(model.membershipError, "Fixture query opening failed.")
        XCTAssertEqual(model.activityError, "Fixture query opening failed.")
        XCTAssertEqual(model.adminError, "Fixture query opening failed.")
        XCTAssertEqual(model.profileError, "Fixture query opening failed.")
        engine.shutdown()
    }

    func testDirectoryObservationReturnsCleanlyWhenCancelled() async throws {
        let engine = try NMPEngine(config: .init())
        let probe = QueryOpeningProbe()
        let opening = NMPQueryOpening(
            filter: NMPQueryOpening.live.filter,
            demand: { engine, demand, window in
                let query = try await openNMPQuery(
                    engine: engine,
                    demand: demand,
                    window: window
                )
                await probe.recordOpening()
                return query
            }
        )
        let model = RoomDirectoryModel(
            engine: engine,
            hostRelay: "wss://nip29.f7z.io",
            store: try directoryStore(),
            queryOpening: opening
        )
        let observation = Task { await model.observe() }
        await probe.waitForOpening()

        observation.cancel()
        await observation.value

        XCTAssertNil(model.observationError)
        engine.shutdown()
    }

    func testEveryRoomHandleReleasesWhenViewTaskIsCancelled() async throws {
        let engine = try NMPEngine(config: .init())
        let probe = QueryOpeningProbe(target: 5)
        let opening = NMPQueryOpening(
            filter: { engine, filter, window in
                let query = try await openNMPQuery(
                    engine: engine,
                    filter: filter,
                    window: window
                )
                await probe.recordOpening()
                return query
            },
            demand: { engine, demand, window in
                let query = try await openNMPQuery(
                    engine: engine,
                    demand: demand,
                    window: window
                )
                await probe.recordOpening()
                return query
            }
        )
        let model = RoomTimelineModel(
            engine: engine,
            groupID: "room",
            hostRelay: "wss://nip29.f7z.io",
            queryOpening: opening
        )
        let observation = Task { await model.observe() }
        await probe.waitForOpening()

        observation.cancel()
        await observation.value

        XCTAssertNil(model.chatError)
        XCTAssertNil(model.membershipError)
        XCTAssertNil(model.activityError)
        XCTAssertNil(model.adminError)
        XCTAssertNil(model.profileError)
        engine.shutdown()
    }

    private func directoryStore() throws -> DirectoryReadStore {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "directory-observation-tests-\(UUID().uuidString)")
        )
        return DirectoryReadStore(
            defaults: defaults,
            hostRelay: "wss://nip29.f7z.io"
        )
    }

    private func mentionReads() throws -> MentionReads {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "inbox-observation-tests-\(UUID().uuidString)")
        )
        return MentionReads(store: MentionReadStore(defaults: defaults), now: 0)
    }
}

private extension NMPQueryOpening {
    static let failing = NMPQueryOpening(
        filter: { _, _, _ in throw FixtureQueryError.openingFailed },
        demand: { _, _, _ in throw FixtureQueryError.openingFailed }
    )
}
