import SwiftUI
import UIKit

let avatarWidth: CGFloat = 34
let avatarSpacing: CGFloat = 10

/// One chat message. `showsHeader` is false for a grouped continuation, which
/// hides the avatar/name/time and aligns the body in the avatar gutter. Author
/// identity is resolved through `profiles`, falling back to shortened hex.
struct MessageRow: View {
    let message: RoomMessage
    let showsHeader: Bool
    let profiles: ProfileBook

    private var displayContent: String {
        message.content.isEmpty ? "Empty message" : message.content
    }

    private var displayName: String {
        profiles.displayName(for: message.author, fallback: message.authorLabel)
    }

    private var avatarURL: URL? {
        profiles.pictureURL(for: message.author)
    }

    var body: some View {
        HStack(alignment: .top, spacing: avatarSpacing) {
            gutter

            VStack(alignment: .leading, spacing: 4) {
                if showsHeader {
                    header
                }
                Text(displayContent)
                    .font(.body)
                    .foregroundStyle(message.content.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, showsHeader ? 10 : 2)
        .padding(.bottom, 2)
        .background(Color(uiColor: .systemBackground))
        .contextMenu { contextActions }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
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
        HStack(alignment: .firstTextBaseline) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(message.createdAt.messageClockTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        if !message.content.isEmpty {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: message.content) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var accessibilityText: String {
        "\(displayName), \(message.createdAt.messageClockTime): \(displayContent)"
    }
}

private extension UInt64 {
    var messageClockTime: String {
        Date(timeIntervalSince1970: TimeInterval(self))
            .formatted(date: .omitted, time: .shortened)
    }
}
