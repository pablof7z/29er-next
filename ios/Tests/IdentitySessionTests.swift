import XCTest
@testable import TwentyNinerNext

@MainActor
final class IdentitySessionTests: XCTestCase {
    private let secretOne = String(repeating: "0", count: 63) + "1"
    private let publicOne = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    func testValidSecretRestoresAcrossLaunchAndSignOutClearsCheckpoint() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)

        await model?.signIn(secretKey: secretOne)

        XCTAssertEqual(model?.activePubkey, publicOne)
        XCTAssertNil(model?.identityError)
        XCTAssertFalse(model?.isSigningIn ?? true)

        model?.engine?.shutdown()
        model = nil

        var restored: AppModel? = makeModel(root: root)
        XCTAssertEqual(restored?.activePubkey, publicOne)
        let restoredEngineID = try ObjectIdentifier(XCTUnwrap(restored?.engine))
        let restoredGeneration = restored?.engineGeneration

        XCTAssertTrue(restored?.signOut() ?? false)
        XCTAssertNil(restored?.activePubkey)
        XCTAssertNil(restored?.identityError)
        XCTAssertEqual(restored?.engineGeneration, (restoredGeneration ?? 0) + 1)
        XCTAssertNotEqual(
            ObjectIdentifier(try XCTUnwrap(restored?.engine)),
            restoredEngineID
        )

        restored?.engine?.shutdown()
        restored = nil

        var signedOut: AppModel? = makeModel(root: root)
        XCTAssertNil(signedOut?.activePubkey)
        signedOut?.engine?.shutdown()
        signedOut = nil
        try FileManager.default.removeItem(at: root)
    }

    func testInvalidSecretStaysSignedOutWithTypedMessage() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)

        await model?.signIn(secretKey: "not-a-key")

        XCTAssertNil(model?.activePubkey)
        XCTAssertEqual(
            model?.identityError,
            "That secret key is not a valid nsec or secret hex key."
        )
        XCTAssertFalse(model?.isSigningIn ?? true)

        model?.engine?.shutdown()
        model = nil
        try FileManager.default.removeItem(at: root)
    }

    func testDatabaseResetRecoversStartupAndPreservesSavedAccount() async throws {
        let root = try makeRoot()
        var model: AppModel? = makeModel(root: root)
        await model?.signIn(secretKey: secretOne)
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

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModel(root: URL) -> AppModel {
        let configuration = OperatorConfiguration(
            indexerRelays: [],
            groupRelay: "wss://nip29.f7z.io"
        )
        return AppModel(
            operatorConfiguration: configuration,
            applicationSupportURL: root
        )
    }
}
