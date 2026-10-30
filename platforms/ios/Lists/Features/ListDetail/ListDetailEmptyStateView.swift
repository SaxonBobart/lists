import SwiftUI

struct ListDetailEmptyStateView: View {
    let icon: String
    let color: Color
    var childCount = 0
    var onBrowseSubLists: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 10) {
                ListIconGlyph(
                    icon: icon,
                    size: 38,
                    weight: .regular,
                    color: color
                )
                Text("No items yet")
            }
        } description: {
            if childCount > 0 {
                Text("Sub-lists: \(childCount). Open them here or add an item with +.")
            } else { Text("Tap or drag the + button to add one.") }
        } actions: {
            if childCount > 0 {
                Button("Browse sub-lists", action: onBrowseSubLists)
                    .accessibilityIdentifier("list.empty.browse.sublists")
            }
        }
    }
}
