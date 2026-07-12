import SwiftUI
import UIKit

/// One rendered row in the chat timeline: either a day boundary or a message.
/// `showsHeader` is false for a message that continues a run from the same
/// author within `ChatTimeline.groupingWindow`, so consecutive messages
/// collapse under a single avatar/name/timestamp header.
enum TimelineEntry: Identifiable, Hashable {
    case daySeparator(anchorID: String, label: String)
    case message(RoomMessage, showsHeader: Bool)

    var id: String {
        switch self {
        case .daySeparator(let anchorID, _): return "day-\(anchorID)"
        case .message(let message, _): return message.id
        }
    }
}

enum ChatTimeline {
    /// Consecutive messages from one author within this window share a header.
    static let groupingWindow: UInt64 = 5 * 60

    static func entries(
        for messages: [RoomMessage],
        calendar: Calendar = .current
    ) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        var previous: RoomMessage?
        var previousDay: DateComponents?

        for message in messages {
            let date = Date(timeIntervalSince1970: TimeInterval(message.createdAt))
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            let isNewDay = day != previousDay

            if isNewDay {
                entries.append(
                    .daySeparator(
                        anchorID: message.id,
                        label: daySeparatorLabel(for: date, calendar: calendar)
                    )
                )
            }

            let sameAuthor = previous?.author == message.author
            let withinWindow = previous.map { message.createdAt &- $0.createdAt <= groupingWindow } ?? false
            let showsHeader = isNewDay || !sameAuthor || !withinWindow
            entries.append(.message(message, showsHeader: showsHeader))

            previous = message
            previousDay = day
        }

        return entries
    }

    static func daySeparatorLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.year().month(.wide).day())
    }
}

struct ChatTimelineView: View {
    let messages: [RoomMessage]
    let profiles: ProfileBook
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
            MessageTimelineView(messages: messages, profiles: profiles)
        }
    }
}

private struct MessageTimelineView: View {
    let messages: [RoomMessage]
    let profiles: ProfileBook

    @State private var isPinnedToBottom = true

    private let bottomAnchorID = "chat-bottom-anchor"

    private var entries: [TimelineEntry] { ChatTimeline.entries(for: messages) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .daySeparator(_, let label):
                            DaySeparatorRow(label: label)
                                .id(entry.id)
                        case .message(let message, let showsHeader):
                            MessageRow(message: message, showsHeader: showsHeader, profiles: profiles)
                                .id(entry.id)
                        }
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
                    ScrollToBottomButton {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        scrollToBottom(proxy)
                    }
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

private struct DaySeparatorRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            line
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var line: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 0.5)
    }
}

