import Foundation
import NMPUI
import SwiftUI

struct GroupRow: View {
    let group: GroupSummary
    let childCount: Int
    let entry: RoomDirectoryEntry?
    let contentObservationFactory: NMPReferenceObservationFactory?

    var body: some View {
        HStack(spacing: 12) {
            GroupAvatar(group: group)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline).lineLimit(1)
                preview
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                if let latest = entry?.latest {
                    Text(GroupRow.relativeTime(latest.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    if childCount > 0 { SubchannelCountBadge(count: childCount) }
                    if let unread = entry?.unread, unread > 0 { UnreadBadge(count: unread) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var preview: some View {
        if let message = entry?.latest,
           !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let contentObservationFactory {
            GroupContentPreview(
                message: message,
                observationFactory: contentObservationFactory
            )
            .id(message.id)
        } else {
            Text(group.about ?? group.localID)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    static func relativeTime(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return date.formatted(.dateTime.month().day())
        }
    }
}

struct SubchannelCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "rectangle.stack.fill").font(.system(size: 10))
            Text("\(count)").font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) subchannels")
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .accessibilityLabel("\(count) unread messages")
    }
}

struct GroupAvatar: View {
    let group: GroupSummary

    var body: some View {
        ZStack {
            Circle().fill(group.localID.avatarColor.gradient)
            Text(group.initials).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 46, height: 46)
    }
}

extension String {
    var avatarColor: Color {
        let value = utf8.reduce(UInt64(0xcbf29ce484222325)) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001b3
        }
        return Color(hue: Double(value % 360) / 360, saturation: 0.58, brightness: 0.78)
    }
}
