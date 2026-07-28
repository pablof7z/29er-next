import CoreGraphics

enum ChatTimelineViewport {
    /// True when the timeline content's bottom edge is at or above the
    /// viewport's bottom edge -- i.e. there is no more content below what's
    /// currently shown, so the reader is scrolled (or pinned) to the bottom.
    ///
    /// `contentFrame` must be the whole content container's bounds (e.g. a
    /// `LazyVStack`'s `.bounds` anchor), not a single row or sentinel: a lazy
    /// container keeps reporting its full bounds even while far offscreen
    /// rows are de-instantiated, so this stays accurate at any scroll depth.
    static func isScrolledToBottom(
        contentFrame: CGRect,
        viewportHeight: CGFloat,
        tolerance: CGFloat = 4
    ) -> Bool {
        viewportHeight > 0 && contentFrame.maxY <= viewportHeight + tolerance
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
