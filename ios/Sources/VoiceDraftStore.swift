import CryptoKit
import Foundation

struct CompletedVoiceDraft: Equatable, Sendable {
    let url: URL
    let shouldSend: Bool
}

struct VoiceDraftStore: Sendable {
    let directory: URL

    init(
        scope: String,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = rootDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("VoiceMessageDrafts", isDirectory: true)
        let digest = SHA256.hash(data: Data(scope.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        directory = Self.canonicalFileURL(
            root.appendingPathComponent(digest, isDirectory: true)
        )
    }

    func createURL(now: Date = Date(), id: UUID = UUID()) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let timestamp = Int(now.timeIntervalSince1970)
        return directory.appendingPathComponent("voice-\(timestamp)-\(id.uuidString).m4a")
    }

    func recoverAttachments() throws -> [ComposerAttachment] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0 }
            .sorted { lhs, rhs in
                let left = try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate
                let right = try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate
                return (left ?? .distantPast) < (right ?? .distantPast)
            }
            .map(attachment(from:))
    }

    func attachment(from url: URL) throws -> ComposerAttachment {
        let url = Self.canonicalFileURL(url)
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ComposerAttachmentError.empty(filename: url.lastPathComponent)
        }
        guard data.count <= ComposerAttachment.maximumBytes else {
            throw ComposerAttachmentError.tooLarge(filename: url.lastPathComponent)
        }
        return ComposerAttachment(
            filename: url.lastPathComponent,
            contentType: "audio/mp4",
            data: data,
            localDraftURL: url
        )
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: Self.canonicalFileURL(url))
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
