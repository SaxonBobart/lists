import SwiftUI

struct TodayView: View {
    let store: ItemStore

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    @State private var lingeringIds: Set<UUID> = []
    @State private var prefs = ListViewPreferences()
    @State private var detailItem: Item?

    private let smartList: SmartList = .today
    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var tint: Color { ListsTokens.smartColor(smartList) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            if visibleItems.isEmpty {
                TodayEmptyView()
            } else {
                SmartListCollectionView(
                    store: store,
                    prefs: prefs,
                    groups: snapshotGroups,
                    onToggleItem: { toggleAndLinger($0) },
                    onIncrementHabit: { incrementHabitAndLinger($0) },
                    onSoftDeleteItem: { id in
                        Task { try? await store.softDelete(id) }
                    },
                    onShowItemDetail: { detailItem = $0 }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            FloatingAddButton(
                tint: tint,
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
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(tint)
        .tint(tint)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                todayMenu
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, store: store)
        }
    }

    // MARK: - Snapshot

    private var snapshotGroups: [SmartListGroup] {
        var groups: [SmartListGroup] = []
        if prefs.showOverdue(for: prefsKey), !overdue.isEmpty {
            var rows: [SmartListRow] = [.sectionTitle(id: "today.overdue", text: "Overdue", isOverdue: true)]
            rows.append(contentsOf: overdue.map { .item(id: $0.id, indent: 0) })
            groups.append(SmartListGroup(id: "today.overdue", rows: rows))
        }
        if !todayItems.isEmpty {
            var rows: [SmartListRow] = [.sectionTitle(id: "today.today", text: "Today", isOverdue: false)]
            rows.append(contentsOf: todayItems.map { .item(id: $0.id, indent: 0) })
            groups.append(SmartListGroup(id: "today.today", rows: rows))
        }
        return groups
    }

    // MARK: - Sectioning

    private var rawVisible: [Item] {
        store.items(
            for: smartList,
            showCompleted: prefs.showCompleted(for: prefsKey),
            lingering: lingeringIds
        )
    }

    /// Apply the user's sort within each section. "Manual" preserves the
    /// store's by-due ordering (the default for Today).
    private var visibleItems: [Item] {
        applySort(rawVisible)
    }

    private var overdue: [Item] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return visibleItems.filter { ($0.due ?? .distantFuture) < startOfToday }
    }

    private var todayItems: [Item] {
        let cal = Calendar.current
        return visibleItems.filter { item in
            guard let due = item.due else { return false }
            return cal.isDateInToday(due)
        }
    }

    // MARK: - Sort + menu

    private func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))
    }

    @ViewBuilder
    private var todayMenu: some View {
        Menu {
            Toggle(isOn: showCompletedBinding) {
                Label("Show Completed", systemImage: "checkmark.circle")
            }
            Toggle(isOn: showOverdueBinding) {
                Label("Show Overdue", systemImage: "exclamationmark.triangle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel("View Options")
        }
    }

    private var showCompletedBinding: Binding<Bool> {
        Binding(
            get: { prefs.showCompleted(for: prefsKey) },
            set: { prefs.setShowCompleted($0, for: prefsKey) }
        )
    }

    private var showOverdueBinding: Binding<Bool> {
        Binding(
            get: { prefs.showOverdue(for: prefsKey) },
            set: { prefs.setShowOverdue($0, for: prefsKey) }
        )
    }

    /// Mirror of `ListDetailView.toggleAndLinger` — keeps a just-completed
    /// item visible for 1.5s so it fades out instead of vanishing.
    private func toggleAndLinger(_ item: Item) {
        let willComplete = !item.done
        Task { try? await store.toggleDone(item.id) }
        guard willComplete, !prefs.showCompleted(for: prefsKey) else {
            lingeringIds.remove(item.id)
            return
        }
        startLinger(for: item.id)
    }

    private func incrementHabitAndLinger(_ item: Item) {
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: .now)
        let current = item.completionLog[key] ?? 0
        let willComplete = current + 1 >= item.goalPerCycle
        Task { try? await store.incrementHabit(item.id) }
        guard willComplete, !prefs.showCompleted(for: prefsKey) else { return }
        startLinger(for: item.id)
    }

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.4)) {
                _ = lingeringIds.remove(id)
            }
        }
    }
}
