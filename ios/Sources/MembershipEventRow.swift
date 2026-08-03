import SwiftUI

struct MembershipEventRow: View {
    let event: RoomMembershipEvent
    let profiles: ProfileBook

    private var displayName: String {
        profiles.displayName(for: event.pubkey, fallback: event.personLabel)
    }

    /// Moderation and self-service read differently on purpose: "was added"
    /// names an action somebody else took, "joined" names one this person
    /// took. Rendering a kind:9001 removal as "left the room" told the reader
    /// the opposite of what happened.
    private var detail: String {
        switch event.change {
        case .added: "was added to the room"
        case .removed: "was removed from the room"
        case .joined: "joined the room"
        case .left: "left the room"
        }
    }

    private var symbol: String {
        switch event.change {
        case .added: "person.badge.plus"
        case .removed: "person.badge.minus"
        case .joined: "arrow.right.circle"
        case .left: "arrow.left.circle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text("\(Text(displayName).fontWeight(.semibold)) \(detail)")
            Text(event.createdAt.formattedMembershipTime)
                .foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PlatformSupport.windowBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName) \(detail), \(event.createdAt.formattedMembershipTime)")
    }
}

private extension UInt64 {
    var formattedMembershipTime: String {
        Date(timeIntervalSince1970: TimeInterval(self))
            .formatted(date: .omitted, time: .shortened)
    }
}
