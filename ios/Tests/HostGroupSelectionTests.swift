import NMP
import XCTest
@testable import TwentyNinerNext

final class HostGroupSelectionTests: XCTestCase {
    private let bootstrap = "wss://bootstrap.example.com"
    private let firstHost = "wss://one.example.com"
    private let secondHost = "wss://two.example.com"

    func testSnapshotPreservesTypedOrderAndDeduplicatesCoordinatesAndHosts() {
        let first = choice(host: firstHost, group: "a", name: "Alpha")
        let duplicate = choice(host: firstHost, group: "a", name: "Duplicate")
        let second = choice(host: secondHost, group: "b", name: nil)

        let snapshot = RememberedGroupSnapshot(
            groups: [first, duplicate, second],
            hosts: [secondHost, firstHost, secondHost],
            hasPrivateContent: true
        )

        XCTAssertEqual(snapshot.groups, [first, second])
        XCTAssertEqual(snapshot.hosts, [secondHost, firstHost])
        XCTAssertTrue(snapshot.hasPrivateContent)
    }

    func testGroupHostsDoNotBecomeRelayFavoritesWithoutAnRTag() {
        let snapshot = RememberedGroupSnapshot(
            groups: [choice(host: firstHost, group: "a", name: "Alpha")],
            hosts: [secondHost],
            hasPrivateContent: false
        )

        XCTAssertEqual(snapshot.hosts, [secondHost])
        XCTAssertEqual(snapshot.groups.map(\.host), [firstHost])
    }

