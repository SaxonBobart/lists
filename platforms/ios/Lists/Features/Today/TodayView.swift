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
                            ForEach(overdue) { item in
                                ItemRow(
                                    item: item, isOverdue: true, store: store,
                                    onToggle: { Task { try? await store.toggleDone(item.id) } }
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
                            ForEach(todayItems) { item in
                                ItemRow(
                                    item: item, isOverdue: false, store: store,
                                    onToggle: { Task { try? await store.toggleDone(item.id) } }
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
                    captureTarget = CaptureTarget(listId: ItemList.inboxId, section: nil)
                },
                isInteracting: $fabIsInteracting
            )
            .padding(.trailing, 16)
            .padding(.bottom, 24)
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
}
