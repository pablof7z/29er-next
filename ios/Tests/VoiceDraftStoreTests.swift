import Foundation
import XCTest
@testable import TwentyNinerNext

final class VoiceDraftStoreTests: XCTestCase {
    func testDraftIsRoomScopedAndRecoverable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = VoiceDraftStore(scope: "relay|room-a", rootDirectory: root)
        let second = VoiceDraftStore(scope: "relay|room-b", rootDirectory: root)
        let url = try first.createURL(now: Date(timeIntervalSince1970: 10), id: UUID())
        try Data("captured audio".utf8).write(to: url)

        let recovered = try first.recoverAttachments()

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.contentType, "audio/mp4")
        XCTAssertEqual(url, url.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(recovered.first?.localDraftURL, url)
        XCTAssertTrue(try second.recoverAttachments().isEmpty)
    }

    func testNewestDraftURLReturnsMostRecentRecording() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(scope: "room", rootDirectory: root)
        let older = try store.createURL(now: Date(timeIntervalSince1970: 10), id: UUID())
        try Data("older".utf8).write(to: older)
        let newer = try store.createURL(now: Date(timeIntervalSince1970: 5_000), id: UUID())
        try Data("newer".utf8).write(to: newer)

        XCTAssertEqual(try store.draftURLs().count, 2)
        XCTAssertEqual(try store.newestDraftURL(), newer)
    }

    func testNewestDraftURLIsNilWhenEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(scope: "empty-room", rootDirectory: root)
        XCTAssertNil(try store.newestDraftURL())
    }

    func testLocalDraftSurvivesUntilExplicitRemoval() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(scope: "room", rootDirectory: root)
        let url = try store.createURL()
        try Data("captured audio".utf8).write(to: url)
        let attachment = try store.attachment(from: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        attachment.removeLocalDraft()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
