import SwiftUI

/// Visual content for a sidebar list cell. The UIKit collection view owns row
/// navigation and the trailing collapse/expand tap zone.
struct SidebarListCellContent: View {
    let list: ItemList
    let depth: Int
    let hasChildren: Bool
    let isCollapsed: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            SidebarRow(
                icon: list.icon,
                hue: ListsTokens.listColor(list.color),
                label: list.name,
                count: count > 0 ? count : nil,
                indent: depth,
                iconShape: .circle
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasChildren {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            } else {
                DecorativeChevron()
            }
        }
    }
}
