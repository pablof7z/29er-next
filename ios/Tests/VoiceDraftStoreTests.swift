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
        XCTAssertEqual(recovered.first?.contentType, "audio/x-caf")
        XCTAssertEqual(recovered.first?.filename.hasSuffix(".caf"), true)
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

    func testPreparedDraftJournalsChatTextBeforeAudioBegins() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(scope: "account|relay|room", rootDirectory: root)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 42)

        let prepared = try store.prepareDraft(
            originalText: "Typed before dictating.",
            now: createdAt,
            id: id
        )

        XCTAssertEqual(prepared.id, id)
        XCTAssertEqual(prepared.status, .capturing)
        XCTAssertEqual(prepared.originalText, "Typed before dictating.")
        let manifest = prepared.url.deletingPathExtension().appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
    }

    func testTranscriptAndProviderSnapshotSurviveRelaunch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(scope: "account|relay|room", rootDirectory: root)
        var draft = try store.prepareDraft(originalText: "Existing")
        try Data("captured audio".utf8).write(to: draft.url)
        let providerID = UUID()
        draft.intent = .review
        draft.transcript = "dictated text"
        draft.providerConfigurationID = providerID
        draft.providerName = "Private Apple"
        draft.status = .transcriptReady
        try store.save(draft)

        let recovered = try XCTUnwrap(store.oldestDraft())

        XCTAssertEqual(recovered.id, draft.id)
        XCTAssertEqual(recovered.originalText, "Existing")
        XCTAssertEqual(recovered.transcript, "dictated text")
        XCTAssertEqual(recovered.providerConfigurationID, providerID)
        XCTAssertEqual(recovered.providerName, "Private Apple")
        XCTAssertEqual(recovered.status, .transcriptReady)
    }

    func testEveryRoomDraftRemainsDiscoverable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(scope: "account|relay|room", rootDirectory: root)
        for second in [10.0, 20.0] {
            let draft = try store.prepareDraft(
                originalText: "",
                now: Date(timeIntervalSince1970: second)
            )
            try Data("audio \(second)".utf8).write(to: draft.url)
        }

        XCTAssertEqual(try store.drafts().count, 2)
        XCTAssertLessThan(
            try XCTUnwrap(store.drafts().first?.createdAt),
            try XCTUnwrap(store.drafts().last?.createdAt)
        )
    }
}
