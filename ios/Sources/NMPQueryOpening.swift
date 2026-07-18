import NMP

struct NMPQueryOpening: Sendable {
    let filter: @Sendable (NMPEngine, NMPFilter) async throws -> NMPQuery
    let demand: @Sendable (NMPEngine, NMPDemand) async throws -> NMPQuery

    static let live = NMPQueryOpening(
        filter: openNMPQuery(engine:filter:),
        demand: openNMPQuery(engine:demand:)
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
    demand: NMPDemand
) async throws -> NMPQuery {
    try engine.observe(demand)
}
