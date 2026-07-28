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
            get: { self.reactionDeliveryFailure },
            set: { self.reactionDeliveryFailure = $0 }
        )
    }
}
