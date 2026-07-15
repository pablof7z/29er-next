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

@MainActor
extension AppModel {
    func addFavoriteRelay(_ relay: String) {
        startFavoriteRelayAction { $0.addSimpleGroupRelay(relay) }
    }

    func removeFavoriteRelay(_ relay: String) {
        startFavoriteRelayAction { $0.removeSimpleGroupRelay(relay) }
    }

    func clearFavoriteRelayError() {
        if case .failed = favoriteRelayEditState {
            favoriteRelayEditState = .idle
        }
    }

    private func startFavoriteRelayAction(
        _ action: (NMPEngine) -> NMPRelayListAction
    ) {
        guard !favoriteRelayEditState.isWorking else { return }
        guard activePubkey != nil, let engine else {
            favoriteRelayEditState = .failed("Sign in to edit your favorite relays.")
            return
        }

        favoriteRelayEditState = .working
        let generation = engineGeneration
        let relayAction = action(engine)
        Task { [weak self] in
            var failure: String?
            for await status in relayAction.status {
                if let message = Self.favoriteRelayFailureMessage(for: status) {
                    failure = message
                }
            }
            guard let self, self.engineGeneration == generation else { return }
            self.favoriteRelayEditState = failure.map(FavoriteRelayEditState.failed) ?? .idle
        }
    }

    static func favoriteRelayFailureMessage(
        for status: NMPRelayListActionStatus
    ) -> String? {
        switch status {
        case .acquiring, .noChange:
            return nil
        case .failed(let failure):
            return relayActionFailureMessage(failure)
        case .receipt(_, let writeStatus):
            return relayWriteFailureMessage(writeStatus)
        }
    }

    private static func relayActionFailureMessage(
        _ failure: NMPRelayListActionFailure
    ) -> String {
        switch failure {
        case .invalidRelay:
            return "Enter a valid WebSocket relay URL, such as wss://relay.example."
        case .signedOut:
            return "Sign in to edit your favorite relays."
        case .accountChanged:
            return "The active account changed before the relay list could be updated."
        case .acquisitionTimedOut, .cachedOnly:
            return "NMP could not confirm the current relay list from its sources. Try again when connected."
        case .sourceUnavailable:
            return "The sources for your relay list are unavailable."
        case .baseHasWrongAuthor, .baseHasWrongKind, .invalidGeneratedTag:
            return "NMP refused an invalid relay-list replacement."
        case .timestampExhausted:
            return "NMP could not create a newer relay-list revision."
        case .engineClosed:
            return "NMP closed before the relay list could be updated."
        case .receiptUnavailable:
            return "NMP could not create a durable write receipt."
        case .threadUnavailable, .executorSaturated:
            return "NMP is busy and could not start the relay-list update."
        }
    }

    private static func relayWriteFailureMessage(_ status: WriteStatus) -> String? {
        switch status {
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
}
