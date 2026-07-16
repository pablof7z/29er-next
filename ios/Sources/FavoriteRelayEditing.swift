import Foundation
import NMP

enum FavoriteRelayEditState: Equatable {
    case idle
    case working
    case failed(String)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

enum FavoriteRelayListOperation: Equatable {
    case add(String)
    case remove(String)
}

enum FavoriteRelayListEditError: Error, Equatable {
    case invalidRelay
    case timestampExhausted

    var message: String {
        switch self {
        case .invalidRelay:
            return "Enter a valid WebSocket relay URL, such as wss://relay.example."
        case .timestampExhausted:
            return "The existing relay list has an invalid timestamp and cannot be replaced."
        }
    }
}

enum FavoriteRelayListEditor {
    static func intent(
        operation: FavoriteRelayListOperation,
        activePubkey: String,
        sourceEvent: FavoriteRelayListEvent?,
        now: UInt64
    ) throws -> WriteIntent? {
        let input: String
        switch operation {
        case .add(let relay), .remove(let relay): input = relay
        }
        let relay = try canonicalRelay(input)
        let existingTags = sourceEvent?.tags ?? []
        let tags: [[String]]

        switch operation {
        case .add:
            guard !existingTags.contains(where: { matches($0, relay: relay) }) else {
                return nil
            }
            tags = existingTags + [["r", relay]]
        case .remove:
            tags = existingTags.filter { !matches($0, relay: relay) }
            guard tags.count != existingTags.count else { return nil }
        }

        let createdAt = try nextTimestamp(now: now, after: sourceEvent?.createdAt)
        return WriteIntent(
            payload: .unsigned(
                pubkey: activePubkey,
                createdAt: createdAt,
                kind: 10_009,
                tags: tags,
                content: sourceEvent?.content ?? ""
            ),
            durability: .durable,
            routing: .authorOutbox
        )
    }

    private static func matches(_ tag: [String], relay: String) -> Bool {
        guard tag.count >= 2, tag[0] == "r",
              let existing = try? canonicalRelay(tag[1]) else { return false }
        return existing == relay
    }

    private static func canonicalRelay(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            throw FavoriteRelayListEditError.invalidRelay
        }
        components.scheme = scheme
        components.host = host.lowercased()
        guard let canonical = components.url?.absoluteString else {
            throw FavoriteRelayListEditError.invalidRelay
        }
        return canonical
    }

    private static func nextTimestamp(now: UInt64, after base: UInt64?) throws -> UInt64 {
        guard let base else { return now }
        guard base < UInt64.max else {
            throw FavoriteRelayListEditError.timestampExhausted
        }
        return max(now, base + 1)
    }
}

@MainActor
extension AppModel {
    func addFavoriteRelay(_ relay: String) {
        startFavoriteRelayEdit(.add(relay))
    }

    func removeFavoriteRelay(_ relay: String) {
        startFavoriteRelayEdit(.remove(relay))
    }

    func clearFavoriteRelayError() {
        if case .failed = favoriteRelayEditState {
            favoriteRelayEditState = .idle
        }
    }

    private func startFavoriteRelayEdit(_ operation: FavoriteRelayListOperation) {
        guard !favoriteRelayEditState.isWorking else { return }
        guard let activePubkey, let engine else {
            favoriteRelayEditState = .failed("Sign in to edit your favorite relays.")
            return
        }

        let intent: WriteIntent
        do {
            guard let composed = try FavoriteRelayListEditor.intent(
                operation: operation,
                activePubkey: activePubkey,
                sourceEvent: remembered.sourceEvent,
                now: UInt64(Date().timeIntervalSince1970)
            ) else {
                favoriteRelayEditState = .idle
                return
            }
            intent = composed
        } catch let error as FavoriteRelayListEditError {
            favoriteRelayEditState = .failed(error.message)
            return
        } catch {
            favoriteRelayEditState = .failed("The relay-list update could not be prepared.")
            return
        }

        favoriteRelayEditState = .working
        let generation = engineGeneration
        Task { [weak self] in
            var failure: String?
            do {
                let receipt = try await engine.publish(intent)
                for await status in receipt.status {
                    if let message = Self.favoriteRelayFailureMessage(for: status) {
                        failure = message
                    }
                }
            } catch {
                failure = Self.favoriteRelayPublishFailureMessage(error)
            }
            guard let self, self.engineGeneration == generation else { return }
            self.favoriteRelayEditState = failure.map(FavoriteRelayEditState.failed) ?? .idle
        }
    }

    static func favoriteRelayFailureMessage(for status: WriteStatus) -> String? {
        switch status {
        case .cancelled:
            return "The relay-list update was cancelled."
        case .rejected(_, let reason):
            return "The relay rejected the updated list: \(reason)"
        case .gaveUp:
            return "NMP could not deliver the updated relay list."
        case .outcomeUnknown:
            return "The relay-list delivery outcome is unknown."
        case .replaceableConflict:
            return "Your relay list changed during this update. Review it and try again."
        case .failed(let reason):
            return "NMP could not update the relay list: \(reason)"
        case .accepted, .awaitingCapability, .signed, .routed, .awaitingRelay,
             .awaitingAuth, .retryEligible, .handoffAmbiguous, .sent, .acked,
             .persistenceBlocked, .routePersistenceBlocked:
            return nil
        }
    }

    private static func favoriteRelayPublishFailureMessage(_ error: Error) -> String {
        switch error as? NMPError {
        case .noActiveAccount, .noActiveSigner:
            return "Sign in to edit your favorite relays."
        case .engineClosed:
            return "NMP closed before the relay list could be updated."
        case .executorSaturated, .threadUnavailable:
            return "NMP is busy and could not start the relay-list update."
        default:
            return "NMP could not start the relay-list update."
        }
    }
}
