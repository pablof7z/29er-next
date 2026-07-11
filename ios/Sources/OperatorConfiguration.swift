import Foundation

struct OperatorConfiguration: Sendable {
    enum LoadResult {
        case configured(OperatorConfiguration)
        case invalid(ConfigurationError)
    }

    enum ConfigurationError: LocalizedError {
        case missingIndexerRelays
        case missingGroupRelay

        var errorDescription: String? {
            switch self {
            case .missingIndexerRelays:
                return "The app has no NMP indexer relays configured."
            case .missingGroupRelay:
                return "The app has no NIP-29 group relay configured."
            }
        }
    }

    let indexerRelays: [String]
    let groupRelay: String

    static func bundled(_ bundle: Bundle = .main) -> LoadResult {
        guard let indexers = bundle.object(forInfoDictionaryKey: "NMPIndexerRelays") as? [String],
              !indexers.isEmpty else {
            return .invalid(.missingIndexerRelays)
        }
        guard let groupRelay = bundle.object(forInfoDictionaryKey: "NMPGroupRelay") as? String,
              !groupRelay.isEmpty else {
            return .invalid(.missingGroupRelay)
        }
        return .configured(OperatorConfiguration(indexerRelays: indexers, groupRelay: groupRelay))
    }
}
