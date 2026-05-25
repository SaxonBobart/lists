import SwiftUI

struct ContentView: View {
    // @Bindable so the view observes `loadIssues` and the local dismissal state.
    @Bindable var store: ItemStore
    @State private var bannerDismissed = false

    var body: some View {
        if store.isLoaded {
            SidebarView(store: store)
                .safeAreaInset(edge: .top) {
                    if !store.loadIssues.isEmpty && !bannerDismissed {
                        QuarantineBanner(count: store.loadIssues.count) {
                            bannerDismissed = true
                        }
                    }
                }
        } else {
            BootstrapPlaceholder()
        }
    }
}

/// DI-1: surfaces files that couldn't be opened (and were set aside) instead of
/// failing silently. Non-technical copy — frames it as a product effect, not a
/// decode error. Dismissible.
private struct QuarantineBanner: View {
    let count: Int
    let onDismiss: () -> Void

    private var message: String {
        let noun = count == 1 ? "note" : "notes"
        return "\(count) \(noun) couldn't be opened and were moved to a safe place. The rest of your lists loaded normally."
    }

    var body: some View {
        HStack(alignment: .top, spacing: ListsSpacing.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: onDismiss)
                .font(ListsTypography.footnote.weight(.semibold))
                .foregroundStyle(ListsTokens.accent)
                .accessibilityLabel("Dismiss notice")
        }
        .padding(ListsSpacing.s4)
        .background(ListsTokens.Background.grouped)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.quarantineBanner")
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
