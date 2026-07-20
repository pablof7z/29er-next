import SwiftUI

/// Liquid Glass styling for the floating spoken-update chrome (mini-player,
/// transport, pills). Uses the iOS 26 `glassEffect` where available and falls
/// back to a translucent material with a hairline stroke on earlier systems.
private struct TTS29GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill((tint ?? .clear).opacity(0.18)))
                    .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func tts29Glass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(TTS29GlassBackground(shape: shape, tint: tint, interactive: interactive))
    }

    func tts29GlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        tts29Glass(in: Capsule(), tint: tint, interactive: interactive)
    }
}
