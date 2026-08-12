import Foundation
import XCTest
@testable import TwentyNinerNext

@MainActor
final class AppModelResetTests: XCTestCase {
    func testAddingRelayPersistsLocallyAndRebuildsNMPWithoutAnAccountWrite() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "AppModelRelayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let relay = "wss://new-relay.example"
        let store = FavoriteRelayStore(defaults: defaults, key: "relays")
        let model = AppModel(
            operatorConfiguration: OperatorConfiguration(
                indexerRelays: [],
                groupRelay: "wss://nip29.f7z.io"
            ),
            applicationSupportURL: support,
            accountStore: MemoryAccountCheckpoint(),
            favoriteRelayStore: store
        )
        defer { model.engine?.shutdown() }
        let previousEngine = try XCTUnwrap(model.engine)

        model.addFavoriteRelay(relay)

        XCTAssertEqual(model.savedRelays, [relay])
        XCTAssertEqual(store.load(), [relay])
        XCTAssertEqual(model.relayHosts, ["wss://nip29.f7z.io", relay])
        XCTAssertEqual(model.selectedHost, relay)
        XCTAssertEqual(model.state, .starting)
        XCTAssertEqual(model.engineGeneration, 1)
        XCTAssertFalse(try XCTUnwrap(model.engine) === previousEngine)
    }

    func testResetReplacesEngineAndPreservesAccountAndUnrelatedAppData() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let checkpoint = MemoryAccountCheckpoint()

        let model = AppModel(
            operatorConfiguration: OperatorConfiguration(
                indexerRelays: [],
                groupRelay: "wss://nip29.f7z.io"
            ),
            applicationSupportURL: support,
            accountStore: checkpoint
        )
        defer { model.engine?.shutdown() }
        let didSignIn = await model.signIn(
            secretKey: String(repeating: "0", count: 63) + "1"
        )
        XCTAssertTrue(didSignIn)
        let activePubkey = try XCTUnwrap(model.activePubkey)

        let originalEngine = try XCTUnwrap(model.engine)
        let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
        let unrelated = appDirectory.appendingPathComponent("presentation-state")
        try Data("keep".utf8).write(to: unrelated)

        XCTAssertTrue(model.resetLocalDatabase())

        let replacementEngine = try XCTUnwrap(model.engine)
        XCTAssertFalse(originalEngine === replacementEngine)
        XCTAssertEqual(model.engineGeneration, 1)
        XCTAssertEqual(model.state, .starting)
        XCTAssertEqual(model.activePubkey, activePubkey)
        XCTAssertEqual(model.selectedHost, "wss://nip29.f7z.io")
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(checkpoint.saveCount, 1)
    }
}
