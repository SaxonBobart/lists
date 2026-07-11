import SwiftUI

struct RebuildLibraryView: View {
    let store: ItemStore
    @Binding var isRebuilding: Bool

    @State private var status: RebuildStatus = .idle

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            VStack(spacing: ListsSpacing.s5) {
                Image(systemName: status.iconName)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(status.iconColor)
                    .accessibilityHidden(true)

                Text(status.title)
                    .font(ListsTypography.title3)
                    .multilineTextAlignment(.center)

                Text(status.message)
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ListsSpacing.s7)

                Button {
                    rebuild()
                } label: {
                    Label(
                        isRebuilding || store.isReloadingFromDisk ? "Rebuilding" : "Rebuild Now",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(ListsTokens.accent)
                .disabled(isRebuilding || store.isReloadingFromDisk)
                .accessibilityIdentifier("settings.rebuildCache.run")
            }
            .padding(.top, ListsSpacing.s8)
        }
        .navigationTitle("Rebuild Cache")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isRebuilding || store.isReloadingFromDisk)
        .accessibilityIdentifier("settings.rebuildCache.screen")
    }

    private func rebuild() {
        guard !isRebuilding else { return }
        isRebuilding = true
        status = .working
        Task {
            do {
                try await store.reloadFromDisk()
                status = .success(
                    lists: store.lists.filter { $0.deletedAt == nil }.count,
                    items: store.items.filter { $0.deletedAt == nil }.count,
                    issues: store.loadIssues.count,
                    pendingRecovery: store.hasPendingRestoreRecovery
                        || store.hasPendingDeletionRecovery
                        || store.pendingRestoreCleanup != nil
                )
            } catch {
                status = .failure(error.localizedDescription)
            }
            isRebuilding = false
        }
    }
}
