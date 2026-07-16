import NMP

enum ChatHistoryLoadState: Equatable {
    case ready
    case loading
    case noRowsReturned
    case atBound(max: UInt64)
    case failed(String)
}

struct ChatHistoryPaging: Equatable {
    private(set) var targetRows: UInt64
    private(set) var state = ChatHistoryLoadState.ready

    let pageSize: UInt64
    let maxRows: UInt64

    init(
        initialRows: UInt64 = RoomChatWindow.initialRows,
        pageSize: UInt64 = RoomChatWindow.pageSize,
        maxRows: UInt64 = RoomChatWindow.maxRows
    ) {
        targetRows = initialRows
        self.pageSize = pageSize
        self.maxRows = maxRows
    }

    var proposedTarget: UInt64? {
        guard state != .loading, targetRows < maxRows else { return nil }
        return min(targetRows + pageSize, maxRows)
    }

    mutating func acceptedRequest(target: UInt64) {
        targetRows = min(max(target, targetRows), maxRows)
        state = .loading
    }

    mutating func receive(_ load: WindowLoad?) {
        guard let load else { return }
        switch load {
        case .idle:
            if state != .loading { state = .ready }
        case .requesting:
            state = .loading
        case .returned(let added):
            if targetRows >= maxRows {
                state = .atBound(max: maxRows)
            } else {
                state = added == 0 ? .noRowsReturned : .ready
            }
        case .atBound(let max):
            state = .atBound(max: max)
        }
    }

    mutating func fail(_ message: String) {
        state = .failed(message)
    }
}
