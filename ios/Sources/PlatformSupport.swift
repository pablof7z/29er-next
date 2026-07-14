import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PlatformSupport {
    static var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    static var windowBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var secondaryGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var separator: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }

    @MainActor
    static func performLightImpact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
        #endif
    }

    @MainActor
    static func copyToPasteboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformIdentityPresentation() -> some View {
        #if os(iOS)
        presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        #else
        frame(width: 480)
        #endif
    }

    @ViewBuilder
    func platformRecipientPickerPresentation() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
        #else
        frame(minWidth: 520, minHeight: 480)
        #endif
    }

    @ViewBuilder
    func platformSecretEntry() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)
        #else
        self
        #endif
    }
}
