import Foundation
import NMP

struct AppEngineResources {
    let config: NMPConfig
    let accountStore: NMPInsecureFileAccountStore
    let appDirectory: URL
    let storeGeneration: String
}

struct AppEngineSession {
    let engine: NMPEngine
    let activePubkey: String?
}

enum AppEngineBootstrap {
    @MainActor
    static func resources(
        fileManager: FileManager,
        operatorConfiguration: OperatorConfiguration,
        applicationSupportURL: URL?,
        relayOverride: String? = nil
    ) throws -> AppEngineResources {
        let support = try applicationSupportURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        let storePath = appDirectory.appendingPathComponent("nmp.redb").path
        let storeIdentity = NMPStoreIdentity(fileManager: fileManager)
        var storeGeneration = try storeIdentity.prepare(
            appDirectory: appDirectory,
            storePath: storePath
        )
        var replacementGeneration: String?
        let preparedStorePath = try NMPStoreEpoch(fileManager: fileManager)
            .prepare(appDirectory: appDirectory) {
                replacementGeneration = try storeIdentity.beginReset(
                    appDirectory: appDirectory
                )
            }
        if let replacementGeneration {
            try storeIdentity.completeReset(
                appDirectory: appDirectory,
                generation: replacementGeneration
            )
            storeGeneration = replacementGeneration
        }
        try DurableReceiptStore.pruneGenerations(
            rootDirectory: appDirectory,
            keeping: storeGeneration,
            fileManager: fileManager
        )
        let groupRelay = relayOverride ?? operatorConfiguration.groupRelay
        let config = NMPConfig(
            storePath: preparedStorePath,
            indexerRelays: relayOverride == nil ? operatorConfiguration.indexerRelays : [],
            appRelays: [groupRelay]
        )
        let accountStore = NMPInsecureFileAccountStore(
            fileURL: appDirectory.appendingPathComponent("local-account.nsec")
        )
        return AppEngineResources(
            config: config,
            accountStore: accountStore,
            appDirectory: appDirectory,
            storeGeneration: storeGeneration
        )
    }

    static func start(_ resources: AppEngineResources) throws -> AppEngineSession {
        let engine = try NMPEngine(
            config: resources.config,
            localAccountStore: resources.accountStore
        )
        return AppEngineSession(
            engine: engine,
            activePubkey: try engine.activeAccount()
        )
    }
}
