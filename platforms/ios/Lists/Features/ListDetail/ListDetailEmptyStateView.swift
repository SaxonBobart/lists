import SwiftUI

struct ListDetailEmptyStateView: View {
    let icon: String
    let color: Color

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
            Text("Tap or drag the + button to add one.")
        }
    }
}
