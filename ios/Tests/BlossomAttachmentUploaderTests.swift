import Foundation
import Network
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
        let server = try await BlossomHTTPServer.start(.success)
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
        let server = try await BlossomHTTPServer.start(.redirect)
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
        let server = try await BlossomHTTPServer.start(.hashMismatch)
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

private actor UploadRecorder {
    struct Request: Sendable {
        let serverURL: String
        let blob: Data
        let contentType: String?
        let verb: BlossomVerb
        let hash: String?
    }

    let returnedURL: String
    private(set) var request: Request?

    init(returnedURL: String) {
        self.returnedURL = returnedURL
    }

    func record(
        serverURL: String,
        blob: Data,
        contentType: String?,
        verb: BlossomVerb,
        hash: String?
    ) -> String {
        request = Request(
            serverURL: serverURL,
            blob: blob,
            contentType: contentType,
            verb: verb,
            hash: hash
        )
        return returnedURL
    }
}

private final class BlossomHTTPServer: @unchecked Sendable {
    enum Behavior {
        case success
        case redirect
        case hashMismatch
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "BlossomHTTPServer")
    private let behavior: Behavior
    private let lock = NSLock()
    private var body = Data()
    private var authPrefix: String?

    var relayURL: String {
        "ws://127.0.0.1:\(listener.port!.rawValue)"
    }

    var publicBlobURL: String {
        let hash = BlossomAttachmentUploader.sha256Hex(BlossomAttachmentUploaderTests.attachment.data)
        return "https://cdn.example.com/\(hash)"
    }

    var receivedBody: Data { lock.withLock { body } }

    var authorizationPrefix: String? { lock.withLock { authPrefix } }

    private init(listener: NWListener, behavior: Behavior) {
        self.listener = listener
        self.behavior = behavior
    }

    static func start(_ behavior: Behavior) async throws -> BlossomHTTPServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = BlossomHTTPServer(listener: listener, behavior: behavior)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OneShot()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim() {
                        continuation.resume()
                    }
                case .failed(let error):
                    if resumed.claim() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in
                server.handle(connection)
            }
            listener.start(queue: server.queue)
        }
        return server
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, complete, error in
            guard let self else { return }
            var request = accumulated
            if let data { request.append(data) }
            if let expected = self.expectedRequestLength(request), request.count >= expected {
                self.respond(to: connection, request: request)
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, accumulated: request)
            }
        }
    }

    private func expectedRequestLength(_ request: Data) -> Int? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = request.range(of: marker),
              let headers = String(data: request[..<headerRange.lowerBound], encoding: .utf8)
        else { return nil }
        let contentLength = headers.split(separator: "\r\n").first { line in
            line.lowercased().hasPrefix("content-length:")
        }.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        return headerRange.upperBound + contentLength
    }

    private func respond(to connection: NWConnection, request: Data) {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = request.range(of: marker) else {
            connection.cancel()
            return
        }
        let headers = String(data: request[..<headerRange.lowerBound], encoding: .utf8) ?? ""
        lock.withLock {
            body = Data(request[headerRange.upperBound...])
            authPrefix = headers.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("authorization:") }
                .map { line in
                    let value = line.split(separator: ":", maxSplits: 1)[1]
                        .trimmingCharacters(in: .whitespaces)
                    return String(value.prefix(6))
                }
        }

        let status: String
        let extraHeaders: String
        let responseBody: Data
        switch behavior {
        case .success:
            status = "200 OK"
            extraHeaders = "Content-Type: application/json\r\n"
            responseBody = descriptor(hash: BlossomAttachmentUploader.sha256Hex(body))
        case .redirect:
            status = "302 Found"
            extraHeaders = "Location: \(publicBlobURL)\r\n"
            responseBody = Data()
        case .hashMismatch:
            status = "200 OK"
            extraHeaders = "Content-Type: application/json\r\n"
            responseBody = descriptor(hash: String(repeating: "b", count: 64))
        }
        let head = Data(
            "HTTP/1.1 \(status)\r\n\(extraHeaders)Content-Length: \(responseBody.count)\r\nConnection: close\r\n\r\n"
                .utf8
        )
        connection.send(content: head + responseBody, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func descriptor(hash: String) -> Data {
        Data(
            #"{"url":"\#(publicBlobURL)","sha256":"\#(hash)","size":\#(body.count),"type":"text/plain","uploaded":1000}"#
                .utf8
        )
    }
}

private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
