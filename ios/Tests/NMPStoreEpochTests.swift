import Foundation
import XCTest
@testable import TwentyNinerNext

final class NMPStoreEpochTests: XCTestCase {
    func testFreshDirectoryPublishesCurrentMarkerBeforeEngineUse() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storePath = try NMPStoreEpoch().prepare(appDirectory: root)

        XCTAssertEqual(storePath, root.appendingPathComponent("nmp.redb").path)
        XCTAssertEqual(try markerData(root), Data("6\n".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storePath))
    }

    func testCurrentMarkerPreservesStoreAndUnrelatedFiles() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("nmp.redb")
        let unrelated = root.appendingPathComponent("identity-state")
        try Data("current-store".utf8).write(to: store)
        try Data("keep".utf8).write(to: unrelated)
        try Data("6\n".utf8).write(to: marker(root))

        _ = try NMPStoreEpoch().prepare(appDirectory: root)

        XCTAssertEqual(try Data(contentsOf: store), Data("current-store".utf8))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
    }

    func testLegacyMarkerRemovesOnlyExactStoreThenPublishesCurrentMarker() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("nmp.redb")
        let similarlyNamed = root.appendingPathComponent("nmp.redb.backup")
        try Data("legacy-store".utf8).write(to: store)
        try Data("preserve".utf8).write(to: similarlyNamed)
        try Data("5\n".utf8).write(to: marker(root))

        _ = try NMPStoreEpoch().prepare(appDirectory: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertEqual(try Data(contentsOf: similarlyNamed), Data("preserve".utf8))
        XCTAssertEqual(try markerData(root), Data("6\n".utf8))
    }

    func testDeletionFailureDoesNotPublishCurrentMarker() throws {
        enum Failure: Error { case remove }
        let markerURL = URL(fileURLWithPath: "/app/nmp-store-epoch")
        let storeURL = URL(fileURLWithPath: "/app/nmp.redb")
        var wroteMarker = false
        let epoch = NMPStoreEpoch(
            fileExists: { $0 == markerURL || $0 == storeURL },
            read: { _ in Data("5\n".utf8) },
            remove: { _ in throw Failure.remove },
            writeAtomically: { _, _ in wroteMarker = true }
        )

        XCTAssertThrowsError(try epoch.prepare(appDirectory: URL(fileURLWithPath: "/app")))
        XCTAssertFalse(wroteMarker)
    }

    func testMarkerWriteFailureLeavesDeletedStoreRetryable() throws {
        enum Failure: Error { case write }
        let markerURL = URL(fileURLWithPath: "/app/nmp-store-epoch")
        let storeURL = URL(fileURLWithPath: "/app/nmp.redb")
        var existing = Set([markerURL, storeURL])
        var markerData = Data("5\n".utf8)
        let epoch = NMPStoreEpoch(
            fileExists: { existing.contains($0) },
            read: { _ in markerData },
            remove: { existing.remove($0) },
            writeAtomically: { _, _ in throw Failure.write }
        )

        XCTAssertThrowsError(try epoch.prepare(appDirectory: URL(fileURLWithPath: "/app")))
        XCTAssertFalse(existing.contains(storeURL))
        XCTAssertEqual(markerData, Data("5\n".utf8))

        let retry = NMPStoreEpoch(
            fileExists: { existing.contains($0) },
            read: { _ in markerData },
            remove: { existing.remove($0) },
            writeAtomically: { data, url in
                markerData = data
                existing.insert(url)
            }
        )
        _ = try retry.prepare(appDirectory: URL(fileURLWithPath: "/app"))
        XCTAssertEqual(markerData, Data("6\n".utf8))
        XCTAssertTrue(existing.contains(markerURL))
    }

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func marker(_ root: URL) -> URL {
        root.appendingPathComponent("nmp-store-epoch")
    }

    private func markerData(_ root: URL) throws -> Data {
        try Data(contentsOf: marker(root))
    }
}
