import NMP

func roomChatDemand(host: String, groupID: String) -> NMPDemand {
    roomContentDemand(
        host: host,
        groupID: groupID,
        kinds: [9, 9_000, 9_001],
        limit: 200
    )
}

func roomActivityDemand(host: String, groupID: String) -> NMPDemand {
    roomContentDemand(host: host, groupID: groupID, kinds: [30_315], limit: 100)
}

func roomReactionsDemand(host: String, groupID: String) -> NMPDemand {
    roomContentDemand(host: host, groupID: groupID, kinds: [7], limit: 1_000)
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

private func roomContentDemand(
    host: String,
    groupID: String,
    kinds: [UInt16],
    limit: UInt32
) -> NMPDemand {
    NMPDemand(
        selection: NMPFilter(
            kinds: kinds,
            tags: ["h": .literal([groupID])],
            limit: limit
        ),
        source: .pinned([host]),
        cache: .strict
    )
}
