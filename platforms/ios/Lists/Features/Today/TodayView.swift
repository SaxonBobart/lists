import SwiftUI

struct TodayView: View {
    let store: ItemStore

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if visibleItems.isEmpty {
                TodayEmptyView()
            } else {
                List {
                    if !overdue.isEmpty {
                        Section {
                            ForEach(Array(overdue.enumerated()), id: \.element.id) { idx, item in
                                ItemRow(
                                    item: item, isOverdue: true, store: store,
                                    onToggle: { Task { try? await store.toggleDone(item.id) } },
                                    previousSiblingId: previousIdInSameList(at: idx, in: overdue)
                                )
                            }
                        } header: {
                            Text("Overdue".uppercased())
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    if !todayItems.isEmpty {
                        Section {
                            ForEach(Array(todayItems.enumerated()), id: \.element.id) { idx, item in
                                ItemRow(
                                    item: item, isOverdue: false, store: store,
                                    onToggle: { Task { try? await store.toggleDone(item.id) } },
                                    previousSiblingId: previousIdInSameList(at: idx, in: todayItems)
                                )
                            }
                        } header: {
                            Text(todaySectionTitle.uppercased())
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
            }

            FloatingAddButton(
                tint: .yellow,  // Today's smart-list color
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
        .tint(.yellow)
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
    }

    // MARK: - Sectioning

    private var visibleItems: [Item] {
        store.items(for: .today)
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

    private var todaySectionTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: .now)
    }

    /// Returns the previous row's id when it shares a list with the row at
    /// `idx` (so an Indent swipe would produce a valid same-list parent).
    /// `nil` when at index 0 or the prior row is in a different list.
    private func previousIdInSameList(at idx: Int, in items: [Item]) -> UUID? {
        guard idx > 0 else { return nil }
        let prev = items[idx - 1]
        return prev.listId == items[idx].listId ? prev.id : nil
    }
}
