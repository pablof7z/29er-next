import CryptoKit
import Foundation

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
        try prepareDirectory()
        let timestamp = Int(now.timeIntervalSince1970)
        return directory.appendingPathComponent("voice-\(timestamp)-\(id.uuidString).caf")
    }

    /// Creates and atomically journals a recording before the microphone starts.
    /// The audio encoder then writes directly to `draft.url`; a process death can never
    /// make the room association or existing composer text disappear.
    func prepareDraft(
        originalText: String,
        now: Date = Date(),
        id: UUID = UUID()
    ) throws -> VoiceDraft {
        let url = try createURL(now: now, id: id)
        let draft = VoiceDraft(
            id: id,
            url: url,
            createdAt: now,
            duration: 0,
            waveform: [],
            originalText: originalText,
            status: .capturing
        )
        try save(draft)
        return draft
    }

    /// Non-empty durable draft files for this room, oldest first.
    func draftURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { ["caf", "m4a"].contains($0.pathExtension.lowercased()) }
            .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0 }
            .sorted { lhs, rhs in
                let left = try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate
                let right = try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate
                return (left ?? .distantPast) < (right ?? .distantPast)
            }
            .map(Self.canonicalFileURL)
    }

    /// The most recent recoverable draft for this room, if any.
    func newestDraftURL() throws -> URL? {
        try draftURLs().last
    }

    /// Every recoverable draft for the room, including its journaled text/transcript.
    func drafts() throws -> [VoiceDraft] {
        let urls = try draftURLs()
        return urls.map { url in
            guard let manifest = try? loadManifest(for: url) else {
                return VoiceDraft(url: url, duration: 0, waveform: [], status: .ready)
            }
            return manifest.draft(audioURL: url)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func oldestDraft() throws -> VoiceDraft? {
        try drafts().first
    }

    func save(_ draft: VoiceDraft) throws {
        try prepareDirectory()
        let data = try JSONEncoder().encode(VoiceDraftManifest(draft))
        try data.write(to: manifestURL(for: draft.url), options: [.atomic])
    }

    func recoverAttachments() throws -> [ComposerAttachment] {
        try draftURLs().map(attachment(from:))
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
            contentType: url.pathExtension.lowercased() == "caf" ? "audio/x-caf" : "audio/mp4",
            data: data,
            localDraftURL: url
        )
    }

    func remove(_ url: URL) {
        let canonical = Self.canonicalFileURL(url)
        try? FileManager.default.removeItem(at: canonical)
        try? FileManager.default.removeItem(at: manifestURL(for: canonical))
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
    }

    private func manifestURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("json")
    }

    private func loadManifest(for audioURL: URL) throws -> VoiceDraftManifest {
        let data = try Data(contentsOf: manifestURL(for: audioURL))
        return try JSONDecoder().decode(VoiceDraftManifest.self, from: data)
    }

    static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private struct VoiceDraftManifest: Codable {
    let version: Int
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let waveform: [Float]
    let originalText: String
    let intent: VoiceFinalizeIntent?
    let transcript: String?
    let providerConfigurationID: UUID?
    let providerName: String?
    let status: VoiceDraftStatus

    init(_ draft: VoiceDraft) {
        version = 1
        id = draft.id
        createdAt = draft.createdAt
        duration = draft.duration
        waveform = draft.waveform
        originalText = draft.originalText
        intent = draft.intent
        transcript = draft.transcript
        providerConfigurationID = draft.providerConfigurationID
        providerName = draft.providerName
        status = draft.status
    }

    func draft(audioURL: URL) -> VoiceDraft {
        VoiceDraft(
            id: id,
            url: audioURL,
            createdAt: createdAt,
            duration: duration,
            waveform: waveform,
            originalText: originalText,
            intent: intent,
            transcript: transcript,
            providerConfigurationID: providerConfigurationID,
            providerName: providerName,
            status: status
        )
    }
}
