import SwiftUI

enum RoomPane: String, CaseIterable, Identifiable {
    case chat
    case people

    var id: Self { self }

    var label: String {
        switch self {
        case .chat: "Chat"
        case .people: "People"
        }
    }

    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .people: "person.2"
        }
    }
}

struct RoomModePicker: View {
    @Binding var selection: RoomPane

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassControl
            } else {
                materialControl
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    @available(iOS 26.0, *)
    private var liquidGlassControl: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(RoomPane.allCases) { pane in
                    if selection == pane {
                        paneButton(pane)
                            .buttonStyle(.glassProminent)
                    } else {
                        paneButton(pane)
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .buttonBorderShape(.capsule)
    }

    private var materialControl: some View {
        HStack(spacing: 4) {
            ForEach(RoomPane.allCases) { pane in
                paneButton(pane)
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == pane ? Color.white : Color.primary)
                    .background {
                        if selection == pane {
                            Capsule().fill(Color.accentColor)
                        }
                    }
            }
        }
        .padding(5)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func paneButton(_ pane: RoomPane) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                selection = pane
            }
        } label: {
            Label(pane.label, systemImage: pane.symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Capsule())
        }
        .accessibilityIdentifier("room-mode-\(pane.rawValue)")
    }
}
