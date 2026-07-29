extension RoomTimelineModel {
    var timelineItems: [RoomTimelineItem] {
        NIP29ViewProjection.timelineItems(from: chatRows)
    }

    /// TTS29 spoken items present in the room's chat rows, indexed by event id
    /// with their narrated branches assembled.
    var tts29Catalog: TTS29Catalog {
        TTS29Catalog(rows: chatRows)
    }

    var mentionIDs: Set<String> {
        guard let recipient else { return [] }
        return MentionProjection.mentionIDs(from: chatRows, recipient: recipient)
    }

    var activities: [AgentActivity] {
        NIP29ViewProjection.activities(from: activityRows)
    }

    var reactionsByMessage: [String: [RoomReactionGroup]] {
        RoomReactionProjection.summaries(
            from: RoomReactionProjection.reactions(from: reactionRows),
            viewer: recipient
        )
    }

    var people: RoomPeople {
        NIP29ViewProjection.people(members: members, activities: activities)
    }

    var composerRecipients: [ComposerRecipient] {
        RoomComposerProjection.recipients(
            from: people,
            recentSpeakers: timelineItems.compactMap { $0.message?.author },
            profiles: profiles,
            excluding: recipient
        )
    }

    func composerReply(to message: RoomMessage) -> ComposerReply {
        RoomComposerProjection.reply(to: message, people: people, profiles: profiles)
    }

    /// The default recipient a new message auto-tags with: the most recent
    /// speaker other than the signed-in user (#118).
    var lastOtherSpeaker: ComposerRecipient? {
        RoomComposerProjection.lastOtherSpeaker(
            in: timelineItems,
            excluding: recipient,
            people: people,
            profiles: profiles
        )
    }

    /// Management backends present in this room, resolved from kind:0 across
    /// members, admins, and live-session authors.
    var backends: [RoomBackend] {
        let candidates = members.map(\.pubkey) + admins + activities.map(\.author)
        return RoomBackendProjection.backends(candidatePubkeys: candidates, profiles: profiles)
    }
}
