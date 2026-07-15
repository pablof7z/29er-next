import SwiftUI

@main
struct TwentyNinerNextApp: App {
    @State private var audioPlayback = AudioPlaybackController()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            PersistentAudioPlayerContainer {
                MacAppRootView()
            }
                .environment(audioPlayback)
        }
        .defaultSize(width: 980, height: 720)
        #else
        WindowGroup {
            PersistentAudioPlayerContainer {
                Group {
                    #if NMP_DEVICE_PROOF
                    ProofLaunchRootView()
                    #else
                    AppRootView()
                    #endif
                }
            }
            .environment(audioPlayback)
        }
        #endif
    }
}

#if os(macOS)
private struct MacAppRootView: View {
    @State private var model = AppModel()

    var body: some View {
        MacRootView(model: model)
            .frame(minWidth: 720, minHeight: 520)
    }
}
#endif

private struct AppRootView: View {
    @State private var model = AppModel()

    var body: some View {
        RootView(model: model)
    }
}

#if NMP_DEVICE_PROOF
private struct ProofLaunchRootView: View {
    private let mode = ProofLaunchMode.current

    var body: some View {
        switch mode {
        case .inert:
            ProofInertView()
        case .corpusPreflight:
            CorpusPreflightView()
        case .roomOpenProof:
            AppRootView()
        case .audioPlayer:
            AudioPlayerProofView()
        case .attachmentComposer:
            AttachmentComposerProofView()
        }
    }
}

private enum ProofLaunchMode {
    case inert
    case corpusPreflight
    case roomOpenProof
    case audioPlayer
    case attachmentComposer

    static let current = ProofLaunchMode(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        if arguments.contains("--audio-player-proof") {
            self = .audioPlayer
        } else if arguments.contains("--attachment-composer-proof") {
            self = .attachmentComposer
        } else if arguments.contains("--nmp-room-open-proof") {
            self = .roomOpenProof
        } else if arguments.contains("--nmp-corpus-preflight") {
            self = .corpusPreflight
        } else {
            self = .inert
        }
    }
}

private struct ProofInertView: View {
    var body: some View {
        Text("inert mode=none engine=not-started")
            .font(.system(.footnote, design: .monospaced))
            .padding()
            .accessibilityIdentifier("nmp-proof-inert")
    }
}
#endif
