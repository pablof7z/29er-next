import SwiftUI

@main
struct TwentyNinerNextApp: App {
    var body: some Scene {
        WindowGroup {
            #if NMP_DEVICE_PROOF
            ProofLaunchRootView()
            #else
            AppRootView()
            #endif
        }
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
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--nmp-room-open-proof") {
            AppRootView()
        } else if ProcessInfo.processInfo.arguments.contains("--nmp-corpus-preflight") {
            CorpusPreflightView()
        } else {
            Text("inert mode=none engine=not-started")
                .font(.system(.footnote, design: .monospaced))
                .padding()
                .accessibilityIdentifier("nmp-proof-inert")
        }
    }
}
#endif
