import NMP
import NMPContent

/// Product-owned acquisition policy for references selected by a channel
/// preview. Authored hints remain presentation data and never become relay,
/// kind, or author authority.
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
