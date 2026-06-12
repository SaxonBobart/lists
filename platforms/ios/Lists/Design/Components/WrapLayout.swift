import SwiftUI

// MARK: - Wrap layout

/// Tiny flow layout that places subviews left-to-right, wrapping to a new
/// line when the next subview would overflow the proposed width. Used by
/// `TagInputView` so chips wrap naturally when there are many.
struct WrapLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += rowHeight + verticalSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        // Two passes per row: gather the row's items + its max height, then place
        // each one vertically centred. Centring is what makes a short tag chip
        // line up with the taller text field on the same row (a UITextField is
        // intrinsically taller than a `Text`; top-aligning left them misaligned).
        var index = 0
        var y = bounds.minY

        while index < subviews.count {
            var row: [(offset: Int, size: CGSize)] = []
            var x = bounds.minX
            var rowHeight: CGFloat = 0

            while index < subviews.count {
                let size = subviews[index].sizeThatFits(.unspecified)
                let isFirst = row.isEmpty
                let nextX = isFirst ? x + size.width : x + horizontalSpacing + size.width
                if !isFirst, nextX > bounds.maxX { break }
                row.append((index, size))
                x = nextX
                rowHeight = max(rowHeight, size.height)
                index += 1
            }

            var px = bounds.minX
            for item in row {
                let size = item.size
                subviews[item.offset].place(
                    at: CGPoint(x: px, y: y + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                px += size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }
    }
}
