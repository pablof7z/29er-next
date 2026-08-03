import NMP

/// The event kinds this app reads inside a NIP-29 room.
///
/// NIP-29 keeps MODERATOR actions and SELF-SERVICE requests apart, and NMP
/// names all four in `crates/nmp-nip29/src/operations.rs`: kind:9000 is
/// put-user and kind:9001 is remove-user -- what a moderator did to somebody
/// else -- while kind:9021 is join-request and kind:9022 is leave-request,
/// which is what a person did themselves. They are not interchangeable and
/// they do not name the same subject: 9000/9001 name their target on a `p`
/// tag, 9021/9022 name nobody but their own author.
enum RoomKind {
    static let reaction: UInt16 = 7
    static let chat: UInt16 = 9
    static let putUser: UInt16 = 9_000
    static let removeUser: UInt16 = 9_001
    static let joinRequest: UInt16 = 9_021
    static let leaveRequest: UInt16 = 9_022
    static let liveStatus: UInt16 = 30_315
    static let groupMetadata: UInt16 = 39_000
    static let groupAdmins: UInt16 = 39_001
    static let groupMembers: UInt16 = 39_002

    /// Everything the room timeline renders, read through one subscription.
    static let timeline: [UInt16] = [chat, putUser, removeUser, joinRequest, leaveRequest]
}

/// The NIP-29 group a room reads and writes.
///
/// Exactly one host per group: 29er-next deliberately does not present a
/// group hosted on several relays, so the scope always names one.
/// `NMPRelayScope.on` refuses an empty host set; `.group` narrows and
/// contacts nothing, so this value is an identity that serves every read and
/// every write for the room's whole lifetime.
func roomGroup(host: String, groupID: String) throws -> NMPGroup {
    try NMPRelayScope.on([host]).group(groupID)
}

/// Chat plus membership activity. `NMPGroup.read` owns the `#h` scoping and
/// stamps both host-scoping axes (pinned wire authority AND a strict cache
/// mode) on the branch it mints -- the app supplies only the selection.
func roomChatQuery(host: String, groupID: String) throws -> NMPLiveQuery {
    try roomGroup(host: host, groupID: groupID)
        .read(NMPFilter(kinds: RoomKind.timeline, limit: 200))
}

func roomActivityQuery(host: String, groupID: String) throws -> NMPLiveQuery {
    try roomGroup(host: host, groupID: groupID)
        .read(NMPFilter(kinds: [RoomKind.liveStatus], limit: 100))
}

func roomReactionsQuery(host: String, groupID: String) throws -> NMPLiveQuery {
    try roomGroup(host: host, groupID: groupID)
        .read(NMPFilter(kinds: [RoomKind.reaction], limit: 1_000))
}

// MARK: - Relay-signed group records
//
// PLACEHOLDER, awaiting NMP's roster reader (that design is in flight).
//
// kind:39000/39001/39002 key themselves on `d`, not on the `h` tag
// `NMPGroup.read` stamps, and `NMPRelayScope.groupsWhere` accepts only
// membership/admin *predicates* -- neither door can express "the group
// records for THIS group id at THIS host", so these three demands stay
// hand-built. They are deliberately NOT wrapped in an app-side roster
// abstraction: a second app-owned roster model is exactly what would make
// the upstream adoption harder.
//
// They mirror what NMP's own NIP-29 demands carry (`crates/nmp-nip29/src/
// discovery.rs`): pinned to exactly one host AND `CacheMode.strict`, both
// axes. Pinning alone scopes only which relay is asked on the wire; the
// cache would still answer from any provenance under the `.agnostic`
// default, which is a real cross-host leak.

func roomMembershipQuery(host: String, groupID: String) -> NMPLiveQuery {
    .single(groupRecordDemand(host: host, groupID: groupID, kind: RoomKind.groupMembers))
}

func roomAdminQuery(host: String, groupID: String) -> NMPLiveQuery {
    .single(groupRecordDemand(host: host, groupID: groupID, kind: RoomKind.groupAdmins))
}

/// Every group the host advertises. Not expressible through
/// `NMPRelayScope.groupsWhere` either -- that door needs a membership or
/// admin predicate, and "everything this relay hosts" is not one. Same
/// placeholder as the two above.
func groupDirectoryQuery(host: String) -> NMPLiveQuery {
    .single(
        NMPDemand(
            selection: NMPFilter(kinds: [RoomKind.groupMetadata], limit: 250),
            source: .pinned([host]),
            cache: .strict
        )
    )
}

/// Recent chat across every group at the host, for the channel-list preview.
func roomDirectoryQuery(host: String) -> NMPLiveQuery {
    .single(
        NMPDemand(
            selection: NMPFilter(kinds: [RoomKind.chat], limit: 500),
            source: .pinned([host]),
            cache: .strict
        )
    )
}

private func groupRecordDemand(host: String, groupID: String, kind: UInt16) -> NMPDemand {
    NMPDemand(
        selection: NMPFilter(
            kinds: [kind],
            tags: ["d": .literal([groupID])],
            limit: 20
        ),
        source: .pinned([host]),
        cache: .strict
    )
}
