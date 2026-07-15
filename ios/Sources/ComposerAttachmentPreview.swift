import AVFoundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ComposerAttachmentPreviewStrip: View {
    let attachments: [ComposerAttachment]
    let isDisabled: Bool
    let remove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentPreview(attachment: attachment) {
                        remove(attachment.id)
                    }
                    .disabled(isDisabled)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("room-composer-attachments")
    }
}

private struct ComposerAttachmentPreview: View {
    let attachment: ComposerAttachment
    let remove: () -> Void
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        HStack(spacing: 8) {
            preview
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .padding(6)
        .frame(maxWidth: 230)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityIdentifier("composer-attachment-\(attachment.id)")
        .onDisappear { audioPlayer?.stop() }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if attachment.isAudio {
                Button(action: toggleAudioPreview) {
                    thumbnail
                        .overlay {
                            Image(systemName: audioPlayer?.isPlaying == true ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.bold))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(attachment.filename)")
            } else {
                thumbnail
            }
        }
        .frame(width: 38, height: 38)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if os(iOS)
        if attachment.isImage, let image = UIImage(data: attachment.data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            fileIcon
        }
        #elseif os(macOS)
        if attachment.isImage, let image = NSImage(data: attachment.data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            fileIcon
        }
        #endif
    }

    private var fileIcon: some View {
        Image(systemName: attachment.isAudio ? "waveform" : "doc.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private func toggleAudioPreview() {
        if let audioPlayer, audioPlayer.isPlaying {
            audioPlayer.stop()
            self.audioPlayer = nil
            return
        }
        do {
            let player = try AVAudioPlayer(data: attachment.data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            audioPlayer = nil
        }
    }
}
