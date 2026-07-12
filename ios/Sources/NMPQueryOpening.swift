import NMP

/// Opens NMP's synchronous observation boundary away from actor-isolated UI
/// models. Initial snapshot decoding completes before `observe` returns, so
/// every model must await this async seam before consuming the query on its
/// own actor.
func openNMPQuery(engine: NMPEngine, filter: NMPFilter) async throws -> NMPQuery {
    try engine.observe(filter)
}
