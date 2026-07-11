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
    private(set) var coverage: Coverage = .unknown
    private(set) var diagnostics = DiagnosticsSnapshot()

    let engine: NMPEngine?
    private var isRunning = false
    let groupRelay: String

    init(
        fileManager: FileManager = .default,
        operatorConfiguration: OperatorConfiguration? = nil
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
                state = .failed(error.localizedDescription)
                return
            }
        }

        groupRelay = configuration.groupRelay
        do {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDirectory = support.appendingPathComponent("29er-next", isDirectory: true)
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            engine = try NMPEngine(
                config: NMPConfig(
                    storePath: appDirectory.appendingPathComponent("nmp.redb").path,
                    indexerRelays: configuration.indexerRelays,
                    appRelays: [configuration.groupRelay]
                )
            )
        } catch {
            engine = nil
            state = .failed(error.localizedDescription)
        }
    }

    func run() async {
        guard let engine, !isRunning else { return }
        isRunning = true
        state = .observing
        defer { isRunning = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.observeGroups(using: engine)
            }
            group.addTask { [weak self] in
                await self?.observeDiagnostics(using: engine)
            }
        }
    }

    var relayCount: Int {
        diagnostics.relays.count
    }

    var activeSubscriptionCount: UInt32 {
        diagnostics.relays.reduce(0) { $0 + $1.wireSubCount }
    }

    private func observeGroups(using engine: NMPEngine) async {
        do {
            let query = try engine.observe(NMPFilter(kinds: [39_000], limit: 250))
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                groups = NIP29ViewProjection.groups(from: batch.rows)
                coverage = batch.coverage
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func observeDiagnostics(using engine: NMPEngine) async {
        let observation = engine.observeDiagnostics()
        defer { observation.cancel() }

        for await snapshot in observation {
            guard !Task.isCancelled else { return }
            diagnostics = snapshot
        }
    }
}
