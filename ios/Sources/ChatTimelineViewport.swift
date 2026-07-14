import CoreGraphics

enum ChatTimelineViewport {
    static func bottomAnchorIsVisible(frame: CGRect, viewportHeight: CGFloat) -> Bool {
        viewportHeight > 0 && frame.maxY >= 0 && frame.minY <= viewportHeight
    }
}
