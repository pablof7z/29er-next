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
    var selectedHost: String?
    var selectedGroup: GroupCoordinate?
    var diagnostics = DiagnosticsSnapshot()
    var diagnosticsError: String?
    var activePubkey: String?
    var isSigningIn = false
    var identityError: String?
    var generatedIdentityProfile: GeneratedIdentityProfile?

    private(set) var engine: NMPEngine?
    private(set) var contentObservationFactory: NMPReferenceObservationFactory?
    private(set) var engineGeneration = 0
    private var engineConfig: NMPConfig?
    private var localAccountStore: NMPInsecureFileAccountStore?
    var generatedProfileStore: GeneratedIdentityProfileStore?
    var activeRegistration: NMPAccountRegistration?
    var profilePublishTask: Task<Void, Never>?
    let groupRelay: String

    var canResetLocalDatabase: Bool {
        engineConfig?.storePath != nil
    }

    init(
        fileManager: FileManager = .default,
        operatorConfiguration: OperatorConfiguration? = nil,
        applicationSupportURL: URL? = nil
    ) {
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
                relayOverride: proofOfflineRelay
            )
            engineConfig = resources.config
            localAccountStore = resources.accountStore
            generatedProfileStore = resources.generatedProfileStore
            let session = try AppEngineBootstrap.start(resources)
            engine = session.engine
            contentObservationFactory = .live(engine: session.engine)
            activePubkey = session.activePubkey
            generatedIdentityProfile = resources.generatedProfileStore.load(matching: session.activePubkey)
            selectedHost = session.activePubkey == nil ? groupRelay : nil
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
        profilePublishTask?.cancel()
        profilePublishTask = nil
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
            contentObservationFactory = .live(engine: engine)
            activePubkey = try engine.activeAccount()
            generatedIdentityProfile = generatedProfileStore?.load(matching: activePubkey)
            groups = []
            hasReceivedGroups = false
            groupsError = nil
            remembered = .empty
            hasReceivedRememberedGroups = false
            rememberedGroupsError = nil
            favoriteRelayEditState = .idle
            selectedHost = activePubkey == nil ? groupRelay : nil
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
        guard await ensureIdentity() else {
            state = .failed(identityError ?? "NMP could not create a default identity.")
            return
        }
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
}
