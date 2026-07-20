import SwiftUI

/// The visual identity of a spoken item's author: a display name, initials, and
/// a deterministic gradient derived from the pubkey (or agent name when the
/// author pubkey is empty). The gradient uses an FNV-1a hash so it stays stable
/// across launches, unlike Swift's per-process `Hasher`.
struct TTS29Identity: Equatable {
    let agentName: String
    let author: String

    init(_ item: TTS29Item) {
        self.agentName = item.agentName
        self.author = item.author
    }

    init(agentName: String, author: String) {
        self.agentName = agentName
        self.author = author
    }

    var displayName: String {
        let trimmed = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? shortAuthor : trimmed
    }

    var shortAuthor: String {
        guard !author.isEmpty else { return "unknown" }
        if author.count > 12 {
            return "\(author.prefix(6))…\(author.suffix(4))"
        }
        return author
    }

    var initials: String {
        let words = agentName.split { $0 == " " || $0 == "-" || $0 == "_" }
        let letters = words.prefix(2).compactMap { $0.first }
        if !letters.isEmpty { return String(letters).uppercased() }
        return String(author.prefix(2)).uppercased()
    }

    private var seed: UInt64 {
        let source = author.isEmpty ? agentName : author
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private func hue(_ shift: UInt64) -> Double {
        Double((seed >> shift) & 0xFFFF) / Double(0xFFFF)
    }

    var gradientColors: [Color] {
        let first = hue(0)
        let second = (first + 0.12 + hue(24) * 0.18).truncatingRemainder(dividingBy: 1)
        return [
            Color(hue: first, saturation: 0.55, brightness: 0.82),
            Color(hue: second, saturation: 0.68, brightness: 0.62)
        ]
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A circular pubkey-gradient avatar with the agent's initials.
struct TTS29AgentAvatar: View {
    let identity: TTS29Identity
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(identity.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(identity.initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
    }
}
