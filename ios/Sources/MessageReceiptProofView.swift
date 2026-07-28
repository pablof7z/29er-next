#if NMP_DEVICE_PROOF
import NMP
import SwiftUI

struct MessageReceiptProofView: View {
    private let receiptID: UInt64 = 77
    @State private var state = MessageDeliveryState.idle

    var body: some View {
        VStack(spacing: 18) {
            Text(report)
                .font(.footnote.monospaced())
                .accessibilityIdentifier("message-receipt-proof-state")

            ComposerDeliveryStatus(
                progressMessage: state.progressMessage,
                errorMessage: state.failureMessage
            )

            Button("Accepted") {
                state = .applying(.accepted, receiptID: receiptID)
            }
            .accessibilityIdentifier("message-receipt-proof-accepted")

            Button("Acknowledged") {
                state = .applying(
                    .acked(relay: "wss://groups.example"),
                    receiptID: receiptID
                )
            }
            .accessibilityIdentifier("message-receipt-proof-acked")

            Button("Rejected") {
                state = .applying(
                    .rejected(relay: "wss://groups.example", reason: "permission denied"),
                    receiptID: receiptID
                )
            }
            .accessibilityIdentifier("message-receipt-proof-rejected")

            Button("Ambiguous") {
                state = .applying(
                    .outcomeUnknown(relay: "wss://groups.example"),
                    receiptID: receiptID
                )
            }
            .accessibilityIdentifier("message-receipt-proof-ambiguous")
        }
        .padding()
    }

    private var report: String {
        switch state {
        case .idle:
            return "idle terminal=false"
        case .progressing(let receiptID, let progress):
            return "receipt=\(receiptID.map(String.init) ?? "none") "
                + "progress=\(progress.message) terminal=false"
        case .acknowledged(let receiptID, let relay):
            return "receipt=\(receiptID) acked=\(relay) terminal=true"
        case .failed(let receiptID, let failure):
            return "receipt=\(receiptID.map(String.init) ?? "none") "
                + "failure=\(failure.message) terminal=true"
        case .converged(let receiptID, let relays, let failures):
            return "receipt=\(receiptID) acked=\(relays.joined(separator: ",")) "
                + "failures=\(failures.map(\.message).joined(separator: ",")) terminal=true"
        }
    }
}
#endif
