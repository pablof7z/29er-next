struct NoticeContent: Equatable, Identifiable {
    let symbol: String
    let title: String
    let message: String

    var id: String { "\(symbol):\(title)" }

    static func profilesUnavailable(
        _ message: String,
        symbol: String = "exclamationmark.triangle.fill"
    ) -> NoticeContent {
        NoticeContent(
            symbol: symbol,
            title: "Profiles unavailable",
            message: message
        )
    }
}

enum ChannelListPresentation {
    static func activityNotice(error: String?) -> NoticeContent? {
        error.map {
            NoticeContent(
                symbol: "exclamationmark.triangle.fill",
                title: "Room activity unavailable",
                message: $0
            )
        }
    }
}

enum InboxContentState: Equatable {
    case unavailable(String)
    case zero
    case mentions
}

struct InboxPresentation: Equatable {
    let content: InboxContentState
    let notice: NoticeContent?

    static func make(
        unreadCount: Int,
        mentionError: String?,
        profileError: String?
    ) -> InboxPresentation {
        if unreadCount == 0, let mentionError {
            return InboxPresentation(content: .unavailable(mentionError), notice: nil)
        }
        if unreadCount == 0 {
            return InboxPresentation(content: .zero, notice: nil)
        }
        if let mentionError {
            return InboxPresentation(
                content: .mentions,
                notice: NoticeContent(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Inbox may be out of date",
                    message: mentionError
                )
            )
        }
        if let profileError {
            return InboxPresentation(
                content: .mentions,
                notice: NoticeContent.profilesUnavailable(profileError)
            )
        }
        return InboxPresentation(content: .mentions, notice: nil)
    }
}

enum ChatTimelinePresentation: Equatable {
    case unavailable(String)
    case loading
    case empty
    case messages(profileNotice: NoticeContent?)

    static func make(
        itemCount: Int,
        hasReceivedSnapshot: Bool,
        error: String?,
        profileError: String?
    ) -> ChatTimelinePresentation {
        if let error { return .unavailable(error) }
        if !hasReceivedSnapshot { return .loading }
        if itemCount == 0 { return .empty }
        let notice = profileError.map { NoticeContent.profilesUnavailable($0) }
        return .messages(profileNotice: notice)
    }
}

enum MembershipPresentation: Equatable {
    case unavailable(NoticeContent)
    case loading
    case metadataMissing(NoticeContent)
    case ready
}

struct RoomPeoplePresentation: Equatable {
    struct Input {
        var hasReceivedMembership = false
        var hasMembershipMetadata = false
        var membershipError: String?
        var hasReceivedActivities = false
        var activityError: String?
        var adminError: String?
        var profileError: String?
        var memberCount = 0
        var activeCount = 0
    }

    let membership: MembershipPresentation
    let notices: [NoticeContent]
    let showEmptyState: Bool

    static func make(_ input: Input) -> RoomPeoplePresentation {
        let membership: MembershipPresentation
        if let membershipError = input.membershipError {
            membership = .unavailable(
                NoticeContent(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Member list unavailable",
                    message: membershipError
                )
            )
        } else if !input.hasReceivedMembership {
            membership = .loading
        } else if !input.hasMembershipMetadata {
            membership = .metadataMissing(
                NoticeContent(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: "Member list unavailable",
                    message: "The relay has not provided kind 39002 membership metadata for this room."
                )
            )
        } else {
            membership = .ready
        }

        let notices = [
            input.adminError.map {
                NoticeContent(symbol: "person.badge.key", title: "Backend admins unavailable", message: $0)
            },
            input.profileError.map {
                NoticeContent.profilesUnavailable(
                    $0,
                    symbol: "person.crop.circle.badge.exclamationmark"
                )
            },
            input.activityError.map {
                NoticeContent(symbol: "bolt.slash", title: "Live status unavailable", message: $0)
            }
        ].compactMap { $0 }

        return RoomPeoplePresentation(
            membership: membership,
            notices: notices,
            showEmptyState: input.hasReceivedMembership &&
                input.hasReceivedActivities &&
                input.memberCount == 0 &&
                input.activeCount == 0 &&
                !input.hasMembershipMetadata
        )
    }
}
