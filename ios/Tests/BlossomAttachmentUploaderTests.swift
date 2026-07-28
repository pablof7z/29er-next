import Foundation
import NMP
import XCTest
@testable import TwentyNinerNext

final class BlossomAttachmentUploaderTests: XCTestCase {
    func testRelayOriginBecomesBlossomServerConfiguration() throws {
        XCTAssertEqual(
            try BlossomAttachmentUploader.serverURL(for: "wss://nip29.f7z.io/groups?id=1"),
            "https://nip29.f7z.io/"
        )
        XCTAssertEqual(
            try BlossomAttachmentUploader.serverURL(for: "ws://localhost:8080/api/"),
            "http://localhost:8080/"
        )
    }

    func testUnsupportedRelaySchemeIsRejectedBeforeSigning() {
        XCTAssertThrowsError(try BlossomAttachmentUploader.serverURL(for: "ftp://relay.example")) {
            XCTAssertEqual($0 as? AttachmentUploadError, .invalidServer)
        }
    }

    func testSHA256MatchesTheBlossomBodyHashInput() {
        XCTAssertEqual(
            BlossomAttachmentUploader.sha256Hex(Data("hello".utf8)),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testAuthorizationWindowRejectsInvalidAndOverflowingClocks() {
        for seconds in [Double.nan, -1, Double(UInt64.max)] {
            XCTAssertThrowsError(
                try BlossomAttachmentUploader.authorizationTimes(
                    Date(timeIntervalSince1970: seconds)
                )
            ) {
                XCTAssertEqual($0 as? AttachmentUploadError, .authorizationFailed)
            }
        }
    }

    func testUploaderUsesNMPDraftSigningAndValidatedAuthorization() async throws {
        let engine = try await makeActiveEngine()
        defer { engine.shutdown() }
        let recorder = UploadRecorder(returnedURL: "https://cdn.example.com/blob")
        let uploader = BlossomAttachmentUploader(
            engine: engine,
            now: { Date(timeIntervalSince1970: 1_000) },
            upload: { serverURL, blob, contentType, authorization in
                await recorder.record(
                    serverURL: serverURL,
                    blob: blob,
                    contentType: contentType,
                    verb: authorization.verb,
                    hash: authorization.blobSha256Hex
                )
            }
        )
        let attachment = ComposerAttachment(
            filename: "hello.txt",
            contentType: "text/plain",
            data: Data("hello".utf8)
        )

        let url = try await uploader.upload(attachment, to: "wss://relay.example/groups")
        let recordedRequest = await recorder.request
        let request = try XCTUnwrap(recordedRequest)

        XCTAssertEqual(url.absoluteString, "https://cdn.example.com/blob")
        XCTAssertEqual(request.serverURL, "https://relay.example/")
        XCTAssertEqual(request.blob, attachment.data)
        XCTAssertEqual(request.contentType, attachment.contentType)
        XCTAssertEqual(request.verb, .upload)
        XCTAssertEqual(request.hash, BlossomAttachmentUploader.sha256Hex(attachment.data))
    }

    func testUploaderRequiresAnActiveNMPAccountBeforeUpload() async throws {
        let engine = try NMPEngine(config: NMPConfig())
        defer { engine.shutdown() }
        let recorder = UploadRecorder(returnedURL: "https://cdn.example.com/blob")
        let uploader = BlossomAttachmentUploader(
            engine: engine,
            now: { Date(timeIntervalSince1970: 1_000) },
            upload: { serverURL, blob, contentType, authorization in
                await recorder.record(
                    serverURL: serverURL,
                    blob: blob,
                    contentType: contentType,
                    verb: authorization.verb,
                    hash: authorization.blobSha256Hex
                )
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await uploader.upload(Self.attachment, to: "wss://relay.example")
        ) {
            XCTAssertEqual($0 as? AttachmentUploadError, .signInRequired)
        }
        let recordedRequest = await recorder.request
        XCTAssertNil(recordedRequest)
    }

    func testUploaderRejectsAnUnsafeReturnedURL() async throws {
        let engine = try await makeActiveEngine()
        defer { engine.shutdown() }
        let uploader = BlossomAttachmentUploader(
            engine: engine,
            now: { Date(timeIntervalSince1970: 1_000) },
            upload: { _, _, _, _ in "javascript:alert(1)" }
        )

        await XCTAssertThrowsErrorAsync(
            try await uploader.upload(Self.attachment, to: "wss://relay.example")
        ) {
            XCTAssertEqual($0 as? AttachmentUploadError, .invalidResponse)
        }
    }

    func testNMPAuthorizationRefusesATamperedBlobBinding() async throws {
        let engine = try await makeActiveEngine()
        defer { engine.shutdown() }
        let author = try XCTUnwrap(try engine.activeAccount())
        let expected = BlossomAttachmentUploader.sha256Hex(Self.attachment.data)
        let draft = try blossomUploadAuthorizationDraft(
            authorPubkeyHex: author,
            blobSha256Hex: expected,
            createdAt: 1_000,
            expiration: 1_300,
            description: "Upload attachment.txt"
        )
        let signed = try await engine.signEvent(draft.signRequest)

        XCTAssertThrowsError(
            try BlossomAuthorization.validate(
                signedEvent: signed,
                verb: .upload,
                blobSha256Hex: String(repeating: "b", count: 64),
                now: 1_001
            )
        ) {
            guard case BlossomAuthError.blobNotBound = $0 else {
                return XCTFail("Expected a typed blob binding refusal, got \($0)")
            }
        }
    }

    func testRealRustClientUploadsToALocalBlossomServer() async throws {
        let server = try await BlossomHTTPServer.start(.success, expectedBlob: Self.attachment.data)
        defer { server.stop() }
        let engine = try await makeActiveEngine()
        defer { engine.shutdown() }
        let client = BlossomClient(
            config: BlossomClientConfig(
                allowedLocalHosts: ["127.0.0.1"],
                requestDeadlineSeconds: 5
            )
        )
        let uploader = BlossomAttachmentUploader(
            engine: engine,
            client: client,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let url = try await uploader.upload(Self.attachment, to: server.relayURL)

        XCTAssertEqual(url.absoluteString, server.publicBlobURL)
        let receivedBody = server.receivedBody
        let authorizationPrefix = server.authorizationPrefix
        XCTAssertEqual(receivedBody, Self.attachment.data)
        XCTAssertEqual(authorizationPrefix, "Nostr ")
    }

    func testRealRustClientRefusesRedirects() async throws {
        let server = try await BlossomHTTPServer.start(.redirect, expectedBlob: Self.attachment.data)
        defer { server.stop() }
        let engine = try await makeActiveEngine()
        defer { engine.shutdown() }
        let client = BlossomClient(
            config: BlossomClientConfig(
                allowedLocalHosts: ["127.0.0.1"],
                requestDeadlineSeconds: 5
            )
        )
        let uploader = BlossomAttachmentUploader(
            engine: engine,
            client: client,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        await XCTAssertThrowsErrorAsync(
            try await uploader.upload(Self.attachment, to: server.relayURL)
        ) {
            XCTAssertEqual($0 as? AttachmentUploadError, .invalidResponse)
        }
    }

    func testRealRustClientRefusesDescriptorHashMismatch() async throws {
        let server = try await BlossomHTTPServer.start(
            .hashMismatch,
            expectedBlob: Self.attachment.data
        )
        defer { server.stop() }
        let engine = try await makeActiveEngine()
        defer { engine.shutdown() }
        let client = BlossomClient(
            config: BlossomClientConfig(
                allowedLocalHosts: ["127.0.0.1"],
                requestDeadlineSeconds: 5
            )
        )
        let uploader = BlossomAttachmentUploader(
            engine: engine,
            client: client,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        await XCTAssertThrowsErrorAsync(
            try await uploader.upload(Self.attachment, to: server.relayURL)
        ) {
            XCTAssertEqual($0 as? AttachmentUploadError, .integrityCheckFailed)
        }
    }

    func testTypedNMPUploadFailuresMapWithoutStringParsing() {
        XCTAssertEqual(
            AttachmentUploadError(
                NMP.BlossomUploadError.authRejected(status: 401, reason: "expired")
            ),
            .authorizationRejected(status: 401, reason: "expired")
        )
        XCTAssertEqual(
            AttachmentUploadError(
                NMP.BlossomUploadError.serverRejected(status: 409, reason: "conflict")
            ),
            .serverRejected(status: 409, reason: "conflict")
        )
        XCTAssertEqual(
            AttachmentUploadError(
                NMP.BlossomUploadError.sha256Mismatch(
                    expectedSha256Hex: String(repeating: "a", count: 64),
                    returnedSha256Hex: String(repeating: "b", count: 64)
                )
            ),
            .integrityCheckFailed
        )
    }

    fileprivate static let attachment = ComposerAttachment(
        filename: "attachment.txt",
        contentType: "text/plain",
        data: Data("hello".utf8)
    )

    private func makeActiveEngine() async throws -> NMPEngine {
        let engine = try NMPEngine(config: NMPConfig())
        let secret = String(repeating: "0", count: 63) + "1"
        let registration = try await engine.addAccount(secretKey: secret)
        try engine.setActiveAccount(registration.publicKey)
        return engine
    }
}
