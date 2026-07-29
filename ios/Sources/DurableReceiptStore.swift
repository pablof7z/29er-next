import CryptoKit
import Foundation

@MainActor
protocol ReceiptRecoveryStoring {
    func reserveCorrelation(_ correlation: String, maximumCount: Int) throws
    func replaceCorrelation(_ correlation: String, with receiptID: UInt64) throws
    func removeCorrelation(_ correlation: String) throws
}

enum ReceiptRecoveryCapacityError: LocalizedError, Equatable {
    case full(maximumCount: Int)

    var errorDescription: String? {
        switch self {
        case .full(let maximumCount):
            return "NMP receipt recovery is already observing its \(maximumCount)-write limit."
        }
    }
}

@MainActor
struct DurableReceiptStore: ReceiptRecoveryStoring {
    enum Scope: String {
        case message
        case reaction
    }

    private struct State: Codable {
        var receiptIDs: [UInt64] = []
        var correlations: [String] = []

        mutating func normalize() {
            receiptIDs = Array(Set(receiptIDs)).sorted()
            correlations = Array(Set(correlations)).sorted()
        }
    }

    private static let directoryName = "receipt-recovery"
    private let fileManager: FileManager
    private let root: URL
    private let recoveryDirectory: URL
    private let directory: URL
    private let fileURL: URL

    init(
        rootDirectory: URL? = nil,
        storeGeneration: String,
        scope: Scope,
        account: String,
        host: String,
        groupID: String,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        root = rootDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("29er-next", isDirectory: true)
        recoveryDirectory = root.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
        directory = recoveryDirectory
            .appendingPathComponent(storeGeneration, isDirectory: true)
        let identity = "\(scope.rawValue)|\(account)|\(host)|\(groupID)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        fileURL = directory.appendingPathComponent("\(digest).json")
    }

    func loadReceiptIDs() throws -> [UInt64] {
        try load().receiptIDs
    }

    func loadCorrelations() throws -> [String] {
        try load().correlations
    }

    func recordReceiptID(_ receiptID: UInt64) throws {
        try mutate { $0.receiptIDs.append(receiptID) }
    }

    func reserveCorrelation(_ correlation: String, maximumCount: Int) throws {
        var state = try load()
        guard !state.correlations.contains(correlation) else { return }
        guard state.receiptIDs.count + state.correlations.count < maximumCount else {
            throw ReceiptRecoveryCapacityError.full(maximumCount: maximumCount)
        }
        state.correlations.append(correlation)
        try persist(state)
    }

    func replaceCorrelation(_ correlation: String, with receiptID: UInt64) throws {
        try mutate {
            $0.correlations.removeAll { $0 == correlation }
            $0.receiptIDs.append(receiptID)
        }
    }

    func removeReceiptID(_ receiptID: UInt64) throws {
        try mutate { $0.receiptIDs.removeAll { $0 == receiptID } }
    }

    func removeCorrelation(_ correlation: String) throws {
        try mutate { $0.correlations.removeAll { $0 == correlation } }
    }

    var recoveryIdentityCount: Int {
        get throws {
            let state = try load()
            return state.receiptIDs.count + state.correlations.count
        }
    }

    static func pruneGenerations(
        rootDirectory: URL? = nil,
        keeping storeGeneration: String,
        fileManager: FileManager = .default
    ) throws {
        let root = rootDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("29er-next", isDirectory: true)
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for entry in entries where entry.lastPathComponent != storeGeneration {
            try fileManager.removeItem(at: entry)
        }
        try CrashSafeFile.synchronizeDirectory(directory)
    }

    private func load() throws -> State {
        guard fileManager.fileExists(atPath: fileURL.path) else { return State() }
        var state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
        state.normalize()
        return state
    }

    private func mutate(_ change: (inout State) -> Void) throws {
        var state = try load()
        change(&state)
        try persist(state)
    }

    private func persist(_ candidate: State) throws {
        var state = candidate
        state.normalize()
        if state.receiptIDs.isEmpty, state.correlations.isEmpty {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
            try CrashSafeFile.synchronizeDirectory(directory)
            return
        }
        let rootExists = fileManager.fileExists(atPath: root.path)
        let recoveryDirectoryExists = fileManager.fileExists(
            atPath: recoveryDirectory.path
        )
        let directoryExists = fileManager.fileExists(atPath: directory.path)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !rootExists {
            try CrashSafeFile.synchronizeDirectory(root.deletingLastPathComponent())
        }
        if !recoveryDirectoryExists {
            try CrashSafeFile.synchronizeDirectory(root)
        }
        if !directoryExists {
            try CrashSafeFile.synchronizeDirectory(recoveryDirectory)
        }
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        try CrashSafeFile.replace(
            JSONEncoder().encode(state),
            at: fileURL,
            fileManager: fileManager
        )
    }
}
