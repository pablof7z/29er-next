struct RoomDirectoryEntry: Hashable, Sendable {
    var latest: RoomMessage?
    var unread: Int
}

struct ScopedRoomMessage: Hashable, Sendable {
    let groupID: String
    let message: RoomMessage
}

enum RoomDirectoryProjection {
    static let maximumBaselines = 1_000

    struct Snapshot: Equatable, Sendable {
        let entries: [String: RoomDirectoryEntry]
        let latestByGroup: [String: RoomMessage]
        let timesByGroup: [String: [UInt64]]
        let baselines: [String: UInt64]
    }

    static func snapshot(
        messages: [ScopedRoomMessage],
        baselines: [String: UInt64],
        now: UInt64
    ) -> Snapshot {
        var latestByGroup: [String: RoomMessage] = [:]
        var timesByGroup: [String: [UInt64]] = [:]

        for scoped in messages {
            let groupID = scoped.groupID
            let message = scoped.message
            timesByGroup[groupID, default: []].append(message.createdAt)

            guard let current = latestByGroup[groupID] else {
                latestByGroup[groupID] = message
                continue
            }
            if message.createdAt > current.createdAt ||
                (message.createdAt == current.createdAt && message.id > current.id) {
                latestByGroup[groupID] = message
            }
        }

        var updatedBaselines = baselines
        for groupID in latestByGroup.keys where updatedBaselines[groupID] == nil {
            updatedBaselines[groupID] = now
        }
        updatedBaselines = prunedBaselines(updatedBaselines)

        return Snapshot(
            entries: entries(
                latestByGroup: latestByGroup,
                timesByGroup: timesByGroup,
                baselines: updatedBaselines
            ),
            latestByGroup: latestByGroup,
            timesByGroup: timesByGroup,
            baselines: updatedBaselines
        )
    }

    static func entries(
        latestByGroup: [String: RoomMessage],
        timesByGroup: [String: [UInt64]],
        baselines: [String: UInt64]
    ) -> [String: RoomDirectoryEntry] {
        var result: [String: RoomDirectoryEntry] = [:]
        for (groupID, message) in latestByGroup {
            let baseline = baselines[groupID] ?? message.createdAt
            let unread = (timesByGroup[groupID] ?? []).count { $0 > baseline }
            result[groupID] = RoomDirectoryEntry(latest: message, unread: unread)
        }
        return result
    }

    static func readBaseline(latest: RoomMessage?, now: UInt64) -> UInt64 {
        latest?.createdAt ?? now
    }

    static func prunedBaselines(_ baselines: [String: UInt64]) -> [String: UInt64] {
        guard baselines.count > maximumBaselines else { return baselines }
        let newest = baselines.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        return Dictionary(
            uniqueKeysWithValues: newest.prefix(maximumBaselines).map { ($0.key, $0.value) }
        )
    }
}
