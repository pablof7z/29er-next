import SwiftUI

struct PersistentAudioPlayerContainer<Content: View>: View {
    @Environment(AudioPlaybackController.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if playback.activeID != nil {
                PersistentAudioMiniPlayer()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: playback.activeID)
    }
}

private struct PersistentAudioMiniPlayer: View {
    @Environment(AudioPlaybackController.self) private var playback

    private var activeID: AudioAttachmentID? { playback.activeID }
    private var position: Double { playback.isScrubbing ? playback.scrubTime : playback.currentTime }
    private var duration: Double { playback.duration }
    private var canSeek: Bool { duration.isFinite && duration > 0 }

    var body: some View {
        if let activeID {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    transportButton("Back 15 seconds", symbol: "gobackward.15") {
                        playback.skip(by: -15)
                    }
                    primaryButton(for: activeID)
                    transportButton("Forward 15 seconds", symbol: "goforward.15") {
                        playback.skip(by: 15)
                    }
                    title(for: activeID)
                    speedMenu
                    Button {
                        playback.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 32, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close audio player")
                    .accessibilityIdentifier("audio-mini-player-close")
                }

                Slider(
                    value: Binding(
                        get: { position },
                        set: { playback.updateScrub(to: $0) }
                    ),
                    in: 0...max(duration, 1),
                    onEditingChanged: { editing in
                        if editing { playback.beginScrubbing() } else { playback.endScrubbing() }
                    }
                )
                .controlSize(.mini)
                .disabled(!canSeek)
                .accessibilityLabel("Mini-player playback position")
                .accessibilityValue("\(spokenTime(position)) of \(spokenTime(duration))")
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("audio-mini-player")
        }
    }

    private func primaryButton(for id: AudioAttachmentID) -> some View {
        Button {
            playback.toggle(id: id, url: id.url)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                if playback.phase == .loading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: primarySymbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primaryAccessibilityLabel(for: id))
        .accessibilityIdentifier("audio-mini-player-toggle")
    }

    private func transportButton(
        _ label: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 32, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func title(for id: AudioAttachmentID) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(id.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(id.displaySource)
                    .lineLimit(1)
                Text("·")
                Text(timeSummary)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button {
                    playback.setPlaybackRate(rate)
                } label: {
                    if playback.playbackRate == rate {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            Text(rateLabel(playback.playbackRate))
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 36, minHeight: 36)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(rateLabel(playback.playbackRate))
    }

    private var primarySymbol: String {
        switch playback.phase {
        case .playing, .buffering: "pause.fill"
        case .ended: "arrow.counterclockwise"
        case .failed: "exclamationmark"
        default: "play.fill"
        }
    }

    private func primaryAccessibilityLabel(for id: AudioAttachmentID) -> String {
        switch playback.phase {
        case .playing, .buffering: "Pause \(id.displayTitle)"
        case .ended: "Replay \(id.displayTitle)"
        case .failed: "Retry \(id.displayTitle)"
        case .loading: "Loading \(id.displayTitle)"
        default: "Play \(id.displayTitle)"
        }
    }

    private var timeSummary: String {
        let elapsed = AudioPlaybackTime.label(position)
        let total = duration > 0 ? AudioPlaybackTime.label(duration) : "–:––"
        return "\(elapsed) / \(total)"
    }

    private func rateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    private func spokenTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }
}
