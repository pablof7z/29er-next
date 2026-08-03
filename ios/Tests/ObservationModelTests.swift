import NMP
import NMPContent
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
    func testRoomChatQueryIsBoundedAndScopedToTheGroupAtTheSelectedHost() throws {
        let branch = try onlyBranch(
            of: roomChatQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")
        )

        XCTAssertEqual(branch.selection.kinds, [9, 9_000, 9_001, 9_021, 9_022])
        XCTAssertEqual(branch.selection.limit, 200)
        XCTAssertEqual(branch.selection.tags["h"], .literal(["29er-next"]))
        XCTAssertEqual(branch.cache, .strict)
        assertPinned(branch, to: "wss://nip29.f7z.io")
    }

    /// The room timeline reads BOTH moderation (9000/9001) and self-service
    /// (9021/9022) membership kinds. It used to read only the moderation pair
    /// and render it as if it were the self-service pair.
    func testRoomChatQueryReadsBothMembershipVocabularies() throws {
        let branch = try onlyBranch(
            of: roomChatQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")
        )
        let kinds = Set(try XCTUnwrap(branch.selection.kinds))

        XCTAssertTrue(kinds.isSuperset(of: [9_000, 9_001]), "moderation kinds")
        XCTAssertTrue(kinds.isSuperset(of: [9_021, 9_022]), "self-service kinds")
    }

    func testActivityQueryIsIndependentBoundedAndScoped() throws {
        let branch = try onlyBranch(
            of: roomActivityQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")
        )

        XCTAssertEqual(branch.selection.kinds, [30_315])
        XCTAssertEqual(branch.selection.limit, 100)
        XCTAssertEqual(branch.selection.tags["h"], .literal(["29er-next"]))
        assertPinned(branch, to: "wss://nip29.f7z.io")
    }

    func testReactionQueryIsIndependentBoundedAndScoped() throws {
        let branch = try onlyBranch(
            of: roomReactionsQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")
        )

        XCTAssertEqual(branch.selection.kinds, [7])
        XCTAssertEqual(branch.selection.limit, 1_000)
        XCTAssertEqual(branch.selection.tags["h"], .literal(["29er-next"]))
        assertPinned(branch, to: "wss://nip29.f7z.io")
    }

    /// A single-host scope yields exactly one branch, and `branches[i]` names
    /// the branch `evidence[i]` reports on -- so a one-branch declaration is
    /// what makes this app's single-entry evidence reading correct.
    func testGroupReadDeclaresOneBranchPerHost() throws {
        let query = try roomChatQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")

        XCTAssertEqual(query.branches.count, 1)
        XCTAssertNil(query.aggregateResultLimit)
    }

    /// The group id is the sole semantic source of the `#h` row, so an
    /// app-supplied one is refused at declaration time rather than silently
    /// merged. Refusals happen where you declare, not where you watch.
    func testGroupReadRefusesACallerSuppliedContextConstraint() throws {
        let group = try roomGroup(host: "wss://nip29.f7z.io", groupID: "29er-next")

        XCTAssertThrowsError(
            try group.read(NMPFilter(kinds: [9], tags: ["h": .literal(["29er-next"])]))
        )
    }

    func testMembershipQueryIsIndependentBoundedStrictAndPinned() throws {
        let branch = try onlyBranch(
            of: roomMembershipQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")
        )

        XCTAssertEqual(branch.selection.kinds, [39_002])
        XCTAssertEqual(branch.selection.limit, 20)
        XCTAssertEqual(branch.selection.tags["d"], .literal(["29er-next"]))
        XCTAssertEqual(branch.cache, .strict)
        assertPinned(branch, to: "wss://nip29.f7z.io")
    }

    func testDirectoryQueryIsBoundedStrictAndPinned() throws {
        let branch = try onlyBranch(of: roomDirectoryQuery(host: "wss://nip29.f7z.io"))

        XCTAssertEqual(branch.selection.kinds, [9])
        XCTAssertEqual(branch.selection.limit, 500)
        XCTAssertEqual(branch.cache, .strict)
        assertPinned(branch, to: "wss://nip29.f7z.io")
    }

    func testAdminQueryUsesTheSameSelectedHostBoundary() throws {
        let branch = try onlyBranch(
            of: roomAdminQuery(host: "wss://nip29.f7z.io", groupID: "29er-next")
        )

        XCTAssertEqual(branch.selection.kinds, [39_001])
        XCTAssertEqual(branch.selection.limit, 20)
        XCTAssertEqual(branch.selection.tags["d"], .literal(["29er-next"]))
        XCTAssertEqual(branch.cache, .strict)
        assertPinned(branch, to: "wss://nip29.f7z.io")
    }

    func testChannelPreviewProfileDemandIgnoresAuthoredRelayHints() throws {
        let demand = try channelPreviewReferenceDemand(
            for: .profile(
                pubkey: "profile-author",
                relayHints: ["ws://127.0.0.1:7777", "wss://untrusted.example"]
            )
        )

        XCTAssertEqual(demand.selection.kinds, [0])
        XCTAssertEqual(demand.selection.authors, .literal(["profile-author"]))
        XCTAssertEqual(demand.selection.limit, 1)
        XCTAssertEqual(demand.source, .authorOutboxes)
    }

    func testChannelPreviewEventDemandUsesOnlyTheAddressedID() throws {
        let demand = try channelPreviewReferenceDemand(
            for: .event(
                id: "event-id",
                authorHint: "misleading-author",
                kindHint: 30_023,
                relayHints: ["wss://untrusted.example"]
            )
        )

        XCTAssertEqual(demand.selection.ids, .literal(["event-id"]))
        XCTAssertNil(demand.selection.kinds)
        XCTAssertNil(demand.selection.authors)
        XCTAssertEqual(demand.selection.limit, 1)
        XCTAssertEqual(demand.source, .public)
    }

    private func onlyBranch(of query: NMPLiveQuery) throws -> NMPDemand {
        XCTAssertEqual(query.branches.count, 1, "a single-host scope is one branch")
        return try XCTUnwrap(query.branches.first)
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
            query: { engine, liveQuery in
                let query = try await openNMPQuery(engine: engine, query: liveQuery)
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
            filter: { engine, filter in
                let query = try await openNMPQuery(engine: engine, filter: filter)
                await probe.recordOpening()
                return query
            },
            query: { engine, liveQuery in
                let query = try await openNMPQuery(engine: engine, query: liveQuery)
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
        filter: { _, _ in throw FixtureQueryError.openingFailed },
        query: { _, _ in throw FixtureQueryError.openingFailed }
    )
}
