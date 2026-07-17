import XCTest
@testable import TwentyNinerNext

@MainActor
final class IdentitySessionTests: XCTestCase {
    private let secretOne = String(repeating: "0", count: 63) + "1"
    private let publicOne = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    func testCleanLaunchCreatesAndRestoresGeneratedIdentity() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)

        let didGenerate = await model?.ensureIdentity() ?? false
        XCTAssertTrue(didGenerate)
        let pubkey = try XCTUnwrap(model?.activePubkey)
        let profile = try XCTUnwrap(model?.generatedIdentityProfile)
        XCTAssertEqual(profile.pubkey, pubkey)
        XCTAssertFalse(profile.name.isEmpty)

        model?.profilePublishTask?.cancel()
        model?.engine?.shutdown()
        model = nil

        var restored: AppModel? = makeModel(root: root)
        XCTAssertEqual(restored?.activePubkey, pubkey)
        XCTAssertEqual(restored?.generatedIdentityProfile, profile)

        restored?.engine?.shutdown()
        restored = nil
        try FileManager.default.removeItem(at: root)
    }

    func testImportedIdentityReplacesGeneratedIdentity() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)
        let didGenerate = await model?.ensureIdentity() ?? false
        XCTAssertTrue(didGenerate)
        let generatedPubkey = model?.activePubkey

        model?.profilePublishTask?.cancel()
        model?.engine?.shutdown()
        model = makeModel(root: root)
        XCTAssertEqual(model?.activePubkey, generatedPubkey)

        let didReplace = await model?.signIn(secretKey: secretOne) ?? false
        XCTAssertTrue(didReplace)
        XCTAssertEqual(model?.activePubkey, publicOne)
        XCTAssertNotEqual(model?.activePubkey, generatedPubkey)
        XCTAssertNil(model?.generatedIdentityProfile)
        XCTAssertNil(model?.identityError)

        model?.engine?.shutdown()
        model = nil

        var restored: AppModel? = makeModel(root: root)
        XCTAssertEqual(restored?.activePubkey, publicOne)
        XCTAssertNil(restored?.generatedIdentityProfile)

        restored?.engine?.shutdown()
        restored = nil
        try FileManager.default.removeItem(at: root)
    }

    func testInvalidReplacementPreservesGeneratedIdentity() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)
        let didGenerate = await model?.ensureIdentity() ?? false
        XCTAssertTrue(didGenerate)
        let generatedPubkey = model?.activePubkey
        let generatedProfile = model?.generatedIdentityProfile

        let didReplace = await model?.signIn(secretKey: "not-a-key") ?? true
        XCTAssertFalse(didReplace)
        XCTAssertEqual(model?.activePubkey, generatedPubkey)
        XCTAssertEqual(model?.generatedIdentityProfile, generatedProfile)
        XCTAssertEqual(model?.identityError, "That secret key is not a valid nsec or secret hex key.")
        XCTAssertFalse(model?.isSigningIn ?? true)

        model?.profilePublishTask?.cancel()
        model?.engine?.shutdown()
        model = nil
        try FileManager.default.removeItem(at: root)
    }

    func testGeneratedProfilePersistenceFailureRollsBackAccount() async throws {
        let root = try makeRoot()
        let appDirectory = root.appendingPathComponent("29er-next", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: appDirectory.appendingPathComponent("generated-identity.json"),
            withIntermediateDirectories: true
        )
        var model: AppModel? = makeModel(root: root)

        let didGenerate = await model?.ensureIdentity() ?? true
        XCTAssertFalse(didGenerate)
        XCTAssertNil(model?.activePubkey)
        XCTAssertEqual(model?.identityError, "NMP could not create and save a default identity.")

        model?.engine?.shutdown()
        model = nil
        var restored: AppModel? = makeModel(root: root)
        XCTAssertNil(restored?.activePubkey)

        restored?.engine?.shutdown()
        restored = nil
        try FileManager.default.removeItem(at: root)
    }

    func testDatabaseResetRecoversStartupAndPreservesSavedAccount() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)
        let didSignIn = await model?.signIn(secretKey: secretOne) ?? false
        XCTAssertTrue(didSignIn)
        XCTAssertEqual(model?.activePubkey, publicOne)

        let appDirectory = root.appendingPathComponent("29er-next", isDirectory: true)
        let database = appDirectory.appendingPathComponent("nmp.redb")
        let checkpoint = appDirectory.appendingPathComponent("local-account.nsec")
        let savedAccount = try Data(contentsOf: checkpoint)

        model?.engine?.shutdown()
        model = nil
        try Data("incompatible-store".utf8).write(to: database, options: .atomic)

        var failed: AppModel? = makeModel(root: root)
        guard case .failed = failed?.state else {
            return XCTFail("an invalid persistent store must fail construction")
        }
        XCTAssertNil(failed?.engine)

        XCTAssertTrue(failed?.resetLocalDatabase() ?? false)
        XCTAssertEqual(failed?.state, .starting)
        XCTAssertEqual(failed?.activePubkey, publicOne)
        XCTAssertNotNil(failed?.engine)
        XCTAssertEqual(try Data(contentsOf: checkpoint), savedAccount)

        failed?.engine?.shutdown()
        failed = nil
        try FileManager.default.removeItem(at: root)
    }

    func testLegacyStoreEpochIsResetBeforeCurrentEngineConstruction() throws {
        let root = try makeRoot()
        let appDirectory = root.appendingPathComponent("29er-next", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let store = appDirectory.appendingPathComponent("nmp.redb")
        let marker = appDirectory.appendingPathComponent("nmp-store-epoch")
        let unrelated = appDirectory.appendingPathComponent("identity-state")
        try Data("legacy-store-sentinel".utf8).write(to: store)
        try Data("5\n".utf8).write(to: marker)
        try Data("preserve".utf8).write(to: unrelated)

        var model: AppModel? = AppModel(
            operatorConfiguration: OperatorConfiguration(
                indexerRelays: [],
                groupRelay: "wss://nip29.f7z.io"
            ),
            applicationSupportURL: root
        )

        XCTAssertNotNil(model?.engine)
        XCTAssertEqual(try Data(contentsOf: marker), Data("6\n".utf8))
        XCTAssertNotEqual(try Data(contentsOf: store), Data("legacy-store-sentinel".utf8))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("preserve".utf8))

        model?.engine?.shutdown()
        model = nil
        try FileManager.default.removeItem(at: root)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModel(root: URL) -> AppModel {
        AppModel(
            operatorConfiguration: OperatorConfiguration(
                indexerRelays: [],
                groupRelay: "wss://nip29.f7z.io"
            ),
            applicationSupportURL: root
        )
    }
}
