import Foundation
import NMP
import NMPContent

struct AppEngineResources {
    let config: NMPConfig
    let accountStore: NMPInsecureFileAccountStore
}

struct AppEngineSession {
    let engine: NMPEngine
    let contentClient: NMPContentClient
    let activePubkey: String?
}

enum AppEngineBootstrap {
    static func resources(
        fileManager: FileManager,
        operatorConfiguration: OperatorConfiguration,
        applicationSupportURL: URL?
    ) throws -> AppEngineResources {
        let support = try applicationSupportURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        let config = NMPConfig(
            storePath: appDirectory.appendingPathComponent("nmp.redb").path,
            indexerRelays: operatorConfiguration.indexerRelays,
            appRelays: [operatorConfiguration.groupRelay]
        )
        let accountStore = NMPInsecureFileAccountStore(
            fileURL: appDirectory.appendingPathComponent("local-account.nsec")
        )
        return AppEngineResources(config: config, accountStore: accountStore)
    }

    static func start(_ resources: AppEngineResources) throws -> AppEngineSession {
        let engine = try NMPEngine(
            config: resources.config,
            localAccountStore: resources.accountStore
        )
        return AppEngineSession(
            engine: engine,
            contentClient: NMPContentClient(engine: engine),
            activePubkey: try engine.activeAccount()
        )
    }
}
