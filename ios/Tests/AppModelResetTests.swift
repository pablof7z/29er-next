import Foundation
import XCTest
@testable import TwentyNinerNext

@MainActor
final class AppModelResetTests: XCTestCase {
    func testResetReplacesEngineAndPreservesUnrelatedAppData() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let model = AppModel(
            operatorConfiguration: OperatorConfiguration(
                indexerRelays: [],
                groupRelay: "wss://nip29.f7z.io"
            ),
            applicationSupportURL: support
        )
        defer { model.engine?.shutdown() }

        let originalEngine = try XCTUnwrap(model.engine)
        let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
        let unrelated = appDirectory.appendingPathComponent("presentation-state")
        try Data("keep".utf8).write(to: unrelated)
        let originalStoreGeneration = model.storeGeneration
        let receiptStore = DurableReceiptStore(
            rootDirectory: appDirectory,
            storeGeneration: model.storeGeneration,
            scope: .message,
            account: "reset-\(UUID().uuidString)",
            host: "wss://nip29.f7z.io",
            groupID: "room"
        )
        try receiptStore.recordReceiptID(1)
        XCTAssertEqual(try receiptStore.loadReceiptIDs(), [1])

        XCTAssertTrue(model.resetLocalDatabase())

        let replacementEngine = try XCTUnwrap(model.engine)
        XCTAssertNotEqual(model.storeGeneration, "")
        XCTAssertNotEqual(model.storeGeneration, originalStoreGeneration)
        XCTAssertFalse(originalEngine === replacementEngine)
        XCTAssertEqual(model.engineGeneration, 1)
        XCTAssertEqual(model.state, .starting)
        XCTAssertEqual(model.selectedHost, "wss://nip29.f7z.io")
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(try receiptStore.loadReceiptIDs(), [])
    }
}
