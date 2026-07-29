struct MessageReceiptPresentation: Equatable, Sendable {
    static let maximumActiveReceiptCount = 4

    private(set) var retainedStates: [UInt64: MessageDeliveryState] = [:]
    private(set) var completedRetainedStates: [UInt64: MessageDeliveryState] = [:]

    mutating func recordRetained(
        _ state: MessageDeliveryState,
        receiptID: UInt64
    ) {
        retainedStates[receiptID] = state
        Self.trim(&retainedStates)
    }

    mutating func completeRetained(
        _ state: MessageDeliveryState,
        receiptID: UInt64
    ) {
        retainedStates.removeValue(forKey: receiptID)
        completedRetainedStates[receiptID] = state
        Self.trim(&completedRetainedStates)
    }

    mutating func endRetainedObservation(receiptID: UInt64) {
        retainedStates.removeValue(forKey: receiptID)
    }

    mutating func clearCompletedRetainedState() {
        completedRetainedStates.removeAll()
    }

    func progressMessage(currentState: MessageDeliveryState) -> String? {
        if let currentProgress = currentState.progressMessage {
            return currentProgress
        }
        return retainedStates
            .sorted { $0.key > $1.key }
            .compactMap { $0.value.progressMessage }
            .first
    }

    func failureMessage(currentState: MessageDeliveryState) -> String? {
        let retained = retainedStates
            .sorted { $0.key < $1.key }
            .map { $0.value }
        let completed = completedRetainedStates
            .sorted { $0.key < $1.key }
            .map { $0.value }
        var messages: [String] = []
        for message in ([currentState] + completed + retained).compactMap(\.failureMessage)
            where !messages.contains(message) {
            messages.append(message)
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private static func trim(_ states: inout [UInt64: MessageDeliveryState]) {
        while states.count > Self.maximumActiveReceiptCount,
              let oldest = states.keys.min() {
            states.removeValue(forKey: oldest)
        }
    }
}
