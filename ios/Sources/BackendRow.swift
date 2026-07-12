import SwiftUI

/// A tappable row in the room's People roster representing a tenex-edge
/// management backend. Selecting it opens `BackendCommandsSheet`.
struct BackendRow: View {
    let backend: RoomBackend

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(backend.pubkey.avatarColor.gradient)
                Image(systemName: "desktopcomputer")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(backend.label)
                    .font(.headline)
                    .lineLimit(1)
                Text(agentSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens management commands")
    }

    private var agentSummary: String {
        switch backend.agents.count {
        case 0: return "Management backend"
        case 1: return "1 agent available"
        case let count: return "\(count) agents available"
        }
    }
}
