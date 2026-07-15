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

    @MainActor
    func testFavoriteRelayEditorExplainsInvalidRelayAndAtomicConflict() {
        XCTAssertEqual(
            AppModel.favoriteRelayFailureMessage(
                for: .failed(.invalidRelay("not-a-relay"))
            ),
            "Enter a valid WebSocket relay URL, such as wss://relay.example."
        )
        XCTAssertEqual(
            AppModel.favoriteRelayFailureMessage(
                for: .receipt(
                    id: 1,
                    status: .replaceableConflict(expected: "old", actual: "new")
                )
            ),
            "Your relay list changed during this update. Review it and try again."
        )
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
