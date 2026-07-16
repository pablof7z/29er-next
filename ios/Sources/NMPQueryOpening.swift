import NMP

struct NMPQueryOpening: Sendable {
    let filter: @Sendable (NMPEngine, NMPFilter, Window?) async throws -> NMPQuery
    let demand: @Sendable (NMPEngine, NMPDemand, Window?) async throws -> NMPQuery

    static let live = NMPQueryOpening(
        filter: openNMPQuery(engine:filter:window:),
        demand: openNMPQuery(engine:demand:window:)
    )
}

/// Opens NMP's synchronous observation boundary away from actor-isolated UI
/// models. Initial snapshot decoding completes before `observe` returns, so
/// every model must await this async seam before consuming the query on its
/// own actor.
func openNMPQuery(
    engine: NMPEngine,
    filter: NMPFilter,
    window: Window? = nil
) async throws -> NMPQuery {
    try engine.observe(filter, window: window)
}

func openNMPQuery(
    engine: NMPEngine,
    demand: NMPDemand,
    window: Window? = nil
) async throws -> NMPQuery {
    try engine.observe(demand, window: window)
}
