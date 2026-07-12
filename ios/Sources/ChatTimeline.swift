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
    var mentionIDs: Set<String> = []
    var reads: MentionReads?
    var focusMessageID: String?

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
            MessageTimelineView(
                messages: messages,
                profiles: profiles,
                mentionIDs: mentionIDs,
                reads: reads,
                focusMessageID: focusMessageID
            )
        }
    }
}

/// Indices of message rows whose frames currently intersect the viewport.
/// Rows a `LazyVStack` has not instantiated simply do not contribute, so the
/// union is exactly the set of on-screen rows.
private struct VisibleRowIndicesKey: PreferenceKey {
    static var defaultValue: Set<Int> { [] }
    static func reduce(value: inout Set<Int>, nextValue: () -> Set<Int>) {
        value.formUnion(nextValue())
    }
}

private struct MessageTimelineView: View {
    let messages: [RoomMessage]
    let profiles: ProfileBook
    let mentionIDs: Set<String>
    let reads: MentionReads?
    let focusMessageID: String?

    @State private var isPinnedToBottom = true
    @State private var visibleIndices: Set<Int> = []
    @State private var didFocus = false

    private let bottomAnchorID = "chat-bottom-anchor"
    private let scrollSpace = "chat-scroll-space"

    private var entries: [TimelineEntry] { ChatTimeline.entries(for: messages) }

    private var indexByID: [String: Int] {
        Dictionary(uniqueKeysWithValues: messages.enumerated().map { ($1.id, $0) })
    }

    /// Indices of messages that mention the user and are still unread.
    private var unreadMentionIndices: [Int] {
        guard let reads else { return [] }
        return messages.indices.filter { index in
            let message = messages[index]
            return mentionIDs.contains(message.id)
                && reads.isUnread(id: message.id, createdAt: message.createdAt)
        }
    }

    /// Unread mentions positioned above the topmost currently-visible row. Only
    /// meaningful once something is on screen, so an empty viewport yields none.
    private var unreadMentionsAbove: [Int] {
        guard let top = visibleIndices.min() else { return [] }
        return unreadMentionIndices.filter { $0 < top }
    }

    var body: some View {
        // The ScrollView fills this reader, so its height is the viewport
        // height used to decide which rows are truly on screen.
        GeometryReader { viewport in
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
                                    .background(visibilityReporter(for: message, viewportHeight: viewport.size.height))
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
                .coordinateSpace(name: scrollSpace)
                .defaultScrollAnchor(.bottom)
                .onPreferenceChange(VisibleRowIndicesKey.self) { visible in
                    updateVisible(visible)
                }
                .onChange(of: messages.last?.id) { _, _ in
                    // Only follow new messages when the reader is already at the
                    // bottom; never yank someone who scrolled up to read history.
                    guard isPinnedToBottom else { return }
                    scrollToBottom(proxy)
                }
                .onChange(of: messages.count) { _, _ in focusIfNeeded(proxy) }
                .onAppear { focusIfNeeded(proxy) }
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 10) {
                        if !unreadMentionsAbove.isEmpty {
                            JumpToMentionButton(count: unreadMentionsAbove.count) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if let target = unreadMentionsAbove.max() {
                                    scrollTo(messages[target].id, proxy: proxy)
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        if !isPinnedToBottom {
                            ScrollToBottomButton {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                scrollToBottom(proxy)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
                .animation(.easeOut(duration: 0.2), value: isPinnedToBottom)
                .animation(.easeOut(duration: 0.2), value: unreadMentionsAbove.isEmpty)
            }
        }
    }

    /// Reports a message row's index into `VisibleRowIndicesKey` only while the
    /// row's frame actually intersects the viewport. This replaces `.onAppear`,
    /// which a `LazyVStack` fires for rows it instantiates just outside the
    /// viewport — that would mark an off-screen mention read prematurely.
    private func visibilityReporter(for message: RoomMessage, viewportHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named(scrollSpace))
            let isVisible = frame.maxY > 0 && frame.minY < viewportHeight
            let indices: Set<Int> = {
                guard isVisible, let index = indexByID[message.id] else { return [] }
                return [index]
            }()
            Color.clear.preference(key: VisibleRowIndicesKey.self, value: indices)
        }
    }

    private func updateVisible(_ visible: Set<Int>) {
        visibleIndices = visible
        // A mention is read the moment it is genuinely on screen.
        for index in visible where index < messages.count {
            let message = messages[index]
            if mentionIDs.contains(message.id) { reads?.markRead(message.id) }
        }
    }

    private func focusIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didFocus,
              let focusMessageID,
              messages.contains(where: { $0.id == focusMessageID }) else {
            return
        }
        didFocus = true
        isPinnedToBottom = false
        proxy.scrollTo(focusMessageID, anchor: .center)
    }

    private func scrollTo(_ id: String, proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .center)
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

/// Floating affordance to jump up to unread mentions above the viewport,
/// mirroring `ScrollToBottomButton` but pointing up and carrying a count badge.
private struct JumpToMentionButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 6, y: -4)
                }
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel("Jump to \(count) unread \(count == 1 ? "mention" : "mentions") above")
        .accessibilityIdentifier("jump-to-mention-button")
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

