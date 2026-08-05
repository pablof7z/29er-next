import Foundation
import NMP

/// There is no working state: `publish` returning is acceptance, so the
/// edited list is already in NMP's store and already in the query this sheet
/// renders. What is left is whether the write later settled badly.
enum FavoriteRelayEditState: Equatable {
    case idle
    case failed(String)

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
            payload: .event(
                kind: 10_009,
                tags: tags,
                content: sourceEvent?.content ?? "",
                createdAt: createdAt
            ),
            // `.auto` -- which strategy claims kind:10009 is NMP's business,
            // decided at send time. There is no `.authorOutbox` any more and
            // naming a strategy here was always the app guessing.
            routing: .auto,
            identity: .explicit(pubkey: activePubkey)
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

        favoriteRelayEditState = .idle
        let generation = engineGeneration
        Task { [weak self] in
            let receipt: Receipt
            do {
                receipt = try await engine.publish(intent)
            } catch {
                guard let self, self.engineGeneration == generation else { return }
                self.favoriteRelayEditState = .failed(
                    WriteFailureText.startFailure(error, action: "relay-list update")
                )
                return
            }
            // Accepted. The new list is in the store and this sheet's query
            // will carry it; nothing is waiting on what follows. A stale
            // compare-and-swap now arrives HERE -- `WriteOutcome.refused` --
            // rather than as a throw from `publish`.
            guard let failure = await Self.favoriteRelayFailure(draining: receipt.status),
                  let self, self.engineGeneration == generation else { return }
            self.favoriteRelayEditState = .failed(failure)
        }
    }

    static func favoriteRelayFailure<Facts: AsyncSequence & Sendable>(
        draining facts: Facts
    ) async -> String? where Facts.Element == WriteFact {
        await WriteReport.failure(draining: facts, subject: "relay list")
    }
}
