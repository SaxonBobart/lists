import SwiftUI

/// The footnote meta line beneath an item's title — due date (red when
/// overdue), repeat cadence, and tags. Shared by `ItemRow` and the inline
/// editor (`InlineItemEditor`) so an item's date/tags stay visible and pixel-
/// identical while editing in place. Renders nothing when there's no meta.
struct ItemMetaLine: View {
    let item: Item
    let isOverdue: Bool

    var body: some View {
        let hasDateMeta = ItemFactChips.hasFacts(for: item)
        let hasTags = !item.tags.isEmpty
        if hasDateMeta || hasTags {
            VStack(alignment: .leading, spacing: 2) {
                if hasDateMeta {
                    ItemFactChips(item: item, isOverdue: isOverdue)
                }
                if hasTags {
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(ListsTypography.subheadline)
                        .foregroundStyle(ListsTokens.tagAccent)
                }
            }
        }
    }

    /// The date portion of the meta line (no tags). Exposed so the inline
    /// editor can render the same date string beside its editable tag field.
    static func dateString(for item: Item) -> String? {
        ItemFactChips.dateString(for: item)
    }

    /// The end-of-span string for an event's meta line — time-only when the
    /// event ends the same day it starts (timed), otherwise a short date.
    /// Mirrors the document view's fact strip. `nil` for non-events or events
    /// without an end. Exposed so the inline editor and document view share one
    /// end formatter.
    static func endString(for item: Item) -> String? {
        ItemFactChips.endString(for: item)
    }
}
