import SwiftUI

/// The distinct "spoken update" card shown in the channel timeline in place of
/// a plain text line. It never autoplays: tapping it opens the player, which is
/// where playback starts.
struct TTS29Card: View {
    let item: TTS29Item
    let isActive: Bool
    let isPlaying: Bool
    let onOpen: () -> Void

    private var identity: TTS29Identity { TTS29Identity(item) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let summary = item.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.16 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spoken update from \(identity.displayName): \(item.title)")
        .accessibilityHint("Opens the player")
        .accessibilityIdentifier("tts29-card")
    }

    private var header: some View {
        HStack(spacing: 10) {
            TTS29AgentAvatar(identity: identity, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Spoken update · \(TTS29Formatting.timestamp(item.createdDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            playGlyph
        }
    }

    private var playGlyph: some View {
        ZStack {
            Circle().fill(Color.accentColor)
            Image(systemName: isPlaying ? "waveform" : "play.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
        }
        .frame(width: 34, height: 34)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if item.hasAudio {
                badge("waveform", label: "Audio")
            }
            if item.hasChildren {
                badge("arrow.triangle.branch", label: "\(item.children.count)")
            }
            if item.hasAttachments {
                badge("paperclip", label: "\(item.attachments.count)")
            }
            if item.hasQuestions {
                badge("questionmark.circle", label: "\(item.questions.count)")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func badge(_ symbol: String, label: String) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
    }
}
