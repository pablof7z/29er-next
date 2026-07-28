import Foundation
import Network
import NMP
import XCTest
@testable import TwentyNinerNext

actor UploadRecorder {
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

final class BlossomHTTPServer: @unchecked Sendable {
    enum Behavior {
        case success
        case redirect
        case hashMismatch
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "BlossomHTTPServer")
    private let behavior: Behavior
    private let expectedHash: String
    private let lock = NSLock()
    private var body = Data()
    private var authPrefix: String?

    var relayURL: String {
        "ws://127.0.0.1:\(listener.port!.rawValue)"
    }

    var publicBlobURL: String {
        "https://cdn.example.com/\(expectedHash)"
    }

    var receivedBody: Data { lock.withLock { body } }

    var authorizationPrefix: String? { lock.withLock { authPrefix } }

    private init(listener: NWListener, behavior: Behavior, expectedBlob: Data) {
        self.listener = listener
        self.behavior = behavior
        expectedHash = BlossomAttachmentUploader.sha256Hex(expectedBlob)
    }

    static func start(_ behavior: Behavior, expectedBlob: Data) async throws -> BlossomHTTPServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = BlossomHTTPServer(
            listener: listener,
            behavior: behavior,
            expectedBlob: expectedBlob
        )
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
        }.flatMap {
            Int(
                $0.split(separator: ":", maxSplits: 1)[1]
                    .trimmingCharacters(in: .whitespaces)
            )
        } ?? 0
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
        let responseHead = "HTTP/1.1 \(status)\r\n"
            + extraHeaders
            + "Content-Length: \(responseBody.count)\r\n"
            + "Connection: close\r\n\r\n"
        let head = Data(responseHead.utf8)
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

func XCTAssertThrowsErrorAsync<T>(
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
