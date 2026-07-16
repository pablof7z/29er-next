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
    var selectedHost: String?
    var selectedGroup: GroupCoordinate?
    var diagnostics = DiagnosticsSnapshot()
    var diagnosticsError: String?
    private(set) var activePubkey: String?
    private(set) var isSigningIn = false
    private(set) var identityError: String?

    private(set) var engine: NMPEngine?
    private(set) var contentObservationFactory: NMPReferenceObservationFactory?
    private(set) var engineGeneration = 0
    private var engineConfig: NMPConfig?
    private var localAccountStore: NMPInsecureFileAccountStore?
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
            let session = try AppEngineBootstrap.start(resources)
            engine = session.engine
            contentObservationFactory = .live(engine: session.engine)
            activePubkey = session.activePubkey
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
            groups = []
            hasReceivedGroups = false
            groupsError = nil
            remembered = .empty
            hasReceivedRememberedGroups = false
            rememberedGroupsError = nil
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

    func signIn(secretKey: String) async {
        guard let engine else {
            identityError = "NMP is not available."
            return
        }
        guard !isSigningIn else { return }

        isSigningIn = true
        identityError = nil
        defer { isSigningIn = false }

        do {
            let registration = try await engine.addAccount(secretKey: secretKey)
            let pubkey = registration.publicKey
            do {
                try engine.setActiveAccount(pubkey)
                activePubkey = pubkey
                remembered = .empty
                hasReceivedRememberedGroups = false
                rememberedGroupsError = nil
                selectedHost = nil
                selectedGroup = nil
            } catch {
                let message = Self.identityMessage(for: error)
                do {
                    try engine.clearPersistedAccount()
                    replaceWithReadOnlyEngine(identityError: message)
                } catch {
                    identityError = "NMP could not activate or clear the saved account."
                }
            }
        } catch {
            activePubkey = nil
            identityError = Self.identityMessage(for: error)
        }
    }

    @discardableResult
    func signOut() -> Bool {
        guard let engine else {
            identityError = "NMP is not available."
            return false
        }
        do {
            try engine.clearPersistedAccount()
            replaceWithReadOnlyEngine(identityError: nil)
            return true
        } catch {
            identityError = "NMP could not clear the saved account."
            return false
        }
    }

    func clearIdentityError() {
        identityError = nil
    }

    private func replaceWithReadOnlyEngine(identityError: String?) {
        let oldEngine = engine
        engine = nil
        contentObservationFactory = nil
        activePubkey = nil
        remembered = .empty
        hasReceivedRememberedGroups = false
        rememberedGroupsError = nil
        selectedHost = groupRelay
        selectedGroup = nil
        groups = []
        hasReceivedGroups = false
        groupsError = nil
        self.identityError = identityError
        state = .starting
        oldEngine?.shutdown()

        guard let engineConfig else {
            engine = nil
            state = .failed("NMP could not restart a read-only session.")
            engineGeneration &+= 1
            return
        }

        do {
            let engine = try NMPEngine(
                config: engineConfig,
                localAccountStore: localAccountStore
            )
            self.engine = engine
            contentObservationFactory = .live(engine: engine)
        } catch {
            engine = nil
            contentObservationFactory = nil
            state = .failed("NMP could not restart a read-only session.")
        }
        engineGeneration &+= 1
    }

    private static func identityMessage(for error: Error) -> String {
        switch error as? NMPError {
        case .invalidSecretKey:
            return "That secret key is not a valid nsec or secret hex key."
        default:
            return "NMP could not sign in this account."
        }
    }
}
