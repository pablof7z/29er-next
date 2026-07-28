#if os(iOS)
import SwiftUI

/// Repositions one stable composer editor between collapsed and expanded layouts.
///
/// The subview order is leading action, editor, mention strip, trailing action.
/// Keeping those subviews in one `Layout` prevents keyboard focus from being lost
/// when the editor moves from the collapsed row to the expanded top row.
struct ComposerTextReflowLayout: Layout {
    let isExpanded: Bool
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 4 else { return .zero }
        let width = resolvedWidth(proposal: proposal, subviews: subviews)
        return isExpanded
            ? expandedSize(width: width, subviews: subviews)
            : collapsedSize(width: width, subviews: subviews)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 4 else { return }
        if isExpanded {
            placeExpanded(in: bounds, subviews: subviews)
        } else {
            placeCollapsed(in: bounds, subviews: subviews)
        }
    }

    private func resolvedWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width { return max(0, width) }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let editor = subviews[1].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        return leading.width + editor.width + trailing.width + spacing * 2
    }

    private func collapsedSize(width: CGFloat, subviews: Subviews) -> CGSize {
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        let editorWidth = availableMiddleWidth(
            totalWidth: width,
            leadingWidth: leading.width,
            trailingWidth: trailing.width
        )
        let editor = subviews[1].sizeThatFits(
            ProposedViewSize(width: editorWidth, height: nil)
        )
        return CGSize(
            width: width,
            height: max(leading.height, max(editor.height, trailing.height))
        )
    }

    private func expandedSize(width: CGFloat, subviews: Subviews) -> CGSize {
        let editor = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        let mentionWidth = availableMiddleWidth(
            totalWidth: width,
            leadingWidth: leading.width,
            trailingWidth: trailing.width
        )
        let mentions = subviews[2].sizeThatFits(
            ProposedViewSize(width: mentionWidth, height: nil)
        )
        let controlsHeight = max(leading.height, max(mentions.height, trailing.height))
        return CGSize(width: width, height: editor.height + spacing + controlsHeight)
    }

    private func placeCollapsed(in bounds: CGRect, subviews: Subviews) {
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        let editorWidth = availableMiddleWidth(
            totalWidth: bounds.width,
            leadingWidth: leading.width,
            trailingWidth: trailing.width
        )

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(leading)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leading.width + spacing, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: editorWidth, height: nil)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX + leading.width + spacing, y: bounds.midY),
            anchor: .leading,
            proposal: .zero
        )
        subviews[3].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(trailing)
        )
    }

    private func placeExpanded(in bounds: CGRect, subviews: Subviews) {
        let editorProposal = ProposedViewSize(width: bounds.width, height: nil)
        let editor = subviews[1].sizeThatFits(editorProposal)
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        let mentionWidth = availableMiddleWidth(
            totalWidth: bounds.width,
            leadingWidth: leading.width,
            trailingWidth: trailing.width
        )
        let mentionProposal = ProposedViewSize(width: mentionWidth, height: nil)
        let mentions = subviews[2].sizeThatFits(mentionProposal)
        let controlsHeight = max(leading.height, max(mentions.height, trailing.height))
        let controlsY = bounds.minY + editor.height + spacing + controlsHeight / 2

        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: editorProposal
        )
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: controlsY),
            anchor: .leading,
            proposal: ProposedViewSize(leading)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX + leading.width + spacing, y: controlsY),
            anchor: .leading,
            proposal: mentionProposal
        )
        subviews[3].place(
            at: CGPoint(x: bounds.maxX, y: controlsY),
            anchor: .trailing,
            proposal: ProposedViewSize(trailing)
        )
    }

    private func availableMiddleWidth(
        totalWidth: CGFloat,
        leadingWidth: CGFloat,
        trailingWidth: CGFloat
    ) -> CGFloat {
        max(0, totalWidth - leadingWidth - trailingWidth - spacing * 2)
    }
}
#endif
