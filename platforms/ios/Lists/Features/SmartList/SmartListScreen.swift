import SwiftUI

/// Generic smart-list screen for non-Today smart lists. Today specifically
/// has its own `TodayView` with day-of-week header + Overdue/Today
/// sectioning.
struct SmartListScreen: View {
    let store: ItemStore
    let smartList: SmartList

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if items.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: smartList.iconName,
                    description: Text(emptyDescription)
                )
            } else {
                List {
                    Section {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            ItemRow(
                                item: item,
                                isOverdue: isOverdue(item),
                                store: store,
                                onToggle: { Task { try? await store.toggleDone(item.id) } },
                                previousSiblingId: previousIdInSameList(at: idx, in: items)
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
            }

            // Smart lists can't accept dropped items (they're filter views,
            // not real containers) — tap the FAB to add to the default list.
            FloatingAddButton(
                tint: ListsTokens.smartColor(smartList),
                action: {
                    if let id = store.defaultCaptureListId {
                        captureTarget = CaptureTarget(listId: id, section: nil)
                    }
                },
                isInteracting: $fabIsInteracting
            )
            .opacity(store.defaultCaptureListId == nil ? 0.4 : 1)
            .allowsHitTesting(store.defaultCaptureListId != nil)
            .padding(.trailing, 16)
            .padding(.bottom, 0)
        }
        .navigationTitle(smartList.displayName)
        .navigationBarTitleDisplayMode(.large)
        .tint(ListsTokens.smartColor(smartList))
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
    }

    private var items: [Item] {
        store.items(for: smartList)
    }

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    private func previousIdInSameList(at idx: Int, in items: [Item]) -> UUID? {
        guard idx > 0 else { return nil }
        let prev = items[idx - 1]
        return prev.listId == items[idx].listId ? prev.id : nil
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
        case .today:     return "Items due today appear here."
        case .scheduled: return "Items with a future date appear here."
        case .flagged:   return "Flag an item to keep it nearby."
        case .urgent:    return "Items with the urgent trigger active appear here."
        case .completed: return "Items you finish appear here, sorted by completion time."
        case .all:       return "Add an item to a list to see it here."
        }
    }
}
