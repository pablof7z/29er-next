import Foundation
import Observation

@MainActor
@Observable
final class VoiceProviderStore {
    private(set) var configurations: [VoiceProviderConfiguration]
    private(set) var activeConfigurationID: UUID

    private let defaults: UserDefaults
    private let credentials: VoiceCredentialStore
    private let configurationsKey = "voice.provider.configurations.v1"
    private let activeIDKey = "voice.provider.active-id.v1"

    init(
        defaults: UserDefaults = .standard,
        credentials: VoiceCredentialStore = VoiceCredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials
        let decoded = defaults.data(forKey: configurationsKey)
            .flatMap { try? JSONDecoder().decode([VoiceProviderConfiguration].self, from: $0) }
        let loaded = decoded?.isEmpty == false ? decoded! : [.builtInApple]
        configurations = loaded

        if let rawID = defaults.string(forKey: activeIDKey),
           let id = UUID(uuidString: rawID),
           loaded.contains(where: { $0.id == id }) {
            activeConfigurationID = id
        } else {
            activeConfigurationID = loaded[0].id
        }
        persist()
    }

    var activeConfiguration: VoiceProviderConfiguration {
        configurations.first(where: { $0.id == activeConfigurationID })
            ?? configurations[0]
    }

    var activeName: String { activeConfiguration.normalizedName }

    func configuration(id: UUID) -> VoiceProviderConfiguration? {
        configurations.first(where: { $0.id == id })
    }

    func add(_ kind: VoiceProviderKind) -> VoiceProviderConfiguration {
        let configuration = VoiceProviderConfiguration.new(kind)
        configurations.append(configuration)
        persist()
        return configuration
    }

    func save(
        _ configuration: VoiceProviderConfiguration,
        newCredential: String? = nil
    ) throws {
        guard !configuration.normalizedName.isEmpty else {
            throw VoiceProviderConfigurationError.missingName
        }
        if let newCredential, !newCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try credentials.setCredential(newCredential, for: configuration.id)
        }
        if let index = configurations.firstIndex(where: { $0.id == configuration.id }) {
            configurations[index] = configuration
        } else {
            configurations.append(configuration)
        }
        persist()
    }

    func activate(_ id: UUID) throws {
        guard let configuration = configuration(id: id) else {
            throw VoiceProviderConfigurationError.missingConfiguration
        }
        try validate(configuration)
        activeConfigurationID = id
        persist()
    }

    func delete(_ id: UUID) throws {
        guard id != activeConfigurationID else {
            throw VoiceProviderConfigurationError.activeConfigurationCannotBeDeleted
        }
        credentials.removeCredential(for: id)
        configurations.removeAll { $0.id == id }
        persist()
    }

    func snapshot() throws -> VoiceProviderSnapshot {
        let configuration = activeConfiguration
        try validate(configuration)
        return VoiceProviderSnapshot(
            configuration: configuration,
            credential: credentials.credential(for: configuration.id)
        )
    }

    func maskedCredential(for id: UUID) -> String? {
        credentials.maskedCredential(for: id)
    }

    func isReady(_ configuration: VoiceProviderConfiguration) -> Bool {
        (try? validate(configuration)) != nil
    }

    private func validate(_ configuration: VoiceProviderConfiguration) throws {
        guard !configuration.normalizedName.isEmpty else {
            throw VoiceProviderConfigurationError.missingName
        }
        if configuration.kind == .elevenLabs,
           credentials.credential(for: configuration.id) == nil {
            throw VoiceProviderConfigurationError.missingCredential
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: configurationsKey)
        }
        defaults.set(activeConfigurationID.uuidString, forKey: activeIDKey)
    }
}
