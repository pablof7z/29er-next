import Foundation
import NMP

/// App-owned operator configuration: which relay hosts this installation may
/// browse. NMP owns the URL boundary, physical connection and every query
/// result; this store contains neither a relay session nor protocol data.
struct FavoriteRelayStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "favorite-relays.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String] {
        guard let stored = defaults.array(forKey: key) as? [String] else { return [] }
        var seen = Set<String>()
        return stored.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func save(_ relays: [String]) {
        defaults.set(relays, forKey: key)
    }
}

enum FavoriteRelayConfigurationError: Error, Equatable {
    case invalidRelay

    var message: String {
        "Enter a valid WebSocket relay URL, such as wss://relay.example."
    }
}

enum FavoriteRelayConfiguration {
    static func validatedRelay(_ input: String) throws -> String {
        let relay = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relay.isEmpty else { throw FavoriteRelayConfigurationError.invalidRelay }
        do {
            _ = try NMPRelayScope.on([relay])
            return relay
        } catch {
            throw FavoriteRelayConfigurationError.invalidRelay
        }
    }

    static func appending(_ relay: String, to savedRelays: [String]) -> [String] {
        savedRelays.contains(relay) ? savedRelays : savedRelays + [relay]
    }

    static func removing(_ relay: String, from savedRelays: [String]) -> [String] {
        savedRelays.filter { $0 != relay }
    }
}

enum FavoriteRelayEditState: Equatable {
    case idle
    case failed(String)

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

@MainActor
extension AppModel {
    func addFavoriteRelay(_ input: String) {
        do {
            let relay = try FavoriteRelayConfiguration.validatedRelay(input)
            let updated = FavoriteRelayConfiguration.appending(relay, to: savedRelays)
            guard updated != savedRelays else {
                selectedHost = relay
                return
            }
            savedRelays = updated
            favoriteRelayStore.save(updated)
            favoriteRelayEditState = .idle
            rebuildEngine(selecting: relay)
        } catch let error as FavoriteRelayConfigurationError {
            favoriteRelayEditState = .failed(error.message)
        } catch {
            favoriteRelayEditState = .failed("The relay could not be added.")
        }
    }

    func removeFavoriteRelay(_ relay: String) {
        guard savedRelays.contains(relay) else { return }
        let updated = FavoriteRelayConfiguration.removing(relay, from: savedRelays)
        savedRelays = updated
        favoriteRelayStore.save(updated)
        favoriteRelayEditState = .idle
        rebuildEngine(selecting: selectedHost == relay ? nil : selectedHost)
    }

    func clearFavoriteRelayError() {
        favoriteRelayEditState = .idle
    }
}
