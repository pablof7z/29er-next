import SwiftUI

/// Presentation-only workspace color selection. This mirrors tenex-edge's
/// 64-bit FNV-style hash and six-color choice so a workspace remains visually
/// stable across the CLI and native app.
enum WorkspaceTint {
    static func paletteIndex(for seed: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash = hash &* 0x0000_0100_0000_01b3
            hash ^= UInt64(byte)
        }
        return Int(hash % 6)
    }

    static func color(for seed: String) -> Color {
        switch paletteIndex(for: seed) {
        case 0: return .cyan
        case 1: return .green
        case 2: return .orange
        case 3: return .pink
        case 4: return .blue
        default: return .red
        }
    }
}
