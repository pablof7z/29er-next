import Foundation

/// One rendered row in the chat timeline: a day boundary, message, or room
/// membership event.
/// `showsHeader` is false for a message that continues a run from the same
/// author within `ChatTimeline.groupingWindow`, so consecutive messages
/// collapse under a single avatar/name/timestamp header.
enum TimelineEntry: Identifiable, Hashable {
    case daySeparator(anchorID: String, label: String)
    case message(RoomMessage, showsHeader: Bool)
    case membership(RoomMembershipEvent)

    var id: String {
        switch self {
        case .daySeparator(let anchorID, _): return "day-\(anchorID)"
        case .message(let message, _): return message.id
        case .membership(let event): return event.id
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
        entries(for: messages.map(RoomTimelineItem.message), calendar: calendar)
    }

    static func entries(
        for items: [RoomTimelineItem],
        calendar: Calendar = .current
    ) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        var previous: RoomMessage?
        var previousDay: DateComponents?

        for item in items {
            let date = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            let isNewDay = day != previousDay

            if isNewDay {
                entries.append(
                    .daySeparator(
                        anchorID: item.id,
                        label: daySeparatorLabel(for: date, calendar: calendar)
                    )
                )
            }

            switch item {
            case .message(let message):
                let sameAuthor = previous?.author == message.author
                let withinWindow = previous.map {
                    message.createdAt &- $0.createdAt <= groupingWindow
                } ?? false
                let showsHeader = isNewDay || !sameAuthor || !withinWindow
                entries.append(.message(message, showsHeader: showsHeader))
                previous = message
            case .membership(let event):
                entries.append(.membership(event))
                previous = nil
            }
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
