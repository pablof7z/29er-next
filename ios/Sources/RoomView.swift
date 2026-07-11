import NMP
import SwiftUI

struct RoomView: View {
    let group: GroupSummary
    @State private var model: RoomTimelineModel

    init(group: GroupSummary, engine: NMPEngine) {
        self.group = group
        _model = State(initialValue: RoomTimelineModel(engine: engine, groupID: group.id))
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
        .task {
            await model.observe()
        }
    }

    @ViewBuilder
    private var roomContent: some View {
        VStack(spacing: 0) {
            if !model.activities.isEmpty {
                ActivityStrip(activities: model.activities)
                Divider()
            }

            if model.messages.isEmpty {
                ContentUnavailableView(
                    "No Messages Yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Messages will appear here as NMP receives room events.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.messages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: model.messages.last?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct ActivityStrip: View {
    let activities: [AgentActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Working here")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(activities.count) live")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(activities) { activity in
                        ActivityCard(activity: activity)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

private struct ActivityCard: View {
    let activity: AgentActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activity.isBusy ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(activity.authorLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(activity.title.isEmpty ? "Untitled session" : activity.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(activity.activityLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 210, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
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
