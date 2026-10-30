import SwiftUI

struct ContentView: View {
    // @Bindable so the view observes recovery state and the local dismissal state.
    @Bindable var store: ItemStore
    @State private var bannerDismissed = false
    @State private var calendarPreferences = CalendarPreferences()
    #if DEBUG
    @State private var sampleMoveSession = ItemMoveSession()
    @State private var sampleHierarchyReveal = ListHierarchyRevealSession()
    #endif

    var body: some View {
        Group {
            if store.isLoaded {
                #if DEBUG
                // Keep the same isolated attachment library while allowing
                // Home/Recently Deleted verification in the DEBUG harness.
                if ProcessInfo.processInfo.arguments.contains("--attachment-sample-data"),
                   !ProcessInfo.processInfo.arguments.contains("--attachment-sample-home"),
                   let list = store.lists.first(where: { $0.id == "attachment-samples" }) {
                    ListHierarchyRevealHost(session: sampleHierarchyReveal, store: store) {
                    NavigationStack {
                        ListDetailView(store: store, list: list, autoListPrefs: AutoListPreferences(),
                                       calendarPreferences: calendarPreferences, moveSession: sampleMoveSession)
                    }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if sampleMoveSession.isActive { MoveShelfView(session: sampleMoveSession, store: store) }
                    }
                    .safeAreaInset(edge: .top) {
                        Text("Sample data · isolated library").font(.caption).foregroundStyle(.secondary).padding(6)
                    }
                } else {
                    sidebar
                }
                #else
                sidebar
                #endif
            } else {
                BootstrapPlaceholder()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { PendingSaveBanner(store: store) }
    }

    private var sidebar: some View {
            SidebarView(store: store, calendarPreferences: calendarPreferences)
                .disabled(store.isReloadingFromDisk)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if MarkdownAudioRecording.shared.visibleDocuments.isEmpty { MarkdownRecordingStrip(store: store) }
                }
                .safeAreaInset(edge: .top) {
                    if (!store.loadIssues.isEmpty
                        || store.hasPendingRestoreRecovery
                        || store.hasPendingDeletionRecovery
                        || store.pendingRestoreCleanup != nil),
                       !bannerDismissed {
                        RecoveryBanner(
                            quarantinedCount: store.loadIssues.count,
                            hasPendingRestore: store.hasPendingRestoreRecovery,
                            hasPendingDeletion: store.hasPendingDeletionRecovery,
                            hasPendingCleanup: store.pendingRestoreCleanup != nil
                        ) {
                            bannerDismissed = true
                        }
                    }
                }
    }
}

/// Surfaces files that couldn't be opened or an interrupted restore that must
/// remain untouched instead of silently normalizing or purging user data.
private struct RecoveryBanner: View {
    let quarantinedCount: Int
    let hasPendingRestore: Bool
    let hasPendingDeletion: Bool
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

        if hasPendingDeletion {
            if quarantinedCount > 0 {
                let noun = quarantinedCount == 1 ? "issue" : "issues"
                return "Lists found \(quarantinedCount) recovery \(noun) while finishing a deletion. Editing the affected data is paused until recovery can safely continue."
            }
            return "Lists couldn't safely finish an interrupted deletion. Editing the affected data is paused; rebuild the library to retry."
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


/// Kept visible until the exact failed retained intents become durable.
/// Also mounted in the full-screen document, which covers the Home banner.
struct PendingSaveBanner: View {
    let store: ItemStore
    @State private var isRetrying = false

    var body: some View {
        if store.pendingSaveFailureCount > 0 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).accessibilityHidden(true)
                Text(isRetrying ? "Saving changes…" : "Some changes haven’t saved. Keep Lists open and try again.")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("persistence.unsaved.message")
                Button("Retry") {
                    guard !isRetrying else { return }
                    isRetrying = true
                    Task { @MainActor in
                        defer { isRetrying = false }
                        // Failure remains visible in the store. The existing
                        // flush retries the newest retained intent per context.
                        do { try await store.flushPendingWrites() }
                        catch { /* Keep the durable failure banner visible. */ }
                    }
                }
                .disabled(isRetrying)
                .accessibilityIdentifier("persistence.unsaved.retry")
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .accessibilityIdentifier("persistence.unsaved.banner")
        }
    }
}
