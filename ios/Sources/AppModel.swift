import Foundation
import NMP
import NMPUI
import Observation

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case starting
        case observing
        case failed(String)
    }

    private(set) var state: State = .starting
    var groups: [GroupSummary] = []
    var hasReceivedGroups = false
    var groupsError: String?
    var remembered = RememberedGroupSnapshot.empty
    var hasReceivedRememberedGroups = false
    var rememberedGroupsError: String?
    var favoriteRelayEditState = FavoriteRelayEditState.idle
    var savedRelays: [String]
    var selectedHost: String?
    var selectedGroup: GroupCoordinate?
    var diagnostics = DiagnosticsSnapshot()
    var diagnosticsError: String?
    var activePubkey: String?
    var isSigningIn = false
    var identityError: String?

    private(set) var engine: NMPEngine?
    private(set) var contentObservationFactory: NMPReferenceObservationFactory?
    private(set) var engineGeneration = 0
    private var engineConfig: NMPConfig?
    private var localAccountStore: (any NMPLocalAccountCheckpoint)?
    let favoriteRelayStore: FavoriteRelayStore
    var activeRegistration: NMPAccountRegistration?
    let groupRelay: String

    var favoriteRelays: [FavoriteRelayChoice] {
        FavoriteRelayChoice.favorites(
            defaultRelay: groupRelay,
            savedRelays: savedRelays,
            remembered: remembered
        )
    }

    var relayHosts: [String] { favoriteRelays.map(\.url) }

    var canResetLocalDatabase: Bool {
        engineConfig?.storePath != nil
    }

    init(
        fileManager: FileManager = .default,
        operatorConfiguration: OperatorConfiguration? = nil,
        applicationSupportURL: URL? = nil,
        accountStore: (any NMPLocalAccountCheckpoint)? = nil,
        favoriteRelayStore: FavoriteRelayStore = FavoriteRelayStore()
    ) {
        let storedRelays = favoriteRelayStore.load()
        let validatedRelays = storedRelays.compactMap {
            try? FavoriteRelayConfiguration.validatedRelay($0)
        }
        self.favoriteRelayStore = favoriteRelayStore
        savedRelays = validatedRelays
        if validatedRelays != storedRelays {
            favoriteRelayStore.save(validatedRelays)
        }
        let configuration: OperatorConfiguration
        if let operatorConfiguration {
            configuration = operatorConfiguration
        } else {
            switch OperatorConfiguration.bundled() {
            case .configured(let value):
                configuration = value
            case .invalid(let error):
                groupRelay = ""
                engine = nil
                contentObservationFactory = nil
                engineConfig = nil
                state = .failed(error.localizedDescription)
                return
            }
        }

        let proofOfflineRelay = RoomOpenProbe.shared.offlineRelay
        groupRelay = proofOfflineRelay ?? configuration.groupRelay
        do {
            let resources = try AppEngineBootstrap.resources(
                fileManager: fileManager,
                operatorConfiguration: configuration,
                applicationSupportURL: applicationSupportURL,
                relayOverride: proofOfflineRelay,
                savedRelays: savedRelays,
                accountStore: accountStore
            )
            engineConfig = resources.config
            localAccountStore = resources.accountStore
            let session = try AppEngineBootstrap.start(resources)
            engine = session.engine
            contentObservationFactory = .live(
                engine: session.engine,
                resolve: channelPreviewReferenceDemand
            )
            activePubkey = session.activePubkey
            selectedHost = relayHosts.first
        } catch {
            engine = nil
            contentObservationFactory = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Ask NMP to destroy its closed canonical store, then reconstruct the
    /// engine. The separately configured local-account checkpoint is retained
    /// so a saved account can be restored during reconstruction.
    @discardableResult
    func resetLocalDatabase() -> Bool {
        guard let engineConfig, let storePath = engineConfig.storePath else {
            state = .failed("NMP has no persistent local database to reset.")
            return false
        }

        let oldEngine = engine
        activeRegistration = nil
        engine = nil
        contentObservationFactory = nil
        activePubkey = nil
        oldEngine?.shutdown()

        do {
            try NMPEngine.resetPersistentStore(at: storePath)
            let engine = try NMPEngine(
                config: engineConfig,
                localAccountStore: localAccountStore
            )
            self.engine = engine
            contentObservationFactory = .live(
                engine: engine,
                resolve: channelPreviewReferenceDemand
            )
            activePubkey = try engine.activeAccount()
            groups = []
            hasReceivedGroups = false
            groupsError = nil
            remembered = .empty
            hasReceivedRememberedGroups = false
            rememberedGroupsError = nil
            favoriteRelayEditState = .idle
            selectedHost = relayHosts.first
            selectedGroup = nil
            diagnostics = DiagnosticsSnapshot()
            diagnosticsError = nil
            state = .starting
            engineGeneration &+= 1
            return true
        } catch {
            engine = nil
            contentObservationFactory = nil
            state = .failed("NMP could not reset the local database: \(error.localizedDescription)")
            engineGeneration &+= 1
            return false
        }
    }

    func run() async {
        guard let engine else { return }
        let generation = engineGeneration
        state = .observing

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.observeRememberedGroups(using: engine, generation: generation)
            }
            group.addTask { [weak self] in
                await self?.observeDiagnostics(using: engine, generation: generation)
            }
        }
    }

    func clearIdentityError() {
        identityError = nil
    }

    func rebuildEngine(selecting host: String?) {
        guard var configuration = engineConfig else {
            favoriteRelayEditState = .failed("NMP is not available.")
            return
        }
        configuration.appRelays = AppEngineBootstrap.configuredRelays(
            defaultRelay: groupRelay,
            savedRelays: savedRelays
        )
        engineConfig = configuration

        let oldEngine = engine
        activeRegistration = nil
        engine = nil
        contentObservationFactory = nil
        activePubkey = nil
        oldEngine?.shutdown()

        do {
            let engine = try NMPEngine(
                config: configuration,
                localAccountStore: localAccountStore
            )
            self.engine = engine
            contentObservationFactory = .live(engine: engine, resolve: channelPreviewReferenceDemand)
            activePubkey = try engine.activeAccount()
            groups = []
            hasReceivedGroups = false
            groupsError = nil
            remembered = .empty
            hasReceivedRememberedGroups = false
            rememberedGroupsError = nil
            selectedGroup = nil
            diagnostics = DiagnosticsSnapshot()
            diagnosticsError = nil
            selectedHost = HostGroupSelectionPolicy.reconciledHost(
                availableHosts: relayHosts,
                selectedHost: host
            )
            state = .starting
            engineGeneration &+= 1
        } catch {
            state = .failed(error.localizedDescription)
            engineGeneration &+= 1
        }
    }
}
