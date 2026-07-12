import NMP
import XCTest
@testable import TwentyNinerNext

private enum FixtureQueryError: LocalizedError {
    case openingFailed

    var errorDescription: String? { "Fixture query opening failed." }
}

private actor QueryOpeningProbe {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordOpening() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitForOpening() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
final class ObservationModelTests: XCTestCase {
    func testDirectoryReportsQueryOpeningFailure() async throws {
        let engine = try NMPEngine(config: .init())
        let model = RoomDirectoryModel(
            engine: engine,
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
        XCTAssertEqual(model.contentError, "Fixture query opening failed.")
        XCTAssertEqual(model.membershipError, "Fixture query opening failed.")
        XCTAssertEqual(model.adminError, "Fixture query opening failed.")
        XCTAssertEqual(model.profileError, "Fixture query opening failed.")
        engine.shutdown()
    }

    func testDirectoryObservationReturnsCleanlyWhenCancelled() async throws {
        let engine = try NMPEngine(config: .init())
        let probe = QueryOpeningProbe()
        let opening = NMPQueryOpening(
            filter: { engine, filter in
                let query = try await openNMPQuery(engine: engine, filter: filter)
                await probe.recordOpening()
                return query
            },
            demand: NMPQueryOpening.live.demand
        )
        let model = RoomDirectoryModel(
            engine: engine,
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

    private func directoryStore() throws -> DirectoryReadStore {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "directory-observation-tests-\(UUID().uuidString)")
        )
        return DirectoryReadStore(defaults: defaults)
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
        filter: { _, _ in throw FixtureQueryError.openingFailed },
        demand: { _, _ in throw FixtureQueryError.openingFailed }
    )
}
