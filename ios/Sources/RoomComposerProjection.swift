import Foundation

enum RoomComposerProjection {
    static func recipients(
        from people: RoomPeople,
        profiles: ProfileBook,
        excluding excludedPubkey: String?
    ) -> [ComposerRecipient] {
        var seen = Set<String>()
        return (people.members + people.activeHere)
            .filter {
                $0.pubkey != excludedPubkey &&
                    profiles.profile(for: $0.pubkey)?.isBackend != true &&
                    seen.insert($0.pubkey).inserted
            }
            .map { recipient(for: $0.pubkey, people: people, profiles: profiles) }
            .sorted { lhs, rhs in
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.pubkey < rhs.pubkey
            }
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
            pictureURL: profiles.pictureURL(for: pubkey)
        )
    }
}
