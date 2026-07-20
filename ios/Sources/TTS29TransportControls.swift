import SwiftUI

/// The bottom transport cluster in the full player: a scrubber with elapsed and
/// remaining time, skip controls, and a play/pause button.
struct TTS29TransportCluster: View {
    @Bindable var playback: TTS29PlaybackController
    let item: TTS29Item

    @State private var scrubbing: Double?

    private var duration: Double { playback.duration }
    private var fraction: Double { scrubbing ?? playback.progress }
    private var canSeek: Bool { duration > 0 }

    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { fraction },
                    set: { scrubbing = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing, let value = scrubbing {
                        playback.seek(toFraction: value)
                        scrubbing = nil
                    }
                }
            )
            .disabled(!canSeek)
            .tint(.accentColor)

            HStack {
                Text(TTS29Formatting.clock(fraction * duration))
                Spacer()
                Text("-" + TTS29Formatting.clock(max(duration - fraction * duration, 0)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                skipButton("gobackward.15", label: "Back 15 seconds") { playback.skip(by: -15) }
                playPauseButton
                skipButton("goforward.15", label: "Forward 15 seconds") { playback.skip(by: 15) }
            }
        }
        .padding(16)
        .tts29Glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var playPauseButton: some View {
        Button {
            playback.toggle(item)
        } label: {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                Image(systemName: playSymbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: playback.isPlaying)
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        .accessibilityIdentifier("tts29-play-toggle")
    }

    private func skipButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!canSeek)
        .accessibilityLabel(label)
    }

    private var playSymbol: String {
        switch playback.phase {
        case .playing, .loading: "pause.fill"
        case .ended: "arrow.counterclockwise"
        case .failed: "exclamationmark"
        default: "play.fill"
        }
    }
}

/// The toolbar speed control: a menu of playback rates persisted per agent.
struct TTS29SpeedControl: View {
    @Bindable var playback: TTS29PlaybackController

    var body: some View {
        Menu {
            Picker("Playback speed", selection: Binding(
                get: { playback.rate },
                set: { playback.setRate($0) }
            )) {
                ForEach(TTS29PlaybackRateStore.menu, id: \.self) { rate in
                    Text(rate.tts29RateLabel).tag(rate)
                }
            }
        } label: {
            Text(playback.rate.tts29RateLabel)
                .font(.footnote.monospacedDigit().weight(.semibold))
                .frame(minWidth: 38)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(playback.rate.tts29RateLabel)
        .accessibilityIdentifier("tts29-speed")
    }
}
