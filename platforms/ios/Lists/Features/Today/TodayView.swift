import SwiftUI

struct TodayView: View {
    let store: ItemStore
    let defaultNewItemType: Item.ItemType
    let moveSession: ItemMoveSession
    let habitsPluginEnabled: Bool

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    @State private var lingeringIds: Set<UUID> = []
    @State private var prefs = ListViewPreferences()
    @State private var detailItem: Item?

    private let smartList: SmartList = .today
    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var tint: Color { ListsTokens.smartColor(smartList) }
    private var bottomContentInset: CGFloat {
        moveSession.isActive ? 0 : 96
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
                Color(.systemBackground).ignoresSafeArea()

                if snapshotGroups.isEmpty {
                    TodayEmptyView()
                } else {
                    SmartListCollectionView(
                        store: store,
                        moveSession: moveSession,
                        prefs: prefs,
                        groups: snapshotGroups,
                        onToggleItem: { toggleAndLinger($0) },
                        onIncrementHabit: { incrementHabitAndLinger($0) },
                        onSoftDeleteItem: { id in
                            Task { try? await store.softDelete(id) }
                        },
                        onShowItemDetail: { detailItem = $0 },
                        bottomContentInset: bottomContentInset
                    )
                    // Full-bleed so rows scroll under the glass nav bar; the
                    // controller is auto-tracked for large-title collapse.
                    .ignoresSafeArea()
                }

                if !moveSession.isActive {
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
                    .padding(.bottom, 16)
                }
            }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(tint)
        .tint(tint)
        .toolbar {
            if !moveSession.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    todayMenu
                }
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(
                store: store,
                defaultListId: target.listId,
                defaultSection: target.section,
                defaultNewItemType: defaultNewItemType,
                onOpenCreatedItem: { detailItem = $0 }
            )
        }
        .itemDetailCover(item: $detailItem, store: store) { moving in
            moveSession.begin(item: moving)
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

    private var sections: TodaySmartListSections {
        TodaySmartListSections.split(visibleItems, lingering: lingeringIds)
    }

    private var rawVisible: [Item] {
        store.items(
            for: smartList,
            showCompleted: prefs.showCompleted(for: prefsKey),
            lingering: lingeringIds
        )
        .filter { $0.isAvailable(in: itemTypePolicy) }
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    /// Apply the user's sort within each section. "Manual" preserves the
    /// store's by-due ordering (the default for Today).
    private var visibleItems: [Item] {
        applySort(rawVisible)
    }

    private var overdue: [Item] {
        sections.overdue
    }

    private var todayItems: [Item] {
        sections.today
    }

    // MARK: - Sort + menu

    private func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))
    }

    @ViewBuilder
    private var todayMenu: some View {
        Menu {
            Button {
                showCompletedBinding.wrappedValue.toggle()
            } label: {
                Label(
                    showCompletedBinding.wrappedValue ? "Hide Completed Items" : "Show Completed Items",
                    systemImage: showCompletedBinding.wrappedValue ? "eye.slash" : "eye"
                )
            }
            .accessibilityIdentifier("today.menu.showCompleted")
            Toggle(isOn: showOverdueBinding) {
                Label("Show Overdue", systemImage: "exclamationmark.triangle")
            }
            .accessibilityIdentifier("today.menu.showOverdue")
        } label: {
            Label("View Options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("today.menu")
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

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: prefs.showCompleted(for: prefsKey),
            lingeringIds: &lingeringIds,
            startLinger: startLinger
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: prefs.showCompleted(for: prefsKey),
            startLinger: startLinger
        )
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
