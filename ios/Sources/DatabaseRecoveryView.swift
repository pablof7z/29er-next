import SwiftUI

struct DatabaseRecoveryView: View {
    let message: String
    let canReset: Bool
    let reset: () -> Void

    @State private var confirmingReset = false

    var body: some View {
        ContentUnavailableView {
            Label("NMP Couldn’t Start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if canReset {
                Button("Reset Local Database", role: .destructive) {
                    confirmingReset = true
                }
                .accessibilityIdentifier("reset-local-database")
            }
        }
        .confirmationDialog(
            "Reset Local Database?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset and Restart", role: .destructive, action: reset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This deletes cached events, pending writes, receipts, and sync evidence. "
                + "Your saved account remains available for automatic login."
            )
        }
    }
}
