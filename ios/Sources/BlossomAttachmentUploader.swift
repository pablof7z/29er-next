import CryptoKit
import Foundation
import NMP

struct BlossomAttachmentUploader {
    private static let authorizationLifetime: UInt64 = 5 * 60

    let engine: NMPEngine
    var session: URLSession = .shared
    var now: @Sendable () -> Date = Date.init

    func upload(_ attachment: ComposerAttachment, to relay: String) async throws -> URL {
        let server = try Self.serverURL(for: relay)
        let hash = Self.sha256Hex(attachment.data)
        let authorization = try await authorizationHeader(server: server, hash: hash)
        let uploadURL = server.appendingPathComponent("upload", isDirectory: false)

        var request = URLRequest(url: uploadURL, timeoutInterval: 5 * 60)
        request.httpMethod = "PUT"
        request.httpBody = attachment.data
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(attachment.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(hash, forHTTPHeaderField: "X-SHA-256")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BlossomUploadError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (String(bytes: data.prefix(500), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BlossomUploadError.server(status: http.statusCode, detail: detail)
        }

        let descriptor: BlossomDescriptor
        do {
            descriptor = try JSONDecoder().decode(BlossomDescriptor.self, from: data)
        } catch {
            throw BlossomUploadError.malformedDescriptor
        }
        return try Self.validatedURL(
            descriptor: descriptor,
            expectedHash: hash,
            expectedSize: attachment.data.count
        )
    }

    static func serverURL(for relay: String) throws -> URL {
        guard var components = URLComponents(string: relay) else {
            throw BlossomUploadError.invalidRelay
        }
        switch components.scheme?.lowercased() {
        case "wss", "https": components.scheme = "https"
        case "ws", "http": components.scheme = "http"
        default: throw BlossomUploadError.invalidRelay
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let url = components.url, url.host != nil else {
            throw BlossomUploadError.invalidRelay
        }
        return url
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func authorizationHeader(server: URL, hash: String) async throws -> String {
        let createdAt = UInt64(now().timeIntervalSince1970)
        let unsigned = try Self.authorizationEvent(
            server: server,
            hash: hash,
            createdAt: createdAt
        )
        let signed = try await engine.signEvent(unsigned)
        let event = BlossomAuthorizationEvent(signed)
        let json = try JSONEncoder().encode(event)
        return "Nostr \(json.base64EncodedString())"
    }

    static func authorizationEvent(
        server: URL,
        hash: String,
        createdAt: UInt64
    ) throws -> NMPUnsignedEvent {
        guard let host = server.host?.lowercased() else {
            throw BlossomUploadError.invalidRelay
        }
        return NMPUnsignedEvent(
            createdAt: createdAt,
            kind: 24_242,
            tags: [
                ["t", "upload"],
                ["expiration", String(createdAt + Self.authorizationLifetime)],
                ["x", hash],
                ["server", host]
            ],
            content: "Upload Blob"
        )
    }

    static func validatedURL(
        descriptor: BlossomDescriptor,
        expectedHash: String,
        expectedSize: Int
    ) throws -> URL {
        guard descriptor.sha256.caseInsensitiveCompare(expectedHash) == .orderedSame else {
            throw BlossomUploadError.hashMismatch
        }
        guard descriptor.size == expectedSize,
              !descriptor.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              descriptor.uploaded > 0 else {
            throw BlossomUploadError.incompleteDescriptor
        }
        guard let url = URL(string: descriptor.url),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.path.lowercased().contains(expectedHash.lowercased()) else {
            throw BlossomUploadError.invalidPublicURL
        }
        return url
    }
}

struct BlossomDescriptor: Decodable {
    let url: String
    let sha256: String
    let size: Int
    let type: String
    let uploaded: UInt64
}

private struct BlossomAuthorizationEvent: Encodable {
    let id: String
    let pubkey: String
    let createdAt: UInt64
    let kind: UInt16
    let tags: [[String]]
    let content: String
    let sig: String

    init(_ event: NMPSignedEvent) {
        id = event.id
        pubkey = event.pubkey
        createdAt = event.createdAt
        kind = event.kind
        tags = event.tags
        content = event.content
        sig = event.sig
    }

    enum CodingKeys: String, CodingKey {
        case id, pubkey, kind, tags, content, sig
        case createdAt = "created_at"
    }
}

enum BlossomUploadError: LocalizedError, Equatable {
    case invalidRelay
    case invalidResponse
    case server(status: Int, detail: String)
    case malformedDescriptor
    case hashMismatch
    case incompleteDescriptor
    case invalidPublicURL

    var errorDescription: String? {
        switch self {
        case .invalidRelay:
            return "This room relay does not provide a valid Blossom upload address."
        case .invalidResponse:
            return "The attachment server returned an invalid response."
        case .server(let status, let detail):
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            return "Attachment upload failed with HTTP \(status)\(suffix)"
        case .malformedDescriptor:
            return "The attachment server returned a malformed upload descriptor."
        case .hashMismatch:
            return "The attachment server returned a different file hash."
        case .incompleteDescriptor:
            return "The attachment server returned an incomplete upload descriptor."
        case .invalidPublicURL:
            return "The attachment server returned an invalid public URL."
        }
    }
}
