import SwiftUI

struct TodayEmptyView: View {
    var body: some View {
        VStack(spacing: ListsSpacing.s4) {
            Image(systemName: "sun.max")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
            Text("Nothing scheduled")
                .font(ListsTypography.title3)
                .foregroundStyle(ListsTokens.Foreground.secondary)
            Text("Items due today will appear here.")
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ListsSpacing.s7)
    }
}
