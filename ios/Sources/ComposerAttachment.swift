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
    }
}

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
