import SwiftUI

/// Generic smart-list screen for non-Today smart lists (Scheduled, Flagged,
/// Urgent, Completed, All). For Today specifically, use `TodayView`.
struct SmartListScreen: View {
    let store: ItemStore
    let smartList: SmartList

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            ScrollView {
                if items.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: smartList.iconName,
                        description: Text(emptyDescription)
                    )
                    .padding(.top, ListsSpacing.s8)
                } else {
                    insetCard {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            ItemRow(item: item, isOverdue: false, store: store) {
                                Task { try? await store.toggleDone(item.id) }
                            }
                            if idx < items.count - 1 {
                                Divider()
                                    .background(ListsTokens.Separator.translucent)
                                    .padding(.leading, ListsDensity.rowPadX + 28 + ListsSpacing.s3)
                            }
                        }
                    }
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.top, ListsSpacing.s4)
                    .padding(.bottom, ListsSpacing.s8)
                }
            }
        }
        .navigationTitle(smartList.displayName)
        .navigationBarTitleDisplayMode(.large)
    }

    private var items: [Item] {
        store.items(for: smartList)
    }

    private var emptyTitle: String {
        switch smartList {
        case .today:     return "Nothing today"
        case .scheduled: return "Nothing scheduled"
        case .flagged:   return "No flagged items"
        case .urgent:    return "No urgent items"
        case .completed: return "Nothing completed yet"
        case .all:       return "Nothing here"
        }
    }

    private var emptyDescription: String {
        switch smartList {
        case .today:     return "Items due today will appear here."
        case .scheduled: return "Items with a future date will appear here."
        case .flagged:   return "Flag an item to keep it nearby."
        case .urgent:    return "Items with the urgent trigger active will appear here."
        case .completed: return "Items you finish will appear here, sorted by completion time."
        case .all:       return "Add an item to a list to see it here."
        }
    }

    @ViewBuilder
    private func insetCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
                .fill(ListsTokens.Background.elevated)
        )
    }
}
