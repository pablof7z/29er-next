import SwiftUI

let avatarWidth: CGFloat = 34
let avatarSpacing: CGFloat = 10

/// One chat message. `showsHeader` is false for a grouped continuation, which
/// hides the avatar/name/time and aligns the body in the avatar gutter. Author
/// identity is resolved through `profiles`, falling back to shortened hex.
struct MessageRow: View {
    let message: RoomMessage
    let showsHeader: Bool
    let profiles: ProfileBook
    let agentActivity: AgentActivity?
    let onReply: () -> Void

    private var displayContent: String {
        message.content.isEmpty ? "Empty message" : message.content
    }

    private var displayName: String {
        profiles.displayName(for: message.author, fallback: message.authorLabel)
    }

    private var avatarURL: URL? {
        profiles.pictureURL(for: message.author)
    }

    private var authorWorkspace: String? {
        profiles.workspace(for: message.author)
    }

    private var authorColor: Color {
        authorWorkspace.map(WorkspaceTint.color) ?? .primary
    }

    private var activityTitle: String? {
        guard let title = agentActivity?.title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    private var hasAudio: Bool {
        MessageContent.segments(of: message.content).contains {
            if case .audio = $0 { return true }
            return false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: avatarSpacing) {
            gutter

            VStack(alignment: .leading, spacing: 4) {
                if showsHeader {
                    header
                }
                content
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, showsHeader ? 10 : 2)
        .padding(.bottom, 2)
        .background(PlatformSupport.windowBackground)
        .contextMenu { contextActions }
        .accessibilityElement(children: hasAudio ? .contain : .combine)
        .accessibilityLabel(hasAudio ? accessibilityAudioLabel : accessibilityText)
        .accessibilityAction(named: "Reply") { onReply() }
    }

    @ViewBuilder
    private var content: some View {
        if message.content.isEmpty {
            Text(displayContent)
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
                .onTapGesture {
                    PlatformSupport.performLightImpact()
                    onReply()
                }
        } else {
            MessageBody(raw: message.content, messageID: message.id, onReply: onReply)
        }
    }

    @ViewBuilder
    private var gutter: some View {
        if showsHeader {
            AuthorAvatar(
                pubkey: message.author,
                displayName: displayName,
                pictureURL: avatarURL,
                size: avatarWidth
            )
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: avatarWidth, height: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authorColor)
                    if let agentActivity {
                        AgentStateBadge(isBusy: agentActivity.isBusy)
                    }
                }
                if let activityTitle {
                    Text(activityTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(activityTitle)
                }
            }
            Spacer()
            Text(message.createdAt.messageClockTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        if !message.content.isEmpty {
            Button {
                PlatformSupport.copyToPasteboard(message.content)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: message.content) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var accessibilityText: String {
        let status = agentActivity.map { $0.isBusy ? "busy" : "idle" }
        let activity = [activityTitle, status].compactMap { $0 }.joined(separator: ", ")
        let author = activity.isEmpty ? displayName : "\(displayName), \(activity)"
        return "\(author), \(message.createdAt.messageClockTime): \(displayContent)"
    }

    private var accessibilityAudioLabel: String {
        "\(displayName), \(message.createdAt.messageClockTime), audio message"
    }
}

private struct AgentStateBadge: View {
    let isBusy: Bool

    private var color: Color { isBusy ? .orange : .green }
    private var label: String { isBusy ? "Busy" : "Idle" }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel("Agent status: \(label)")
    }
}

private extension UInt64 {
    var messageClockTime: String {
        Date(timeIntervalSince1970: TimeInterval(self))
            .formatted(date: .omitted, time: .shortened)
    }
}
