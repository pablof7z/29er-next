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
    /// The one relay-signed record this app still reads as raw rows -- see
    /// `groupDirectoryQuery(host:)`. 39001 and 39002 are gone from here
    /// because nothing selects them any more: they arrive typed, through
    /// `roomRecordsObservation(engine:host:groupID:)`.
    static let groupMetadata: UInt16 = 39_000

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
// kind:39000 metadata, kind:39001 admins and kind:39002 members key
// themselves on `d`, not on the `h` row `NMPGroup.read` stamps. They are
// therefore NOT group content and `NMPGroup.read` refuses them outright
// (NMP #1245) rather than building a filter no such event can match. They
// read through their own door instead.

/// This room's relay-signed records, as one reactive observation.
///
/// Every delivery is a complete `NMPGroupSnapshot`, carrying the admin list
/// and the member list with each entry already naming the hosts that listed
/// it. The app never sees a row delta, never walks a `p` row, and never
/// accumulates -- the value that arrives IS the current value, so a
/// demotion shrinks the list the same way a promotion grows it.
///
/// One observation for both lists, not two: NMP mints one branch per host in
/// the scope, and this app's scope names exactly one.
///
/// kind:39000 is deliberately NOT selected. The record selector exists so a
/// screen pays only for what it renders, and the room renders neither the
/// group's name nor its `about` -- both come from the sidebar's directory
/// listing, which cannot use this door at all (`groupDirectoryQuery(host:)`).
func roomRecordsObservation(
    engine: NMPEngine,
    host: String,
    groupID: String
) throws -> NMPGroupObservation {
    try roomGroup(host: host, groupID: groupID)
        .observeRecords(engine: engine, records: [.admins, .members])
}

/// Every group the host advertises, for the channel sidebar.
///
/// NOT expressible through `NMPRelayScope.observeRecords(engine:matching:records:)`.
/// `NMPGroupPredicate` has exactly three leaves -- `memberListIncludes`,
/// `adminListIncludes` and `anyOf(ids)` -- and "every group this relay
/// hosts" is none of them: the first two are membership questions this
/// browse list deliberately does not ask, and the third needs the very ids
/// the browse is for. So this one 39000 read stays hand-built, and
/// `GroupDirectoryProjection` stays the single place that parses it.
/// Tracked as an upstream gap; see that type's doc comment.
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
