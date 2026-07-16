import SwiftUI

struct ChatHistoryControl: View {
    let state: ChatHistoryLoadState
    let load: () -> Void

    var body: some View {
        Group {
            switch state {
            case .ready:
                loadButton("Load Earlier Messages")
            case .loading:
                ProgressView("Loading earlier messages…")
                    .accessibilityIdentifier("chat-history-loading")
            case .noRowsReturned:
                VStack(spacing: 6) {
                    Text("No earlier messages received from the current relay plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    loadButton("Try Again")
                }
            case .atBound(let max):
                Label("History limit reached (\(max) events)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("chat-history-at-bound")
            case .failed(let message):
                VStack(spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    loadButton("Retry Earlier Messages")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func loadButton(_ title: String) -> some View {
        Button(title, action: load)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("chat-load-earlier")
    }
}
