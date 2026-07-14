import SwiftUI

@main
struct TwentyNinerNextApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacRootView(model: model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 980, height: 720)
        #else
        WindowGroup {
            #if NMP_DEVICE_PROOF
            ProofLaunchRootView()
            #else
            AppRootView()
            #endif
        }
        #endif
    }
}

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
        }
    }
}

private enum ProofLaunchMode {
    case inert
    case corpusPreflight
    case roomOpenProof

    static let current = ProofLaunchMode(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        if arguments.contains("--nmp-room-open-proof") {
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
