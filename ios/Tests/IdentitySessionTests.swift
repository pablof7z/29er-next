import XCTest
@testable import TwentyNinerNext

@MainActor
final class IdentitySessionTests: XCTestCase {
    private let secretOne = String(repeating: "0", count: 63) + "1"
    private let publicOne = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    func testValidSecretActivatesAccountAndEndingSessionReplacesEngine() async throws {
        let fixture = try makeModel()
        var model: AppModel? = fixture.model

        await model?.signIn(secretKey: secretOne)

        XCTAssertEqual(model?.activePubkey, publicOne)
        XCTAssertNil(model?.identityError)
        XCTAssertFalse(model?.isSigningIn ?? true)

        let signedInEngineID = try ObjectIdentifier(XCTUnwrap(model?.engine))
        let signedInGeneration = model?.engineGeneration
        model?.endIdentitySession()
        XCTAssertNil(model?.activePubkey)
        XCTAssertNil(model?.identityError)
        XCTAssertEqual(model?.engineGeneration, (signedInGeneration ?? 0) + 1)
        let readOnlyEngine = try XCTUnwrap(model?.engine)
        XCTAssertNotEqual(ObjectIdentifier(readOnlyEngine), signedInEngineID)

        model?.engine?.shutdown()
        model = nil
        try FileManager.default.removeItem(at: fixture.root)
    }

    func testInvalidSecretStaysSignedOutWithTypedMessage() async throws {
        let fixture = try makeModel()
        var model: AppModel? = fixture.model

        await model?.signIn(secretKey: "not-a-key")

        XCTAssertNil(model?.activePubkey)
        XCTAssertEqual(
            model?.identityError,
            "That secret key is not a valid nsec or secret hex key."
        )
        XCTAssertFalse(model?.isSigningIn ?? true)

        model?.engine?.shutdown()
        model = nil
        try FileManager.default.removeItem(at: fixture.root)
    }

    private func makeModel() throws -> (model: AppModel, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = OperatorConfiguration(
            indexerRelays: [],
            groupRelay: "wss://nip29.f7z.io"
        )
        return (
            AppModel(
                operatorConfiguration: configuration,
                applicationSupportURL: root
            ),
            root
        )
    }
}
