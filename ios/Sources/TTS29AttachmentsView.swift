import Kingfisher
import SwiftUI

/// A remote image for spoken-update surfaces, backed by the app's shared
/// Kingfisher cache.
struct TTS29RemoteImage: View {
    let url: URL?

    var body: some View {
        KFImage(url)
            .resizable()
            .placeholder {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.06))
                    .overlay { ProgressView() }
            }
            .fade(duration: 0.2)
            .scaledToFit()
    }
}

/// The horizontal attachments rail beneath the transcript.
struct TTS29AttachmentsRail: View {
    let attachments: [TTS29Artifact]
    let onOpen: (TTS29Artifact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Attachments", systemImage: "paperclip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(attachments) { attachment in
                        Button { onOpen(attachment) } label: {
                            TTS29AttachmentCard(attachment: attachment)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .accessibilityIdentifier("tts29-attachments")
    }
}

private struct TTS29AttachmentCard: View {
    let attachment: TTS29Artifact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if attachment.kind == .image {
                    TTS29RemoteImage(url: attachment.resolvedURL)
                        .scaledToFill()
                        .frame(height: 74)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Image(systemName: attachment.kind.symbolName)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(height: 74)
                        .frame(maxWidth: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(attachment.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(TTS29Formatting.byteCount(attachment.byteCount))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 148, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.10)))
    }
}

/// The narrated branches list. Each child opens the same player.
struct TTS29BranchesRail: View {
    let children: [TTS29Item]
    let onOpen: (TTS29Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Narrated branches", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(children) { child in
                Button { onOpen(child) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if child.hasChildren || child.hasAttachments {
                                Text(branchDetail(child))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tts29-branch")
            }
        }
    }

    private func branchDetail(_ child: TTS29Item) -> String {
        var parts: [String] = []
        if child.hasChildren { parts.append("\(child.children.count) sub-branch\(child.children.count == 1 ? "" : "es")") }
        if child.hasAttachments { parts.append("\(child.attachments.count) attachment\(child.attachments.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
