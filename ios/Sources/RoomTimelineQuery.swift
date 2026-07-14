import NMP

func roomChatDemand(host: String, groupID: String) throws -> NMPDemand {
    var demand = try groupContentDemand(host: host, groupId: groupID)
    demand.selection.kinds = [9, 9_000, 9_001]
    demand.selection.limit = 200
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
