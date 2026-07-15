import Foundation
import NMP
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
    private(set) var groups: [GroupSummary] = []
    private(set) var diagnostics = DiagnosticsSnapshot()
    private(set) var diagnosticsError: String?
    private(set) var activePubkey: String?
    private(set) var isSigningIn = false
    private(set) var identityError: String?

    private(set) var engine: NMPEngine?
    private(set) var engineGeneration = 0
    private var engineConfig: NMPConfig?
    let groupRelay: String

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
                engineConfig = nil
                state = .failed(error.localizedDescription)
                return
            }
        }

        let proofRelay = RoomOpenProbe.shared.offlineRelay
        groupRelay = proofRelay ?? configuration.groupRelay
        do {
            let support: URL
            if let applicationSupportURL {
                support = applicationSupportURL
            } else {
                support = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            }
            let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            let engineConfig = NMPConfig(
                storePath: appDirectory.appendingPathComponent("nmp.redb").path,
                indexerRelays: proofRelay == nil ? configuration.indexerRelays : [],
                appRelays: [groupRelay]
            )
            self.engineConfig = engineConfig
            engine = try NMPEngine(config: engineConfig)
        } catch {
            engine = nil
            engineConfig = nil
            state = .failed(error.localizedDescription)
        }
    }

    func run() async {
        guard let engine else { return }
        let generation = engineGeneration
        state = .observing

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.observeGroups(using: engine, generation: generation)
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
            let pubkey = try await engine.addAccount(secretKey: secretKey)
            do {
                try engine.setActiveAccount(pubkey)
                activePubkey = pubkey
            } catch {
                replaceWithReadOnlyEngine(identityError: Self.identityMessage(for: error))
            }
        } catch {
            activePubkey = nil
            identityError = Self.identityMessage(for: error)
        }
    }

    func endIdentitySession() {
        replaceWithReadOnlyEngine(identityError: nil)
    }

    func clearIdentityError() {
        identityError = nil
    }

    private func observeGroups(using engine: NMPEngine, generation: Int) async {
        do {
            var demand = try groupDiscoveryDemand(host: groupRelay)
            demand.selection.limit = 250
            let query = try await openNMPQuery(
                engine: engine,
                demand: demand
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled, generation == engineGeneration else { return }
                groups = GroupDirectoryProjection.groups(from: batch.rows, hostRelay: groupRelay)
            }
        } catch {
            if generation == engineGeneration {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func observeDiagnostics(using engine: NMPEngine, generation: Int) async {
        do {
            let observation = try engine.observeDiagnostics()
            defer { observation.cancel() }

            for await snapshot in observation {
                guard !Task.isCancelled, generation == engineGeneration else { return }
                diagnostics = snapshot
                diagnosticsError = nil
            }
        } catch {
            guard !Task.isCancelled, generation == engineGeneration else { return }
            diagnosticsError = error.localizedDescription
        }
    }

    private func replaceWithReadOnlyEngine(identityError: String?) {
        let oldEngine = engine
        engine = nil
        activePubkey = nil
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
            engine = try NMPEngine(config: engineConfig)
        } catch {
            engine = nil
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
