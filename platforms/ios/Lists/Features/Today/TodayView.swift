import SwiftUI

struct TodayView: View {
    let store: ItemStore

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    @State private var lingeringIds: Set<UUID> = []
    @State private var prefs = ListViewPreferences()

    private let smartList: SmartList = .today
    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var tint: Color { ListsTokens.smartColor(smartList) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            if visibleItems.isEmpty {
                TodayEmptyView()
            } else {
                List {
                    if prefs.showOverdue(for: prefsKey), !overdue.isEmpty {
                        Section {
                            ForEach(Array(overdue.enumerated()), id: \.element.id) { idx, item in
                                ItemRow(
                                    item: item, isOverdue: true, store: store,
                                    onToggle: { toggleAndLinger(item) },
                                    onIncrementHabit: { incrementHabitAndLinger(item) },
                                    previousSiblingId: previousIdInSameList(at: idx, in: overdue),
                                    previousSiblingParentId: previousParentInSameList(at: idx, in: overdue)
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .transition(.opacity)
                            }
                        } header: {
                            Text("Overdue")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .textCase(nil)
                        }
                    }
                    if !todayItems.isEmpty {
                        Section {
                            ForEach(Array(todayItems.enumerated()), id: \.element.id) { idx, item in
                                ItemRow(
                                    item: item, isOverdue: false, store: store,
                                    onToggle: { toggleAndLinger(item) },
                                    onIncrementHabit: { incrementHabitAndLinger(item) },
                                    previousSiblingId: previousIdInSameList(at: idx, in: todayItems),
                                    previousSiblingParentId: previousParentInSameList(at: idx, in: todayItems)
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .transition(.opacity)
                            }
                        } header: {
                            Text("Today")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
                .animation(.easeInOut(duration: 0.4), value: lingeringIds)
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

    /// Returns the previous row's id when it shares a list with the row at
    /// `idx` (so an Indent swipe would produce a valid same-list parent).
    /// `nil` when at index 0 or the prior row is in a different list.
    private func previousIdInSameList(at idx: Int, in items: [Item]) -> UUID? {
        guard idx > 0 else { return nil }
        let prev = items[idx - 1]
        return prev.listId == items[idx].listId ? prev.id : nil
    }

    /// Mirror of `previousIdInSameList` returning the previous row's
    /// `parentId` instead — lets `ItemRow` indent a fresh top-level item
    /// directly to the previous row's level when the previous row is itself
    /// a sub-item.
    private func previousParentInSameList(at idx: Int, in items: [Item]) -> UUID? {
        guard idx > 0 else { return nil }
        let prev = items[idx - 1]
        return prev.listId == items[idx].listId ? prev.parentId : nil
    }

    // MARK: - Sort + menu

    private func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: prefsKey))
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
