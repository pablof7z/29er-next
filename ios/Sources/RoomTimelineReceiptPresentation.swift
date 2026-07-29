import SwiftUI

extension RoomTimelineModel {
    var messageDeliveryProgress: String? {
        messageReceiptPresentation.progressMessage(currentState: messageDeliveryState)
    }

    var messageDeliveryFailure: String? {
        messageReceiptPresentation.failureMessage(currentState: messageDeliveryState)
    }

    var reactionDeliveryFailureBinding: Binding<String?> {
        Binding(
            get: { self.reactionReceiptPresentation.currentFailureMessage },
            set: { value in
                if value == nil {
                    self.reactionReceiptPresentation.dismissCurrentFailure()
                }
            }
        )
    }
}
