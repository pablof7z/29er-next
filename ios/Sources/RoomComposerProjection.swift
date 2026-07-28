import Foundation

enum RoomComposerProjection {
    /// The pickable roster: formal members, currently-live-activity people,
    /// and -- so the picker never offers a narrower pool than auto-tagging
    /// (`lastOtherSpeaker`) already draws from -- anyone who has posted a
    /// chat message in the room, even without formal membership or a still-
    /// live activity event.
    static func recipients(
        from people: RoomPeople,
        recentSpeakers: [String] = [],
        profiles: ProfileBook,
        excluding excludedPubkey: String?
    ) -> [ComposerRecipient] {
        var seen = Set<String>()
        let pubkeys = people.members.map(\.pubkey) + people.activeHere.map(\.pubkey) + recentSpeakers
        return pubkeys
            .filter {
                $0 != excludedPubkey &&
                    profiles.profile(for: $0)?.isBackend != true &&
                    seen.insert($0).inserted
            }
            .map { recipient(for: $0, people: people, profiles: profiles) }
            .sorted { lhs, rhs in
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.pubkey < rhs.pubkey
            }
    }

    /// The most recent message's author other than `excludedPubkey` (the
    /// signed-in user) -- the default recipient a composer auto-tags the
    /// moment typing starts, same value shape a manual mention pick or
    /// reply already produces so it renders as an identical chip.
    static func lastOtherSpeaker(
        in items: [RoomTimelineItem],
        excluding excludedPubkey: String?,
        people: RoomPeople,
        profiles: ProfileBook
    ) -> ComposerRecipient? {
        for item in items.reversed() {
            guard let message = item.message, message.author != excludedPubkey else { continue }
            return recipient(for: message.author, people: people, profiles: profiles)
        }
        return nil
    }

    static func reply(
        to message: RoomMessage,
        people: RoomPeople,
        profiles: ProfileBook
    ) -> ComposerReply {
        ComposerReply(
            eventID: message.id,
            author: recipient(for: message.author, people: people, profiles: profiles),
            preview: message.content
        )
    }

    private static func recipient(
        for pubkey: String,
        people: RoomPeople,
        profiles: ProfileBook
    ) -> ComposerRecipient {
        let person = (people.members + people.activeHere).first { $0.pubkey == pubkey }
        let displayName = person?.activity?.slug
            ?? profiles.displayName(for: pubkey, fallback: PubkeyDisplay.shortHex(pubkey))
        return ComposerRecipient(
            pubkey: pubkey,
            displayName: displayName,
            pictureURL: profiles.pictureURL(for: pubkey),
            activity: person?.activity
        )
    }
}
