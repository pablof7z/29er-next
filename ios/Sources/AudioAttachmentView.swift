import SwiftUI

struct AudioAttachmentView: View {
    let id: AudioAttachmentID
    let displayURL: String
    let url: URL

    @Environment(AudioPlaybackController.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL
    @State private var isExpanded = false

    private var phase: AudioPlaybackPhase { playback.phase(for: id) }
    private var position: Double { playback.position(for: id) }
    private var duration: Double { playback.duration(for: id) }
    private var isActive: Bool { playback.activeID == id }
    private var canSeek: Bool { isActive && duration.isFinite && duration > 0 }

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
                GlassEffectContainer(spacing: 8) {
                    playerContent
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            } else {
                playerContent
                    .padding(12)
                    .background(
                        reduceTransparency ? AnyShapeStyle(PlatformSupport.secondaryGroupedBackground)
                            : AnyShapeStyle(.regularMaterial),
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(PlatformSupport.separator.opacity(0.55), lineWidth: 0.5)
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audio-attachment")
    }

    private var playerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleButton
            if case .failed(let detail) = phase {
                failureRow(detail: detail)
            } else {
                transport
                timeLabels
                if isExpanded { expandedControls }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
    }

    private var titleButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.headline)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if phase == .buffering {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Buffering")
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") audio controls for \(title)")
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                playback.toggle(id: id, url: url)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isActive ? 1 : 0.14))
                    if phase == .loading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: playSymbol)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(isActive ? .white : Color.accentColor)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playAccessibilityLabel)

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
            .disabled(!canSeek)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(spokenTime(position)) of \(spokenTime(duration))")
        }
    }

    private var timeLabels: some View {
        HStack {
            Text(AudioPlaybackTime.label(position))
            Spacer()
            Text(duration > 0 ? "−\(AudioPlaybackTime.label(max(0, duration - position)))" : "−:––")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var expandedControls: some View {
        HStack(spacing: 4) {
            transportButton("Restart", symbol: "backward.end.fill") {
                playback.restart()
            }
            transportButton("Back 15 seconds", symbol: "gobackward.15") {
                playback.skip(by: -15)
            }
            transportButton("Forward 15 seconds", symbol: "goforward.15") {
                playback.skip(by: 15)
            }
            Spacer(minLength: 2)
            speedMenu
            actionsMenu
        }
    }

    private func failureRow(detail: String) -> some View {
        HStack(spacing: 10) {
            Label("Couldn’t play audio", systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .help(detail)
            Spacer()
            Button("Retry") { playback.retry(id: id, url: url) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private func transportButton(
        _ label: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .accessibilityLabel(label)
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
                .frame(minWidth: 40, minHeight: 44)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Playback speed")
        .accessibilityValue("\(rateLabel(playback.playbackRate))")
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                PlatformSupport.copyToPasteboard(url.absoluteString)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                openURL(url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 36, height: 44)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("More audio actions")
    }

    private var title: String {
        let filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return filename.isEmpty ? "Audio attachment" : filename
    }

    private var source: String {
        url.host() ?? displayURL
    }

    private var playSymbol: String {
        switch phase {
        case .playing, .buffering: "pause.fill"
        case .ended: "arrow.counterclockwise"
        default: "play.fill"
        }
    }

    private var playAccessibilityLabel: String {
        switch phase {
        case .playing, .buffering: "Pause \(title)"
        case .ended: "Replay \(title)"
        case .loading: "Loading \(title)"
        default: "Play \(title)"
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    private func spokenTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }
}
