import Foundation
import NMP

struct AppEngineResources {
    let config: NMPConfig
    let accountStore: any NMPLocalAccountCheckpoint
}

struct AppEngineSession {
    let engine: NMPEngine
    let activePubkey: String?
}

enum AppEngineBootstrap {
    /// The plaintext checkpoint this app used to write. Deleted on every
    /// launch: it is a secret key in a readable app-sandbox file, and leaving
    /// it there once the Keychain holds the live copy would be strictly worse
    /// than either one alone.
    static let legacyPlaintextAccountFile = "local-account.nsec"

    static func resources(
        fileManager: FileManager,
        operatorConfiguration: OperatorConfiguration,
        applicationSupportURL: URL?,
        relayOverride: String? = nil,
        accountStore: (any NMPLocalAccountCheckpoint)? = nil
    ) throws -> AppEngineResources {
        let support = try applicationSupportURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        // NMP owns store compatibility and explicit reset. The app names the
        // one file it keeps and nothing else: it does not read a schema
        // marker, does not decide that a store is stale, and does not delete
        // it behind the person using it. When NMP cannot open the store,
        // `DatabaseRecoveryView` asks, and `NMPEngine.resetPersistentStore`
        // does it.
        let storePath = appDirectory.appendingPathComponent("nmp.redb").path
        let groupRelay = relayOverride ?? operatorConfiguration.groupRelay
        let config = NMPConfig(
            storePath: storePath,
            appRelays: [groupRelay],
            fallbackRelays: relayOverride == nil ? operatorConfiguration.indexerRelays : []
        )

        removeLegacyPlaintextAccount(in: appDirectory, fileManager: fileManager)

        // NMP's recommended secure checkpoint, shipped in this same build and
        // previously unused: `kSecClassGenericPassword` under
        // `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced to
        // iCloud Keychain and never carried into a device migration. It is a
        // drop-in `NMPLocalAccountCheckpoint`, so nothing but the type
        // changes here.
        return AppEngineResources(
            config: config,
            accountStore: accountStore ?? NMPKeychainAccountStore()
        )
    }

    /// Delete the old plaintext checkpoint if one is still on disk.
    ///
    /// Deliberately NOT a migration. Copying the secret out of the file into
    /// the Keychain would keep existing sessions alive, but it is a
    /// compatibility path this repo does not keep, and the honest reading of
    /// a plaintext key on disk is that it should stop existing rather than be
    /// promoted. Anyone signed in before this change signs in once more.
    private static func removeLegacyPlaintextAccount(
        in appDirectory: URL,
        fileManager: FileManager
    ) {
        let legacy = appDirectory.appendingPathComponent(legacyPlaintextAccountFile)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        try? fileManager.removeItem(at: legacy)
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
