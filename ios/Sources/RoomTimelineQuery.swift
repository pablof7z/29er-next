import NMP

func roomTimelineDemand(host: String, groupID: String) throws -> NMPDemand {
    var demand = try groupContentDemand(host: host, groupId: groupID)
    demand.selection.kinds = [9, 9_000, 9_001, 30_315]
    demand.selection.limit = 200
    return demand
}
