import Foundation
import XCTest
@testable import TwentyNinerNext

@MainActor
final class AppModelResetTests: XCTestCase {
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
        XCTAssertNil(model.selectedHost)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(checkpoint.saveCount, 1)
    }
}
