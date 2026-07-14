import Foundation

struct AudioAttachmentID: Hashable {
    let messageID: String
    let ordinal: Int
    let url: URL
}

enum AudioPlaybackPhase: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed(String)
}

enum AudioPlaybackTime {
    static func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
