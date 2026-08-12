import Foundation
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

    func testRememberedGroupsRemainAnObservationRatherThanAConfigurationSource() {
        let snapshot = RememberedGroupSnapshot(
            groups: [choice(host: firstHost, group: "a", name: "Alpha")],
            hosts: [secondHost],
            hasPrivateContent: false
        )

        XCTAssertEqual(snapshot.hosts, [secondHost])
        XCTAssertEqual(snapshot.groups.map(\.host), [firstHost])
    }

    func testHostSelectionPreservesSavedRelayWhileSignedOut() {
        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledHost(
                availableHosts: [bootstrap, firstHost],
                selectedHost: firstHost
            ),
            firstHost
        )
        XCTAssertNil(
            HostGroupSelectionPolicy.reconciledGroup(
                activePubkey: nil,
                snapshot: rememberedSnapshot(),
                selectedGroup: GroupCoordinate(hostRelay: firstHost, localID: "a")
            )
        )
    }

    func testHostSelectionChoosesFirstConfiguredRelayWhenSelectionIsStale() {
        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledHost(
                availableHosts: [bootstrap, firstHost],
                selectedHost: secondHost
            ),
            bootstrap
        )
        XCTAssertNil(
            HostGroupSelectionPolicy.reconciledHost(
                availableHosts: [],
                selectedHost: bootstrap
            )
        )
    }

    func testSignedInSelectionRetainsOnlyTypedRememberedGroup() {
        let snapshot = rememberedSnapshot()
        let rememberedGroup = snapshot.groups[1].coordinate

        XCTAssertEqual(
            HostGroupSelectionPolicy.reconciledGroup(
                activePubkey: "pubkey",
                snapshot: snapshot,
                selectedGroup: rememberedGroup
            ),
            rememberedGroup
        )
        XCTAssertNil(
            HostGroupSelectionPolicy.reconciledGroup(
                activePubkey: "pubkey",
                snapshot: snapshot,
                selectedGroup: GroupCoordinate(hostRelay: bootstrap, localID: "stale")
            )
        )
    }

    func testFavoriteRelayChoicesCombineLocalConfigurationWithRememberedObservations() {
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
            FavoriteRelayChoice.favorites(
                defaultRelay: bootstrap,
                savedRelays: [firstHost],
                remembered: snapshot
            ),
            [
                FavoriteRelayChoice(url: bootstrap, source: .default, roomCount: 0),
                FavoriteRelayChoice(url: firstHost, source: .saved, roomCount: 2),
                FavoriteRelayChoice(url: secondHost, source: .remembered, roomCount: 1)
            ]
        )
    }

    func testSavedRelayStorePersistsOnlyLocalConfiguration() {
        let suite = "FavoriteRelayStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FavoriteRelayStore(defaults: defaults, key: "relays")

        store.save([firstHost, secondHost, firstHost, ""])

        XCTAssertEqual(store.load(), [firstHost, secondHost])
    }

    func testRelayValidationUsesNMPScopeBoundary() throws {
        XCTAssertEqual(
            try FavoriteRelayConfiguration.validatedRelay("  \(firstHost)  "),
            firstHost
        )
        XCTAssertThrowsError(try FavoriteRelayConfiguration.validatedRelay("https://relay.example")) {
            XCTAssertEqual($0 as? FavoriteRelayConfigurationError, .invalidRelay)
        }
    }

    func testAppendingAndRemovingRelaysAreLocalOnly() {
        XCTAssertEqual(
            FavoriteRelayConfiguration.appending(firstHost, to: [firstHost]),
            [firstHost]
        )
        XCTAssertEqual(
            FavoriteRelayConfiguration.appending(secondHost, to: [firstHost]),
            [firstHost, secondHost]
        )
        XCTAssertEqual(
            FavoriteRelayConfiguration.removing(firstHost, from: [firstHost, secondHost]),
            [secondHost]
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
