import CryptoKit
import Foundation
import NMP

struct BlossomAttachmentUploader {
    typealias Upload = @Sendable (
        _ serverURL: String,
        _ blob: Data,
        _ contentType: String?,
        _ authorization: BlossomAuthorization
    ) async throws -> String

    private static let authorizationLifetime: UInt64 = 5 * 60

    let engine: NMPEngine
    var now: @Sendable () -> Date
    private let upload: Upload

    init(
        engine: NMPEngine,
        client: BlossomClient = BlossomClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.engine = engine
        self.now = now
        upload = { serverURL, blob, contentType, authorization in
            try await client.upload(
                serverURL: serverURL,
                blob: blob,
                contentType: contentType,
                authorization: authorization
            ).url
        }
    }

    init(
        engine: NMPEngine,
        now: @escaping @Sendable () -> Date,
        upload: @escaping Upload
    ) {
        self.engine = engine
        self.now = now
        self.upload = upload
    }

    func upload(_ attachment: ComposerAttachment, to relay: String) async throws -> URL {
        do {
            try Task.checkCancellation()
            let serverURL = try Self.serverURL(for: relay)
            guard let author = try engine.activeAccount() else {
                throw AttachmentUploadError.signInRequired
            }

            let (createdAt, expiration) = try Self.authorizationTimes(now())
            let hash = Self.sha256Hex(attachment.data)
            let draft = try blossomUploadAuthorizationDraft(
                authorPubkeyHex: author,
                blobSha256Hex: hash,
                createdAt: createdAt,
                expiration: expiration,
                description: "Upload \(attachment.filename)"
            )
            let signed = try await engine.signEvent(draft.signRequest)
            let validationTime = max(createdAt, try Self.unixTimestamp(now()))
            let authorization = try BlossomAuthorization.validate(
                signedEvent: signed,
                verb: .upload,
                blobSha256Hex: hash,
                now: validationTime
            )

            let descriptorURL = try await upload(
                serverURL,
                attachment.data,
                attachment.contentType,
                authorization
            )
            guard let url = URL(string: descriptorURL), MessageContent.isSupportedWebURL(url) else {
                throw AttachmentUploadError.invalidResponse
            }
            return url
        } catch let error as AttachmentUploadError {
            throw error
        } catch is CancellationError {
            throw AttachmentUploadError.cancelled
        } catch let error as NMP.BlossomUploadError {
            throw AttachmentUploadError(error)
        } catch is BlossomAuthError {
            throw AttachmentUploadError.authorizationFailed
        } catch let error as NMPError {
            throw AttachmentUploadError(error)
        } catch {
            throw AttachmentUploadError.uploadUnavailable
        }
    }

    static func serverURL(for relay: String) throws -> String {
        guard var components = URLComponents(string: relay) else {
            throw AttachmentUploadError.invalidServer
        }
        switch components.scheme?.lowercased() {
        case "wss", "https":
            components.scheme = "https"
        case "ws", "http":
            components.scheme = "http"
        default:
            throw AttachmentUploadError.invalidServer
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let serverURL = components.string else {
            throw AttachmentUploadError.invalidServer
        }
        return serverURL
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func authorizationTimes(_ date: Date) throws -> (createdAt: UInt64, expiration: UInt64) {
        let createdAt = try unixTimestamp(date)
        let result = createdAt.addingReportingOverflow(authorizationLifetime)
        guard !result.overflow else {
            throw AttachmentUploadError.authorizationFailed
        }
        return (createdAt, result.partialValue)
    }

    static func unixTimestamp(_ date: Date) throws -> UInt64 {
        guard let timestamp = UInt64(exactly: date.timeIntervalSince1970.rounded(.down)) else {
            throw AttachmentUploadError.authorizationFailed
        }
        return timestamp
    }
}

enum AttachmentUploadError: LocalizedError, Equatable {
    case signInRequired
    case invalidServer
    case authorizationFailed
    case authorizationRejected(status: UInt16, reason: String?)
    case serverRejected(status: UInt16, reason: String?)
    case integrityCheckFailed
    case invalidResponse
    case uploadUnavailable
    case cancelled

    init(_ error: NMP.BlossomUploadError) {
        switch error {
        case .invalidServerUrl, .localHostNotAdmitted:
            self = .invalidServer
        case .runtimeUnavailable, .clientBuild, .network:
            self = .uploadUnavailable
        case .redirectRefused, .responseTooLarge, .descriptorInvalid:
            self = .invalidResponse
        case .authRejected(let status, let reason):
            self = .authorizationRejected(status: status, reason: reason)
        case .serverRejected(let status, let reason), .serverError(let status, let reason):
            self = .serverRejected(status: status, reason: reason)
        case .authorizationBlobMismatch, .sha256Mismatch:
            self = .integrityCheckFailed
        }
    }

    init(_ error: NMPError) {
        switch error {
        case .noActiveSigner:
            self = .signInRequired
        case .invalidSignRequest, .invalidSignerOutput, .invalidSignature, .signerRejected:
            self = .authorizationFailed
        case .signerUnavailable, .engineClosed:
            self = .uploadUnavailable
        default:
            self = .uploadUnavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            "Sign in to upload attachments."
        case .invalidServer:
            "This room does not provide a safe attachment server."
        case .authorizationFailed:
            "The attachment upload could not be authorized."
        case .authorizationRejected(let status, let reason):
            Self.statusMessage("The attachment server rejected authorization", status, reason)
        case .serverRejected(let status, let reason):
            Self.statusMessage("The attachment server rejected the upload", status, reason)
        case .integrityCheckFailed:
            "The attachment server returned data that did not match the uploaded file."
        case .invalidResponse:
            "The attachment server returned an unsafe or invalid response."
        case .uploadUnavailable:
            "The attachment upload could not be completed."
        case .cancelled:
            "The attachment upload was cancelled."
        }
    }

    private static func statusMessage(_ prefix: String, _ status: UInt16, _ reason: String?) -> String {
        let detail = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? "\(prefix) (HTTP \(status))." : "\(prefix) (HTTP \(status)): \(detail)"
    }
}
