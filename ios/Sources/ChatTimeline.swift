import SwiftUI

struct ChatTimelineView: View {
    let items: [RoomTimelineItem]
    let profiles: ProfileBook
    let people: RoomPeople
    let tts29Catalog: TTS29Catalog
    let hasReceivedSnapshot: Bool
    let error: String?
    let profileError: String?
    let mentionIDs: Set<String>
    let reads: MentionReads?
    let focusMessageID: String?
    let onOpenLink: (URL) -> Void
    let onOpenImage: (URL) -> Void
    let onReply: (RoomMessage) -> Void
    let onOpenSpoken: (TTS29Item) -> Void

    private var visibleItems: [RoomTimelineItem] {
        items.filter { item in
            guard let message = item.message else { return true }
            return !tts29Catalog.isHiddenMessage(id: message.id)
        }
    }

    private var presentation: ChatTimelinePresentation {
        ChatTimelinePresentation.make(
            itemCount: visibleItems.count,
            hasReceivedSnapshot: hasReceivedSnapshot,
            error: error,
            profileError: profileError
        )
    }

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .unavailable(let error):
            ContentUnavailableView(
                "Messages Unavailable",
                systemImage: "exclamationmark.bubble",
                description: Text(error)
            )
        case .loading:
            ProgressView("Loading messages…")
        case .empty:
            ContentUnavailableView(
                "No Messages Yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Messages will appear here as NMP receives room events.")
            )
        case .messages(let profileNotice):
            MessageTimelineView(
                items: visibleItems,
                profiles: profiles,
                people: people,
                tts29Catalog: tts29Catalog,
                mentionIDs: mentionIDs,
                reads: reads,
                focusMessageID: focusMessageID,
                onOpenLink: onOpenLink,
                onOpenImage: onOpenImage,
                onReply: onReply,
                onOpenSpoken: onOpenSpoken
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                if let profileNotice {
                    DegradedStateNotice(profileNotice)
                }
            }
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
    let items: [RoomTimelineItem]
    let profiles: ProfileBook
    let people: RoomPeople
    let tts29Catalog: TTS29Catalog
    let mentionIDs: Set<String>
    let reads: MentionReads?
    let focusMessageID: String?
    let onOpenLink: (URL) -> Void
    let onOpenImage: (URL) -> Void
    let onReply: (RoomMessage) -> Void
    let onOpenSpoken: (TTS29Item) -> Void

    @Environment(TTS29PlaybackController.self) private var spokenPlayback
    @State private var isPinnedToBottom = true
    @State private var visibleIndices: Set<Int> = []
    @State private var didFocus = false

    private let bottomAnchorID = "chat-bottom-anchor"
    private let scrollSpace = "chat-scroll-space"

    private var messages: [RoomMessage] { items.compactMap(\.message) }

    private var entries: [TimelineEntry] { ChatTimeline.entries(for: items) }

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
                                messageOrSpokenCard(message, showsHeader: showsHeader)
                                    .id(entry.id)
                                    .background(visibilityReporter(for: message, viewportHeight: viewport.size.height))
                            case .membership(let event):
                                MembershipEventRow(event: event, profiles: profiles)
                                    .id(entry.id)
                            }
                        }

                        // Sentinel that tracks whether the newest timeline item is on screen.
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                            .anchorPreference(
                                key: BottomAnchorBoundsKey.self,
                                value: .bounds,
                                transform: { $0 }
                            )
                    }
                }
                .coordinateSpace(name: scrollSpace)
                .defaultScrollAnchor(.bottom)
                .onPreferenceChange(VisibleRowIndicesKey.self) { visible in
                    updateVisible(visible)
                }
                .onChange(of: items.last?.id) { _, _ in
                    // Only follow new activity when the reader is already at the
                    // bottom; never yank someone who scrolled up to read history.
                    guard isPinnedToBottom else { return }
                    scrollToBottom(proxy)
                }
                .onChange(of: messages.count) { _, _ in
                    focusIfNeeded(proxy)
                }
                .onAppear { focusIfNeeded(proxy) }
                .overlayPreferenceValue(BottomAnchorBoundsKey.self) { anchor in
                    if let anchor {
                        GeometryReader { geometry in
                            let frame = geometry[anchor]
                            let isVisible = ChatTimelineViewport.bottomAnchorIsVisible(
                                frame: frame,
                                viewportHeight: geometry.size.height
                            )
                            Color.clear
                                .onAppear { isPinnedToBottom = isVisible }
                                .onChange(of: isVisible) { _, visible in
                                    isPinnedToBottom = visible
                                }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 10) {
                        if !unreadMentionsAbove.isEmpty {
                            JumpToMentionButton(count: unreadMentionsAbove.count) {
                                PlatformSupport.performLightImpact()
                                if let target = unreadMentionsAbove.max() {
                                    scrollTo(messages[target].id, proxy: proxy)
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        if !isPinnedToBottom {
                            ScrollToBottomButton {
                                PlatformSupport.performLightImpact()
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

    /// A spoken-update card for a TTS29 item, or an ordinary message row.
    @ViewBuilder
    private func messageOrSpokenCard(_ message: RoomMessage, showsHeader: Bool) -> some View {
        if let item = tts29Catalog.item(id: message.id) {
            TTS29Card(
                item: item,
                isActive: spokenPlayback.isActive(item),
                isPlaying: spokenPlayback.isActive(item) && spokenPlayback.isPlaying,
                onOpen: { onOpenSpoken(item) }
            )
        } else {
            MessageRow(
                message: message,
                showsHeader: showsHeader,
                profiles: profiles,
                agentActivity: people.activity(for: message.author),
                onOpenLink: onOpenLink,
                onOpenImage: onOpenImage,
                onReply: { onReply(message) }
            )
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

private struct BottomAnchorBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
