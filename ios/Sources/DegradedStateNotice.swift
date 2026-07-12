import SwiftUI

struct DegradedStateNotice: View {
    let notice: NoticeContent

    init(_ notice: NoticeContent) {
        self.notice = notice
    }

    init(title: String, message: String) {
        self.notice = NoticeContent(
            symbol: "exclamationmark.triangle.fill",
            title: title,
            message: message
        )
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.footnote.weight(.semibold))
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: notice.symbol)
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}
