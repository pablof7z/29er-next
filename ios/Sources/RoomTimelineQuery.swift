import NMP

enum RoomChatWindow {
    static let initialRows: UInt64 = 200
    static let pageSize: UInt64 = 200
    static let maxRows: UInt64 = 1_000

    static let policy = Window.expandable(initial: initialRows, max: maxRows)
}

func roomChatDemand(host: String, groupID: String) throws -> NMPDemand {
    var demand = try groupContentDemand(host: host, groupId: groupID)
    demand.selection.kinds = [9, 9_000, 9_001]
    // NMP's window owns the newest-first selection bound. A simultaneous
    // NIP-01 limit is rejected because it would create two competing bounds.
    demand.selection.limit = nil
    return demand
}

func roomActivityDemand(host: String, groupID: String) throws -> NMPDemand {
    var demand = try groupContentDemand(host: host, groupId: groupID)
    demand.selection.kinds = [30_315]
    demand.selection.limit = 100
    return demand
}

func roomMembershipDemand(host: String, groupID: String) -> NMPDemand {
    NMPDemand(
        selection: NMPFilter(
            kinds: [39_002],
            tags: ["d": .literal([groupID])],
            limit: 20
        ),
        source: .pinned([host]),
        cache: .strict
    )
}

func roomAdminDemand(host: String, groupID: String) -> NMPDemand {
    NMPDemand(
        selection: NMPFilter(
            kinds: [39_001],
            tags: ["d": .literal([groupID])],
            limit: 20
        ),
        source: .pinned([host]),
        cache: .strict
    )
}

func roomDirectoryDemand(host: String) -> NMPDemand {
    NMPDemand(
        selection: NMPFilter(kinds: [9], limit: 500),
        source: .pinned([host]),
        cache: .strict
    )
}
