import CoreGraphics

enum ChatTimelineViewport {
    static func bottomAnchorIsVisible(frame: CGRect, viewportHeight: CGFloat) -> Bool {
        viewportHeight > 0 && frame.maxY >= 0 && frame.minY <= viewportHeight
    }

    static func topVisibleMessageID(
        visibleIndices: Set<Int>,
        messageIDs: [String]
    ) -> String? {
        guard let index = visibleIndices.min(), messageIDs.indices.contains(index) else {
            return nil
        }
        return messageIDs[index]
    }
}
