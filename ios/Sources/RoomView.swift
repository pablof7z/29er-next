import NMP
import SwiftUI

struct RoomView: View {
    let group: GroupSummary
    let allGroups: [GroupSummary]
    let engine: NMPEngine
    @State private var model: RoomTimelineModel

    init(group: GroupSummary, allGroups: [GroupSummary], engine: NMPEngine) {
        self.group = group
        self.allGroups = allGroups
        self.engine = engine
        _model = State(initialValue: RoomTimelineModel(engine: engine, groupID: group.localID))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Opening room…")
            case .failed(let message):
                ContentUnavailableView(
                    "Room Unavailable",
                    systemImage: "exclamationmark.bubble",
                    description: Text(message)
                )
            case .observing:
                roomContent
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !childGroups.isEmpty {
                    NavigationLink {
                        ChildChannelsView(
                            parent: group,
                            children: childGroups,
                            allGroups: allGroups,
                            engine: engine
                        )
                    } label: {
                        Label("Subchannels", systemImage: "rectangle.stack")
                    }
                    .accessibilityIdentifier("room-subchannels-button")
                }

                NavigationLink {
                    peopleView
                } label: {
                    Label("People", systemImage: "person.2")
                }
                .accessibilityIdentifier("room-people-button")
            }
        }
        .task {
            await model.observe()
        }
    }

    private var roomContent: some View {
        ChatTimelineView(
            messages: model.messages,
            hasReceivedSnapshot: model.hasReceivedMessages,
            error: model.messageError
        )
    }

    private var childGroups: [GroupSummary] {
        GroupDirectoryProjection.directChildren(of: group, in: allGroups)
    }

    private var peopleView: some View {
        RoomPeopleView(
            people: model.people,
            hasReceivedMembership: model.hasReceivedMembership,
            hasMembershipMetadata: model.hasMembershipMetadata,
            membershipError: model.membershipError,
            hasReceivedActivities: model.hasReceivedActivities,
            activityError: model.activityError
        )
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChatTimelineView: View {
    let messages: [RoomMessage]
    let hasReceivedSnapshot: Bool
    let error: String?

    @ViewBuilder
    var body: some View {
        if let error {
            ContentUnavailableView(
                "Messages Unavailable",
                systemImage: "exclamationmark.bubble",
                description: Text(error)
            )
        } else if !hasReceivedSnapshot {
            ProgressView("Loading messages…")
        } else if messages.isEmpty {
            ContentUnavailableView(
                "No Messages Yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Messages will appear here as NMP receives room events.")
            )
        } else {
            MessageTimelineView(messages: messages)
        }
    }
}

private struct MessageTimelineView: View {
    let messages: [RoomMessage]

    @State private var isPinnedToBottom = true

    private let bottomAnchorID = "chat-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    // Sentinel that tracks whether the newest message is on screen.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                        .onAppear { isPinnedToBottom = true }
                        .onDisappear { isPinnedToBottom = false }
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.last?.id) { _, _ in
                // Only follow new messages when the reader is already at the
                // bottom; never yank someone who scrolled up to read history.
                guard isPinnedToBottom else { return }
                scrollToBottom(proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    ScrollToBottomButton { scrollToBottom(proxy) }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: isPinnedToBottom)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
}

private struct ScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel("Scroll to latest message")
        .accessibilityIdentifier("scroll-to-bottom-button")
    }
}

private struct MessageRow: View {
    let message: RoomMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.author.avatarColor.gradient)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(String(message.author.prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.authorLabel)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(message.createdAt.messageTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.content.isEmpty ? "Empty message" : message.content)
                    .font(.body)
                    .foregroundStyle(message.content.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 60)
        }
    }
}

private extension UInt64 {
    var messageTimestamp: String {
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
