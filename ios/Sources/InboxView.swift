import SwiftUI

/// Pushed when the toolbar bell is tapped.
struct InboxRoute: Hashable {}

/// Pushed when a mention is tapped: open its room focused on that message.
struct MentionRoute: Hashable {
    let group: GroupSummary
    let messageID: String
}

/// The inbox: every unread message that p-tags the active account, newest
/// first. Opening the inbox does not mark anything read — a mention only clears
/// once its message is actually seen on screen in its room, so this screen is a
/// launcher into that context.
struct InboxView: View {
    let inbox: InboxModel
    let groups: [GroupSummary]

    private var unread: [Mention] { inbox.unreadMentions }
    private var presentation: InboxPresentation {
        InboxPresentation.make(
            unreadCount: unread.count,
            mentionError: inbox.mentionError,
            profileError: inbox.profileError
        )
    }

    var body: some View {
        Group {
            switch presentation.content {
            case .unavailable(let error):
                ContentUnavailableView(
                    "Inbox Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            case .zero:
                ContentUnavailableView(
                    "Inbox Zero",
                    systemImage: "tray",
                    description: Text("Messages that mention you will appear here.")
                )
            case .mentions:
                List(unread) { mention in
                    if let group = group(for: mention) {
                        NavigationLink(value: MentionRoute(group: group, messageID: mention.id)) {
                            MentionRow(mention: mention, roomName: group.name, profiles: inbox.profiles)
                        }
                    } else {
                        MentionRow(mention: mention, roomName: mention.groupLocalID, profiles: inbox.profiles)
                    }
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let notice = presentation.notice {
                        DegradedStateNotice(title: notice.title, message: notice.message)
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(for mention: Mention) -> GroupSummary? {
        groups.first { $0.localID == mention.groupLocalID }
    }

}

struct MentionRow: View {
    let mention: Mention
    let roomName: String
    let profiles: ProfileBook

    private var displayName: String {
        profiles.displayName(for: mention.author, fallback: mention.authorLabel)
    }

    private var avatarURL: URL? {
        profiles.pictureURL(for: mention.author)
    }

    private var displayContent: String {
        mention.content.isEmpty ? "Empty message" : mention.content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AuthorAvatar(
                pubkey: mention.author,
                displayName: displayName,
                pictureURL: avatarURL,
                size: avatarWidth
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(GroupRow.relativeTime(mention.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Label(roomName, systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(displayContent)
                    .font(.subheadline)
                    .foregroundStyle(mention.content.isEmpty ? .tertiary : .primary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName) in \(roomName): \(displayContent)")
    }

}

/// A bell with an unread-count badge for the main-screen toolbar.
struct InboxBell: View {
    let count: Int

    var body: some View {
        Image(systemName: count > 0 ? "tray.full" : "tray")
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 10, y: -8)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(count > 0 ? "Inbox, \(count) unread" : "Inbox")
    }
}
