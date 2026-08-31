import SwiftUI

struct TodayView: View {
    let store: ItemStore
    let defaultNewItemType: Item.ItemType
    let calendarPreferences: CalendarPreferences
    let moveSession: ItemMoveSession
    let documentLinkSession: DocumentLinkSession
    let habitsPluginEnabled: Bool

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    @State private var lingeringIds: Set<UUID> = []
    @State private var prefs = ListViewPreferences()
    @State private var detailItem: Item?
    @State private var rowMutationError: String?

    private let smartList: SmartList = .today
    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var tint: Color { ListsTokens.smartColor(smartList) }
    private var bottomContentInset: CGFloat {
        isDestinationModeActive ? 0 : 96
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
                Color(.systemBackground).ignoresSafeArea()

                if effectiveViewMode == .calendar {
                    CalendarPlannerView(
                        store: store,
                        items: calendarItems,
                        preferences: calendarPreferences,
                        surfaceKey: prefsKey,
                        tint: tint,
                        defaultListId: store.defaultCaptureListId,
                        defaultSection: nil,
                        defaultNewItemType: defaultNewItemType,
                        defaultViewKind: .day,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession
                    )
                } else if snapshotGroups.isEmpty {
                    TodayEmptyView()
                } else {
                    SmartListCollectionView(
                        store: store,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        prefs: prefs,
                        groups: snapshotGroups,
                        onToggleItem: { toggleAndLinger($0) },
                        onIncrementHabit: { incrementHabitAndLinger($0) },
                        onSoftDeleteItem: { id in
                            Task {
                                do {
                                    try await store.softDelete(id)
                                } catch {
                                    rowMutationError = error.localizedDescription
                                }
                            }
                        },
                        onMutationFailure: { rowMutationError = $0 },
                        onShowItemDetail: openOrLink,
                        bottomContentInset: bottomContentInset
                    )
                    // Full-bleed so rows scroll under the glass nav bar; the
                    // controller is auto-tracked for large-title collapse.
                    .ignoresSafeArea()
                }

                if !isDestinationModeActive && effectiveViewMode != .calendar {
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
            if !isDestinationModeActive {
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
        .itemDetailCover(
            item: $detailItem,
            store: store,
            onBeginMove: beginMove,
            onBeginDocumentLink: beginDocumentLink
        )
        .itemMutationErrorAlert($rowMutationError)
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

    private var effectiveViewMode: ListViewPreferences.ViewMode {
        let requested = prefs.viewMode(for: prefsKey)
        return requested == .columns ? .list : requested
    }

    private var calendarItems: [Item] {
        store.items.filter {
            $0.deletedAt == nil
                && $0.isAvailable(in: itemTypePolicy)
                && smartList.matches($0, includeCompleted: true)
        }
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    private var isDestinationModeActive: Bool {
        moveSession.isActive || documentLinkSession.isActive
    }

    private func openOrLink(_ item: Item) {
        if documentLinkSession.isActive {
            documentLinkSession.commit(to: item, store: store)
        } else {
            detailItem = item
        }
    }

    private func beginMove(_ item: Item) {
        documentLinkSession.cancel()
        moveSession.begin(item: item)
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        moveSession.cancel()
        documentLinkSession.begin(source: source)
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
            Menu {
                Picker(selection: viewModeBinding) {
                    ForEach(ListViewPreferences.ViewMode.queryModes, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.systemImage)
                            .tag(mode)
                            .accessibilityIdentifier("today.menu.view.\(mode.rawValue)")
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                Label {
                    Text("View As")
                    Text(effectiveViewMode.label)
                } icon: {
                    Image(systemName: effectiveViewMode.systemImage)
                }
            }
            .accessibilityIdentifier("today.menu.view")
            Divider()
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

    private var viewModeBinding: Binding<ListViewPreferences.ViewMode> {
        Binding(
            get: { effectiveViewMode },
            set: { prefs.setViewMode($0, for: prefsKey) }
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
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: prefs.showCompleted(for: prefsKey),
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
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
