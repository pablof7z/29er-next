import NMP
import NMPContent

/// Product-owned acquisition policy for references selected by a channel
/// preview -- the `resolve` seam `NMPReferenceObservationFactory.live` needs.
///
/// NMPUI hands over the exact authored locator and never picks kind, source
/// authority, cache, freshness, or relay admission itself. Authored relay
/// hints stay presentation data: they are read here and deliberately not
/// turned into wire authority, because an author naming a relay does not make
/// that relay trustworthy for this app's reads.
func channelPreviewReferenceDemand(
    for target: NostrReferenceTarget
) throws -> NMPDemand {
    switch target {
    case .pubkey(let pubkey), .profile(let pubkey, _):
        return NMPDemand(
            selection: NMPFilter(
                kinds: [0],
                authors: .literal([pubkey]),
                limit: 1
            ),
            source: .authorOutboxes
        )
    case .eventID(let id), .event(let id, _, _, _):
        return NMPDemand(
            selection: NMPFilter(ids: .literal([id]), limit: 1),
            source: .public
        )
    case .coordinate(let kind, let author, let identifier, _):
        return NMPDemand(
            selection: NMPFilter(
                kinds: [kind],
                authors: .literal([author]),
                tags: ["d": .literal([identifier])],
                limit: 1
            ),
            source: .authorOutboxes
        )
    }
}
