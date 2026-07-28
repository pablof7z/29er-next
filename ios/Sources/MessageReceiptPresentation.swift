struct MessageReceiptPresentation: Equatable, Sendable {
    private(set) var retainedStates: [UInt64: MessageDeliveryState] = [:]

    mutating func recordRetained(
        _ state: MessageDeliveryState,
        receiptID: UInt64
    ) {
        retainedStates[receiptID] = state
    }

    func progressMessage(currentState: MessageDeliveryState) -> String? {
        guard currentState == .idle else { return currentState.progressMessage }
        return retainedStates
            .sorted { $0.key > $1.key }
            .compactMap { $0.value.progressMessage }
            .first
    }

    func failureMessage(currentState: MessageDeliveryState) -> String? {
        let states = [currentState] + retainedStates
            .sorted { $0.key < $1.key }
            .map { $0.value }
        var messages: [String] = []
        for message in states.compactMap(\.failureMessage)
            where !messages.contains(message) {
            messages.append(message)
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
}
