import SwiftUI

struct AudioAttachmentView: View {
    let id: AudioAttachmentID
    let url: URL

    @Environment(AudioPlaybackController.self) private var playback
    @State private var isSeeking = false

    private var phase: AudioPlaybackPhase { playback.phase(for: id) }
    private var position: Double { playback.position(for: id) }
    private var duration: Double { playback.duration(for: id) }
    private var isActive: Bool { playback.activeID == id }
    private var canSeek: Bool { isActive && duration.isFinite && duration > 0 }

    var body: some View {
        HStack(spacing: 12) {
            playbackButton
            VStack(alignment: .leading, spacing: 3) {
                waveform
                statusLine
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 340, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.accentColor.opacity(0.1), lineWidth: 0.5)
        }
        .task(id: id) {
            await playback.prepareDuration(for: id, url: url)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audio-attachment")
    }

    private var playbackButton: some View {
        Button {
            playback.toggle(id: id, url: url)
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.accentColor.opacity(0.2))
                if phase == .loading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: playSymbol)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isActive ? .white : Color.accentColor)
                }
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playAccessibilityLabel)
        .accessibilityIdentifier("audio-attachment-playback-toggle")
    }

    private var waveform: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(waveformHeights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(waveformColor(at: index))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(seekGesture(width: geometry.size.width))
        }
        .frame(height: 31)
        .accessibilityHidden(true)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if case .failed = phase {
                Image(systemName: "exclamationmark.circle.fill")
            }
            Text(statusText)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(statusColor)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canSeek, width > 0 else { return }
                if !isSeeking {
                    isSeeking = true
                    playback.beginScrubbing()
                }
                let fraction = min(max(value.location.x / width, 0), 1)
                playback.updateScrub(to: duration * Double(fraction))
            }
            .onEnded { _ in
                guard isSeeking else { return }
                isSeeking = false
                playback.endScrubbing()
            }
    }

    private var waveformHeights: [CGFloat] {
        let pattern: [CGFloat] = [
            9, 15, 23, 13, 27, 18, 10, 21, 14, 25,
            17, 11, 20, 29, 16, 9, 14, 24, 18, 12,
            26, 19, 10, 16, 28, 13, 21, 15, 25, 11,
            18, 23, 12, 27, 16, 9, 20, 14, 24, 11
        ]
        let offset = id.messageID.unicodeScalars.reduce(0) {
            ($0 + Int($1.value)) % pattern.count
        }
        return (0..<pattern.count).map { pattern[($0 + offset) % pattern.count] }
    }

    private func waveformColor(at index: Int) -> Color {
        let progress = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let barProgress = Double(index + 1) / Double(waveformHeights.count)
        return barProgress <= progress ? Color.accentColor : Color.secondary.opacity(0.55)
    }

    private var statusText: String {
        if case .failed = phase { return "Couldn’t play" }
        if isActive, position > 0 { return AudioPlaybackTime.label(position) }
        if duration > 0 { return AudioPlaybackTime.label(duration) }
        return "Audio"
    }

    private var statusColor: Color {
        if case .failed = phase { return .red }
        return .secondary
    }

    private var playSymbol: String {
        switch phase {
        case .playing, .buffering: "pause.fill"
        case .ended, .failed: "arrow.counterclockwise"
        default: "play.fill"
        }
    }

    private var playAccessibilityLabel: String {
        switch phase {
        case .playing, .buffering: "Pause \(id.displayTitle)"
        case .ended: "Replay \(id.displayTitle)"
        case .failed: "Retry \(id.displayTitle)"
        case .loading: "Loading \(id.displayTitle)"
        default: "Play \(id.displayTitle)"
        }
    }

    private var statusAccessibilityLabel: String {
        if case .failed = phase { return "Audio failed to play" }
        return duration > 0 ? "Audio duration \(spokenTime(duration))" : "Audio duration unavailable"
    }

    private func spokenTime(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }
}
