import Foundation
import NMP
import XCTest
@testable import TwentyNinerNext

final class AppEngineBootstrapTests: XCTestCase {
    private let secretKey = String(repeating: "0", count: 63) + "1"
    private let publicKey =
        "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    func testResourcesPreserveTheCanonicalNMPStore() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let appDirectory = try makeAppDirectory(in: support)
        let store = appDirectory.appendingPathComponent("nmp.redb")
        let oldMarker = appDirectory.appendingPathComponent("nmp-store-epoch")
        try Data("canonical-store".utf8).write(to: store)
        try Data("5\n".utf8).write(to: oldMarker)
        let checkpoint = MemoryAccountCheckpoint()

        let resources = try makeResources(
            support: support,
            accountStore: checkpoint
        )

        XCTAssertEqual(resources.config.storePath, store.path)
        XCTAssertEqual(try Data(contentsOf: store), Data("canonical-store".utf8))
        XCTAssertEqual(try Data(contentsOf: oldMarker), Data("5\n".utf8))
        XCTAssertTrue((resources.accountStore as AnyObject) === checkpoint)
    }

    func testResourcesUseNMPKeychainCheckpointByDefault() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }

        let resources = try makeResources(support: support)

        XCTAssertTrue(resources.accountStore is NMPKeychainAccountStore)
    }

    func testBootstrapDeletesLegacyPlaintextWithoutImportingIt() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let appDirectory = try makeAppDirectory(in: support)
        let legacy = appDirectory.appendingPathComponent("local-account.nsec")
        try Data((String(repeating: "0", count: 63) + "1").utf8).write(to: legacy)
        let checkpoint = MemoryAccountCheckpoint()
        let resources = try makeResources(
            support: support,
            accountStore: checkpoint
        )

        let session = try AppEngineBootstrap.start(resources)
        defer { session.engine.shutdown() }

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertNil(session.activePubkey)
        XCTAssertEqual(checkpoint.loadCount, 1)
        XCTAssertEqual(checkpoint.saveCount, 0)
    }

    func testNMPKeychainCheckpointRestoresAcrossEngineRestart() async throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let checkpoint = NMPKeychainAccountStore(
            service: "io.f7z.29er-next.tests",
            account: UUID().uuidString
        )
        defer { try? checkpoint.clear() }
        let resources = try makeResources(
            support: support,
            accountStore: checkpoint
        )

        let first = try AppEngineBootstrap.start(resources)
        let registration = try await first.engine.addAccount(secretKey: secretKey)
        try first.engine.setActiveAccount(registration.publicKey)
        XCTAssertEqual(try first.engine.activeAccount(), publicKey)
        first.engine.shutdown()

        let restored = try AppEngineBootstrap.start(resources)
        XCTAssertEqual(restored.activePubkey, publicKey)
        try restored.engine.clearPersistedAccount()
        restored.engine.shutdown()

        let signedOut = try AppEngineBootstrap.start(resources)
        XCTAssertNil(signedOut.activePubkey)
        signedOut.engine.shutdown()
    }

    private func makeResources(
        support: URL,
        accountStore: (any NMPLocalAccountCheckpoint)? = nil
    ) throws -> AppEngineResources {
        try AppEngineBootstrap.resources(
            fileManager: .default,
            operatorConfiguration: OperatorConfiguration(
                indexerRelays: [],
                groupRelay: "wss://nip29.f7z.io"
            ),
            applicationSupportURL: support,
            accountStore: accountStore
        )
    }

    private func makeSupportDirectory() throws -> URL {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    private func makeAppDirectory(in support: URL) throws -> URL {
        let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory
    }
}
