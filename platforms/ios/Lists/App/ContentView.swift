import SwiftUI

struct ContentView: View {
    let store: ItemStore

    var body: some View {
        if store.isLoaded {
            NavigationStack {
                SidebarView(store: store)
            }
            .tint(ListsTokens.accent)
        } else {
            BootstrapPlaceholder()
        }
    }
}

private struct BootstrapPlaceholder: View {
    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()
            VStack(spacing: ListsSpacing.s4) {
                ProgressView()
                    .controlSize(.large)
                    .tint(ListsTokens.accent)
                Text("Loading your lists…")
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
            }
        }
    }
}
