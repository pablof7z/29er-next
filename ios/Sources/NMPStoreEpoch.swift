import Foundation

/// Owns 29er Next's explicit rollout boundary for NMP's persistent store.
///
/// NMP deliberately refuses an older event epoch and never deletes a
/// caller-owned database. This app owns exactly one cache file, so an app
/// release that changes the expected epoch removes only that file before
/// constructing `NMPEngine`, then atomically publishes its epoch marker.
struct NMPStoreEpoch {
    static let current = 6

    private let fileExists: (URL) -> Bool
    private let read: (URL) throws -> Data
    private let remove: (URL) throws -> Void
    private let writeAtomically: (Data, URL) throws -> Void

    init(fileManager: FileManager = .default) {
        fileExists = { fileManager.fileExists(atPath: $0.path) }
        read = { try Data(contentsOf: $0) }
        remove = { try fileManager.removeItem(at: $0) }
        writeAtomically = { data, url in
            try data.write(to: url, options: .atomic)
        }
    }

    init(
        fileExists: @escaping (URL) -> Bool,
        read: @escaping (URL) throws -> Data,
        remove: @escaping (URL) throws -> Void,
        writeAtomically: @escaping (Data, URL) throws -> Void
    ) {
        self.fileExists = fileExists
        self.read = read
        self.remove = remove
        self.writeAtomically = writeAtomically
    }

    /// Returns the only store path the app may pass to NMP.
    ///
    /// Deletion precedes marker publication. A crash between those operations
    /// leaves no database and an old/missing marker, so the next launch safely
    /// retries. Marker read or store deletion failures stop launch without
    /// rewriting the marker or guessing that generic corruption is an epoch
    /// mismatch.
    func prepare(appDirectory: URL) throws -> String {
        let store = appDirectory.appendingPathComponent("nmp.redb")
        let marker = appDirectory.appendingPathComponent("nmp-store-epoch")
        let expected = Data("\(Self.current)\n".utf8)

        if fileExists(marker), try read(marker) == expected {
            return store.path
        }

        if fileExists(store) {
            try remove(store)
        }
        try writeAtomically(expected, marker)
        return store.path
    }
}
