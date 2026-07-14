import SwiftUI

struct MembershipEventRow: View {
    let event: RoomMembershipEvent
    let profiles: ProfileBook

    private var displayName: String {
        profiles.displayName(for: event.pubkey, fallback: event.personLabel)
    }

    private var detail: String {
        switch event.change {
        case .joined: "joined the room"
        case .left: "left the room"
        }
    }

    private var symbol: String {
        switch event.change {
        case .joined: "person.badge.plus"
        case .left: "person.badge.minus"
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
