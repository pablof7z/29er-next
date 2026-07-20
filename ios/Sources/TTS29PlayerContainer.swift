import SwiftUI

/// Hosts the app-level spoken-update chrome: the docked mini-player and the
/// full player surface. Wrapping the app content here keeps playback alive
/// across channel navigation.
struct TTS29PlayerContainer<Content: View>: View {
    @Environment(TTS29PlaybackController.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: Content

    private var showsMiniPlayer: Bool {
        playback.selectedItem != nil && playback.presentedRoot == nil
    }

    var body: some View {
        @Bindable var playback = playback
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsMiniPlayer, let item = playback.selectedItem {
                    TTS29MiniPlayer(playback: playback, item: item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: showsMiniPlayer)
            .modifier(TTS29PlayerPresentation(playback: playback))
    }
}

/// Presents the full player as a full-screen cover on iOS and a sheet on macOS,
/// mirroring how the room presents images and the browser.
private struct TTS29PlayerPresentation: ViewModifier {
    @Bindable var playback: TTS29PlaybackController

    private var presented: Binding<TTS29Item?> {
        Binding(
            get: { playback.presentedRoot },
            set: { playback.presentedRoot = $0 }
        )
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: presented) { root in
            TTS29PlayerView(root: root, playback: playback)
        }
        #else
        content.sheet(item: presented) { root in
            TTS29PlayerView(root: root, playback: playback)
                .frame(minWidth: 560, minHeight: 640)
        }
        #endif
    }
}
