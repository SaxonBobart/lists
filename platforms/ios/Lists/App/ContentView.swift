import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            ListsTokens.Background.grouped
                .ignoresSafeArea()

            VStack(spacing: ListsSpacing.s4) {
                RoundedRectangle(cornerRadius: ListsRadius.md, style: .continuous)
                    .fill(ListsTokens.accent)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text("Lists")
                    .font(ListsTypography.largeTitle)
                    .foregroundStyle(ListsTokens.Foreground.primary)

                Text("Calm. Honest. Yours.")
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
            }
        }
    }
}

#Preview("Light") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