    func testLoggedOutSelectionUsesOnlyOperatorBootstrap() {
        let snapshot = rememberedSnapshot()

        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledHost(
                activePubkey: nil,
                bootstrapHost: bootstrap,
                snapshot: snapshot,
                selectedHost: firstHost
            ),
            bootstrap
        )
        XCTAssertNil(
            HostGroupSelectionPolicy.reconciledGroup(
                activePubkey: nil,
                snapshot: snapshot,
                selectedGroup: snapshot.groups[0].coordinate
            )
        )
    }

    func testSignedInSelectionRetainsOnlyTypedRememberedValues() {
        let snapshot = rememberedSnapshot()
        let rememberedGroup = snapshot.groups[1].coordinate

        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledHost(
                activePubkey: "pubkey",
                bootstrapHost: bootstrap,
                snapshot: snapshot,
                selectedHost: secondHost
            ),
            secondHost
        )
        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledGroup(
                activePubkey: "pubkey",
                snapshot: snapshot,
                selectedGroup: rememberedGroup
            ),
            rememberedGroup
        )
    }

    func testSignedInSelectionDropsStaleGroupAndChoosesFirstTypedHost() {
        let snapshot = rememberedSnapshot()

        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledHost(
                activePubkey: "pubkey",
                bootstrapHost: bootstrap,
                snapshot: snapshot,
                selectedHost: bootstrap
            ),
            firstHost
        )
        XCTAssertNil(
            HostGroupSelectionPolicy.reconciledGroup(
                activePubkey: "pubkey",
                snapshot: snapshot,
                selectedGroup: GroupCoordinate(hostRelay: bootstrap, localID: "stale")
            )
        )
    }

    func testSignedInAccountWithNoPublicRememberedHostsHasNoSelection() {
        XCTAssertNil(
            HostGroupSelectionPolicy.reconciledHost(
                activePubkey: "pubkey",
                bootstrapHost: bootstrap,
                snapshot: .empty,
                selectedHost: bootstrap
            )
        )
    }

    func testFavoriteRelayChoicesPreserveHostOrderAndCountRememberedRooms() {
        let snapshot = RememberedGroupSnapshot(
            groups: [
                choice(host: firstHost, group: "a", name: "Alpha"),
                choice(host: firstHost, group: "b", name: "Beta"),
                choice(host: secondHost, group: "c", name: nil)
            ],
            hosts: [secondHost, firstHost],
            hasPrivateContent: false
        )

        XCTAssertEqual(
            FavoriteRelayChoice.favorites(from: snapshot),
            [
                FavoriteRelayChoice(url: secondHost, roomCount: 1),
                FavoriteRelayChoice(url: firstHost, roomCount: 2)
            ]
        )
    }

    func testBootstrapRelayIsPresentedWithoutPretendingItIsAnAccountFavorite() {
        XCTAssertEqual(
            FavoriteRelayChoice.bootstrap(host: bootstrap),
            [FavoriteRelayChoice(url: bootstrap, roomCount: nil)]
        )
        XCTAssertTrue(FavoriteRelayChoice.bootstrap(host: "").isEmpty)
    }

    func testFavoriteRelayEditorAddsGenericEventWithoutRebuildingExistingList() throws {
        let source = FavoriteRelayListEvent(
            id: "base",
            createdAt: 100,
            tags: [
                ["group", "room", firstHost, "Alpha"],
                ["unknown", "preserve", "verbatim"],
                ["r", firstHost]
            ],
            content: "opaque-private-content"
        )

        let intent = try XCTUnwrap(
            FavoriteRelayListEditor.intent(
                operation: .add(" WSS://TWO.EXAMPLE.COM "),
                activePubkey: "author",
                sourceEvent: source,
                now: 100
            )
        )

        // `WritePayload.unsigned(pubkey:...)` is gone: a payload carries no
        // author at all, and who a write publishes as is `WriteIntent
        // .identity`. `WriteRouting.authorOutbox` is gone too -- which
        // strategy claims kind:10009 is NMP's call, not the app's.
        guard case let .event(kind, tags, content, createdAt) = intent.payload else {
            return XCTFail("Expected a stamped generic write")
        }
        XCTAssertEqual(intent.identity, .explicit(pubkey: "author"))
        XCTAssertEqual(createdAt, 101)
        XCTAssertEqual(kind, 10_009)
        XCTAssertEqual(tags, source.tags + [["r", secondHost]])
        XCTAssertEqual(content, source.content)
        XCTAssertEqual(intent.routing, .auto)
    }

    func testFavoriteRelayEditorRemovesOnlyMatchingRelayTags() throws {
        let source = FavoriteRelayListEvent(
            id: "base",
            createdAt: 100,
            tags: [
                ["r", "WSS://ONE.EXAMPLE.COM"],
                ["group", "room", firstHost],
                ["r", secondHost],
                ["r", "not-a-relay"],
                ["other"]
            ],
            content: "preserved"
        )

        let intent = try XCTUnwrap(
            FavoriteRelayListEditor.intent(
                operation: .remove(firstHost),
                activePubkey: "author",
                sourceEvent: source,
                now: 200
            )
        )

        guard case let .event(kind, tags, content, createdAt) = intent.payload else {
            return XCTFail("Expected a stamped generic write")
        }
        XCTAssertEqual(createdAt, 200)
        XCTAssertEqual(kind, 10_009)
        XCTAssertEqual(
            tags,
            [
                ["group", "room", firstHost],
                ["r", secondHost],
                ["r", "not-a-relay"],
                ["other"]
            ]
        )
        XCTAssertEqual(content, "preserved")
    }

    func testFavoriteRelayEditorTreatsDuplicateAddAndMissingRemoveAsNoOps() throws {
        let source = FavoriteRelayListEvent(
            id: "base",
            createdAt: 100,
            tags: [["r", firstHost]],
            content: ""
        )

        XCTAssertNil(
            try FavoriteRelayListEditor.intent(
                operation: .add("WSS://ONE.EXAMPLE.COM"),
                activePubkey: "author",
                sourceEvent: source,
                now: 200
            )
        )
        XCTAssertNil(
            try FavoriteRelayListEditor.intent(
                operation: .remove(secondHost),
                activePubkey: "author",
                sourceEvent: source,
                now: 200
            )
        )
    }

    func testFavoriteRelayEditorRejectsNonWebSocketRelayAndExhaustedTimestamp() {
        XCTAssertThrowsError(
            try FavoriteRelayListEditor.intent(
                operation: .add("https://relay.example.com"),
                activePubkey: "author",
                sourceEvent: nil,
                now: 200
            )
        ) { error in
            XCTAssertEqual(error as? FavoriteRelayListEditError, .invalidRelay)
        }

        XCTAssertThrowsError(
            try FavoriteRelayListEditor.intent(
                operation: .add(firstHost),
                activePubkey: "author",
                sourceEvent: FavoriteRelayListEvent(
                    id: "base",
                    createdAt: .max,
                    tags: [],
                    content: ""
                ),
                now: 200
            )
        ) { error in
            XCTAssertEqual(error as? FavoriteRelayListEditError, .timestampExhausted)
        }
    }

    /// The app's only tested write-handling path. A stale compare-and-swap is
    /// no longer a throw from `publish`: the write is ACCEPTED, taken into
    /// custody, and refused in the queue -- keeping both event ids, which is
    /// what makes it recoverable without asking the person anything.
    @MainActor
    func testFavoriteRelayEditorExplainsRefusedAndCancelledWrites() async {
        let conflict = await AppModel.favoriteRelayFailure(
            draining: WriteFactSequence([
                .signing(.signed(eventId: "new")),
                .outcome(.refused(.replaceableBaseChanged(expected: "old", actual: "new")))
            ])
        )
        XCTAssertEqual(
            conflict,
            "The relay list changed while this update was in flight. Review it and try again."
        )

        let cancelled = await AppModel.favoriteRelayFailure(
            draining: WriteFactSequence([.outcome(.notSent(.cancelled))])
        )
        XCTAssertEqual(cancelled, "The relay list was not sent -- the write was cancelled.")
    }

    /// `expected`/`actual` survive the boundary intact, which is the whole
    /// reason the refusal is worth more than a string.
    func testStaleReplaceableBaseKeepsBothEventIds() {
        guard case let .outcome(.refused(.replaceableBaseChanged(expected, actual))) =
            WriteFact.outcome(.refused(.replaceableBaseChanged(expected: "old", actual: "new")))
        else {
            return XCTFail("Expected a refused stale-base outcome")
        }
        XCTAssertEqual(expected, "old")
        XCTAssertEqual(actual, "new")
    }

    private func rememberedSnapshot() -> RememberedGroupSnapshot {
        RememberedGroupSnapshot(
            groups: [
                choice(host: firstHost, group: "a", name: "Alpha"),
                choice(host: secondHost, group: "b", name: "Beta")
            ],
            hosts: [firstHost, secondHost],
            hasPrivateContent: false
        )
    }

    private func choice(host: String, group: String, name: String?) -> RememberedGroupChoice {
        RememberedGroupChoice(host: host, groupID: group, name: name)
    }
}
