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
            HStack(alignment: .top, spacing: 10) {
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

/// A single attachment tile styled after ChatGPT's composer: a large rounded image
/// thumbnail with a corner ✕, image-forward and chrome-free. Non-image files show a doc
/// icon with the filename beneath; audio keeps a play/pause overlay.
private struct ComposerAttachmentPreview: View {
    let attachment: ComposerAttachment
    let remove: () -> Void
    @State private var audioPlayer: AVAudioPlayer?

    private let side: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            tile
                .frame(width: side, height: side)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) { removeButton }
            if !attachment.isImage {
                Text(attachment.filename)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: side, alignment: .leading)
            }
        }
        .accessibilityIdentifier("composer-attachment-\(attachment.id)")
        .onDisappear { audioPlayer?.stop() }
    }

    @ViewBuilder
    private var tile: some View {
        if attachment.isAudio {
            Button(action: toggleAudioPreview) {
                ZStack {
                    fileIcon("waveform")
                    Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                    Image(systemName: audioPlayer?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(attachment.filename)")
        } else {
            thumbnail
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if os(iOS)
        if attachment.isImage, let image = UIImage(data: attachment.data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            fileIcon("doc.fill")
        }
        #elseif os(macOS)
        if attachment.isImage, let image = NSImage(data: attachment.data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            fileIcon("doc.fill")
        }
        #endif
    }

    private func fileIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.55), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(5)
        .accessibilityLabel("Remove \(attachment.filename)")
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
