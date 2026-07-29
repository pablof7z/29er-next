import Foundation
import NMP

struct NMPStoreIdentity {
    private enum Phase: String, Codable {
        case ready
        case resetting
    }

    private struct Marker: Codable {
        let version: Int
        let generation: String
        let phase: Phase
    }

    private static let markerVersion = 1
    private let fileExists: (URL) -> Bool
    private let read: (URL) throws -> Data
    private let resetStore: (String) throws -> Void
    private let writeDurably: (Data, URL) throws -> Void

    init(fileManager: FileManager = .default) {
        fileExists = { fileManager.fileExists(atPath: $0.path) }
        read = { try Data(contentsOf: $0) }
        resetStore = { try NMPEngine.resetPersistentStore(at: $0) }
        writeDurably = { data, url in
            try CrashSafeFile.replace(data, at: url, fileManager: fileManager)
        }
    }

    init(
        fileExists: @escaping (URL) -> Bool,
        read: @escaping (URL) throws -> Data,
        resetStore: @escaping (String) throws -> Void,
        writeDurably: @escaping (Data, URL) throws -> Void
    ) {
        self.fileExists = fileExists
        self.read = read
        self.resetStore = resetStore
        self.writeDurably = writeDurably
    }

    func prepare(appDirectory: URL, storePath: String) throws -> String {
        let url = markerURL(appDirectory)
        guard fileExists(url) else {
            let generation = UUID().uuidString.lowercased()
            try write(.ready, generation: generation, to: url)
            return generation
        }

        let marker = try JSONDecoder().decode(Marker.self, from: read(url))
        guard marker.version == Self.markerVersion else {
            throw NMPStoreIdentityError.unsupportedVersion(marker.version)
        }
        guard !marker.generation.isEmpty else {
            throw NMPStoreIdentityError.invalidGeneration
        }
        switch marker.phase {
        case .ready:
            return marker.generation
        case .resetting:
            try resetStore(storePath)
            try write(.ready, generation: marker.generation, to: url)
            return marker.generation
        }
    }

    func beginReset(appDirectory: URL) throws -> String {
        let generation = UUID().uuidString.lowercased()
        try write(.resetting, generation: generation, to: markerURL(appDirectory))
        return generation
    }

    func completeReset(appDirectory: URL, generation: String) throws {
        try write(.ready, generation: generation, to: markerURL(appDirectory))
    }

    private func write(_ phase: Phase, generation: String, to url: URL) throws {
        let marker = Marker(
            version: Self.markerVersion,
            generation: generation,
            phase: phase
        )
        try writeDurably(JSONEncoder().encode(marker), url)
    }

    private func markerURL(_ appDirectory: URL) -> URL {
        appDirectory.appendingPathComponent("nmp-store-identity.json")
    }
}

enum NMPStoreIdentityError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidGeneration

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported NMP store identity marker version \(version)."
        case .invalidGeneration:
            return "The NMP store identity marker has no generation."
        }
    }
}
