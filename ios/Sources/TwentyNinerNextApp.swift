import SwiftUI

@main
struct TwentyNinerNextApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacRootView(model: model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 980, height: 720)
        #else
        WindowGroup {
            RootView(model: model)
        }
        #endif
    }
}
