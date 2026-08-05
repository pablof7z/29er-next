import NMP

/// The seam every model opens its NMP observations through.
///
/// `NMPLiveQuery` is NMP's one read noun -- a canonical branch set built only
/// via `single`/`union`, where `branches[i]` names the branch each delivered
/// `RowBatch.evidence[i]` reports on. Models declare one and hand it here;
/// nothing in this app merges per-host results by hand.
struct NMPQueryOpening: Sendable {
    let filter: @Sendable (NMPEngine, NMPFilter) async throws -> NMPQuery
    let query: @Sendable (NMPEngine, NMPLiveQuery) async throws -> NMPQuery
    /// NIP-29's relay-signed group records do not come through `NMPLiveQuery`
    /// at all -- they key on `d`, not the `h` row `NMPGroup.read` stamps, so
    /// they have their own reactive door and their own opening seam.
    let records: @Sendable (NMPEngine, String, String) async throws -> NMPGroupObservation

    static let live = NMPQueryOpening(
        filter: openNMPQuery(engine:filter:),
        query: openNMPQuery(engine:query:),
        records: openNMPGroupRecords(engine:host:groupID:)
    )
}

/// Opens NMP's synchronous observation boundary away from actor-isolated UI
/// models. Initial snapshot decoding completes before `observe` returns, so
/// every model must await this async seam before consuming the query on its
/// own actor.
func openNMPQuery(
    engine: NMPEngine,
    filter: NMPFilter
) async throws -> NMPQuery {
    try engine.observe(filter)
}

func openNMPQuery(
    engine: NMPEngine,
    query: NMPLiveQuery
) async throws -> NMPQuery {
    try engine.observe(query)
}

func openNMPQuery(
    engine: NMPEngine,
    demand: NMPDemand
) async throws -> NMPQuery {
    try engine.observe(.single(demand))
}

/// Opens the group-records observation off the UI actor, for the same reason
/// `openNMPQuery` exists: `observeRecords` is synchronous and does its first
/// decode before returning.
func openNMPGroupRecords(
    engine: NMPEngine,
    host: String,
    groupID: String
) async throws -> NMPGroupObservation {
    try roomRecordsObservation(engine: engine, host: host, groupID: groupID)
}

/// The same door widened to a whole host: every group it advertises, rather
/// than one this app has already named.
func openNMPGroupDirectory(
    engine: NMPEngine,
    host: String
) async throws -> NMPGroupRecordsObservation {
    try groupDirectoryObservation(engine: engine, host: host)
}
