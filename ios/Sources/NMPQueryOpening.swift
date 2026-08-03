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

    static let live = NMPQueryOpening(
        filter: openNMPQuery(engine:filter:),
        query: openNMPQuery(engine:query:)
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
