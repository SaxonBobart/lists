import SwiftUI

struct MoveNoneDestinationRow: View {
    let listName: String
    let listColor: Color
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .center, spacing: ListsSpacing.s3) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(listColor)
                    .frame(width: 28, height: 28, alignment: .leading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("None")
                        .font(ListsTypography.body.weight(.semibold))
                        .foregroundStyle(ListsTokens.Foreground.primary)
                    Text("Top level in \(listName)")
                        .font(ListsTypography.footnote)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, ListsDensity.rowPadY)
            .padding(.horizontal, ListsDensity.rowPadX)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Move to top level in \(listName)")
        .accessibilityIdentifier("move.destination.none.button")
    }
}
