import SwiftUI

struct ContentView: View {
    // @Bindable so the view observes recovery state and the local dismissal state.
    @Bindable var store: ItemStore
    @State private var bannerDismissed = false

    var body: some View {
        if store.isLoaded {
            SidebarView(store: store)
                .disabled(store.isReloadingFromDisk)
                .safeAreaInset(edge: .top) {
                    if (!store.loadIssues.isEmpty
                        || store.hasPendingRestoreRecovery
                        || store.pendingRestoreCleanup != nil),
                       !bannerDismissed {
                        RecoveryBanner(
                            quarantinedCount: store.loadIssues.count,
                            hasPendingRestore: store.hasPendingRestoreRecovery,
                            hasPendingCleanup: store.pendingRestoreCleanup != nil
                        ) {
                            bannerDismissed = true
                        }
                    }
                }
        } else {
            BootstrapPlaceholder()
        }
    }
}

/// Surfaces files that couldn't be opened or an interrupted restore that must
/// remain untouched instead of silently normalizing or purging user data.
private struct RecoveryBanner: View {
    let quarantinedCount: Int
    let hasPendingRestore: Bool
    let hasPendingCleanup: Bool
    let onDismiss: () -> Void

    private var message: String {
        if hasPendingRestore {
            if quarantinedCount > 0 {
                let noun = quarantinedCount == 1 ? "issue" : "issues"
                return "Lists found \(quarantinedCount) recovery \(noun) while a restore was pending. Further recovery changes and permanent deletion are paused to protect the unresolved batch."
            }
            return "Lists couldn't safely continue an interrupted restore. Further recovery changes and permanent deletion are paused to protect the unresolved batch."
        }

        if hasPendingCleanup {
            return "Your data was restored, but Lists couldn't clear its recovery lock. Permanent deletion is paused; retry from Recently Deleted."
        }

        let noun = quarantinedCount == 1 ? "issue" : "issues"
        return "Lists found \(quarantinedCount) storage recovery \(noun). Affected data was left in place or moved aside, and the rest of your lists loaded normally."
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
