import Foundation
import UniformTypeIdentifiers

struct ComposerAttachment: Identifiable, Hashable, Sendable {
    static let maximumBytes = 25 * 1_024 * 1_024

    let id: UUID
    let filename: String
    let contentType: String
    let data: Data
    let localDraftURL: URL?

    init(
        id: UUID = UUID(),
        filename: String,
        contentType: String,
        data: Data,
        localDraftURL: URL? = nil
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.data = data
        self.localDraftURL = localDraftURL
    }

    static func load(from url: URL) throws -> ComposerAttachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        if let fileSize = values.fileSize, fileSize > maximumBytes {
            throw ComposerAttachmentError.tooLarge(filename: url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ComposerAttachmentError.empty(filename: url.lastPathComponent)
        }
        guard data.count <= maximumBytes else {
            throw ComposerAttachmentError.tooLarge(filename: url.lastPathComponent)
        }

        return ComposerAttachment(
            filename: url.lastPathComponent,
            contentType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
            data: data
        )
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var isImage: Bool {
        UTType(mimeType: contentType)?.conforms(to: .image) == true
    }

    var isAudio: Bool {
        UTType(mimeType: contentType)?.conforms(to: .audio) == true
    }

    func removeLocalDraft() {
        guard let localDraftURL else { return }
        try? FileManager.default.removeItem(at: localDraftURL)
        let manifestURL = localDraftURL
            .deletingPathExtension()
            .appendingPathExtension("json")
        try? FileManager.default.removeItem(at: manifestURL)
    }
}

extension ComposerAttachment {
    /// Loads a pasted image/file the same way an attached one loads: through
    /// `load(from: URL)`, on a copy of the provider's temp file so it survives
    /// past `loadFileRepresentation`'s callback (the original is removed the
    /// moment that callback returns).
    @MainActor
    static func load(from provider: NSItemProvider) async throws -> ComposerAttachment {
        guard let typeIdentifier = provider.preferredTypeIdentifier else {
            throw ComposerAttachmentError.empty(filename: "Pasted item")
        }

        let temporaryURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ComposerAttachmentError.empty(filename: "Pasted item"))
                    return
                }
                do {
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        return try ComposerAttachment.load(from: temporaryURL)
    }
}

private extension NSItemProvider {
    /// A pasted image often registers several type identifiers at once --
    /// e.g. `public.png` alongside an opaque `com.apple.uikit.image` archive
    /// of the serialized `UIImage`. `registeredTypeIdentifiers.first` isn't
    /// reliably the real content: prefer the first identifier that conforms
    /// to a concrete kind we actually want to attach, falling back to
    /// whatever's registered first only if none of them do.
    var preferredTypeIdentifier: String? {
        let preferredConformances: [UTType] = [.image, .movie, .audio, .pdf, .data]
        for conformance in preferredConformances {
            if let match = registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: conformance) == true }) {
                return match
            }
        }
        return registeredTypeIdentifiers.first
    }
}

#if os(iOS)
import PhotosUI
import SwiftUI

extension ComposerAttachment {
    static func load(from item: PhotosPickerItem) async throws -> ComposerAttachment {
        let contentType = item.supportedContentTypes.first
        let filename = "\(UUID().uuidString).\(contentType?.preferredFilenameExtension ?? "dat")"
        guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
            throw ComposerAttachmentError.empty(filename: filename)
        }
        guard data.count <= maximumBytes else {
            throw ComposerAttachmentError.tooLarge(filename: filename)
        }

        return ComposerAttachment(
            filename: filename,
            contentType: contentType?.preferredMIMEType ?? "application/octet-stream",
            data: data
        )
    }
}
#endif

enum ComposerAttachmentError: LocalizedError {
    case empty(filename: String)
    case tooLarge(filename: String)

    var errorDescription: String? {
        switch self {
        case .empty(let filename):
            return "\(filename) is empty."
        case .tooLarge(let filename):
            return "\(filename) is larger than the 25 MB attachment limit."
        }
    }
}
