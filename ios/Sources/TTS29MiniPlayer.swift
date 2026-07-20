import SwiftUI

/// The docked mini-player. It stays visible while the full player is dismissed
/// but audio keeps playing, so the listener can browse other channels. Tapping
/// it reopens the item.
struct TTS29MiniPlayer: View {
    @Bindable var playback: TTS29PlaybackController
    let item: TTS29Item

    private var identity: TTS29Identity { TTS29Identity(item) }

    var body: some View {
        HStack(spacing: 10) {
            TTS29AgentAvatar(identity: identity, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(playback.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                playback.toggleSelected()
            } label: {
                Image(systemName: playSymbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("tts29-mini-toggle")

            Button {
                playback.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(alignment: .bottom) {
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * playback.progress, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.linear(duration: 0.2), value: playback.progress)
            }
            .allowsHitTesting(false)
        }
        .tts29GlassCapsule(interactive: true)
        .contentShape(Capsule())
        .onTapGesture { playback.presentSelected() }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tts29-mini-player")
    }

    private var playSymbol: String {
        switch playback.phase {
        case .playing, .loading: "pause.circle.fill"
        case .ended: "arrow.counterclockwise.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        default: "play.circle.fill"
        }
    }
}
