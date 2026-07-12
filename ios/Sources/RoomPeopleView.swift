import SwiftUI

struct RoomPeopleView: View {
    let people: RoomPeople
    let hasReceivedMembership: Bool
    let hasMembershipMetadata: Bool
    let membershipError: String?
    let hasReceivedActivities: Bool
    let activityError: String?
    let adminError: String?
    let profileError: String?
    let backends: [RoomBackend]
    let canSendCommands: Bool
    let sendCommand: (String, String) async -> String?

    @State private var selectedBackend: RoomBackend?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                membershipNotice

                if !backends.isEmpty {
                    backendsSection
                }

                if let adminError {
                    ObservationNotice(
                        symbol: "person.badge.key",
                        title: "Backend admins unavailable",
                        detail: adminError
                    )
                }

                if let profileError {
                    ObservationNotice(
                        symbol: "person.crop.circle.badge.exclamationmark",
                        title: "Profiles unavailable",
                        detail: profileError
                    )
                }

                if let activityError {
                    ObservationNotice(
                        symbol: "bolt.slash",
                        title: "Live status unavailable",
                        detail: activityError
                    )
                }

                if !visibleMembers.isEmpty {
                    PersonSection(
                        title: "Members",
                        detail: "Listed by the room relay",
                        people: visibleMembers,
                        isActivityLoading: !hasReceivedActivities
                    )
                } else if hasMembershipMetadata {
                    ObservationNotice(
                        symbol: "person.2.slash",
                        title: "No listed members",
                        detail: "The room's current member list is empty."
                    )
                }

                if !visibleActiveHere.isEmpty {
                    PersonSection(
                        title: "Active here",
                        detail: "Live sessions not present in the room's member list",
                        people: visibleActiveHere,
                        isActivityLoading: false
                    )
                }

                if shouldShowEmptyState {
                    ContentUnavailableView(
                        "Nobody Active",
                        systemImage: "person.2",
                        description: Text("No live session status is visible for this room.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: $selectedBackend) { backend in
            BackendCommandsSheet(
                backend: backend,
                canSend: canSendCommands,
                send: { command in await sendCommand(command, backend.pubkey) }
            )
        }
    }

    private var backendPubkeys: Set<String> { Set(backends.map(\.pubkey)) }

    // Backends get their own section; keep them out of the plain rosters so a
    // backend that is also a listed member or admin is not shown twice.
    private var visibleMembers: [RoomPerson] {
        people.members.filter { !backendPubkeys.contains($0.pubkey) }
    }
    private var visibleActiveHere: [RoomPerson] {
        people.activeHere.filter { !backendPubkeys.contains($0.pubkey) }
    }

    @ViewBuilder
    private var backendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Backends")
                    .font(.title3.weight(.semibold))
                Text("Tap to manage sessions and agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 0) {
                ForEach(Array(backends.enumerated()), id: \.element.id) { index, backend in
                    Button {
                        selectedBackend = backend
                    } label: {
                        BackendRow(backend: backend)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-backend-\(backend.pubkey)")
                    if index < backends.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var membershipNotice: some View {
        if let membershipError {
            ObservationNotice(
                symbol: "person.crop.circle.badge.exclamationmark",
                title: "Member list unavailable",
                detail: membershipError
            )
        } else if !hasReceivedMembership {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading the room's member list…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        } else if !hasMembershipMetadata {
            ObservationNotice(
                symbol: "person.crop.circle.badge.questionmark",
                title: "Member list unavailable",
                detail: "The relay has not provided kind 39002 membership metadata for this room."
            )
        }
    }

    private var shouldShowEmptyState: Bool {
        hasReceivedMembership &&
            hasReceivedActivities &&
            people.members.isEmpty &&
            people.activeHere.isEmpty &&
            !hasMembershipMetadata
    }
}

private struct PersonSection: View {
    let title: String
    let detail: String
    let people: [RoomPerson]
    let isActivityLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(people.count, format: .number)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    PersonRow(person: person, isActivityLoading: isActivityLoading)
                    if index < people.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct PersonRow: View {
    let person: RoomPerson
    let isActivityLoading: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(person.authorLabel)
                    .font(.headline)
                    .lineLimit(1)

                if let activity = person.activity {
                    if !activity.title.isEmpty {
                        Text(activity.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                    Text(activity.activityLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let host = activity.host {
                        Label(host, systemImage: "desktopcomputer")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text(isActivityLoading ? "Checking live status…" : "No live status")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let activity = person.activity {
                StatusLabel(isBusy: activity.isBusy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("room-person-\(person.pubkey)")
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            AuthorAvatar(
                pubkey: person.pubkey,
                displayName: person.authorLabel,
                pictureURL: nil,
                size: 42
            )

            if let activity = person.activity {
                Circle()
                    .fill(activity.isBusy ? Color.green : Color.secondary)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2) }
            }
        }
    }
}

private struct StatusLabel: View {
    let isBusy: Bool

    var body: some View {
        Text(isBusy ? "Busy" : "Idle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isBusy ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isBusy ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }
}
