import SwiftUI

struct TodayView: View {
    let store: ItemStore

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                    Text(headerSubtitle)
                        .font(ListsTypography.footnote.weight(.semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .padding(.horizontal, ListsSpacing.s5)
                        .padding(.top, ListsSpacing.s2)

                    if visibleItems.isEmpty {
                        TodayEmptyView()
                            .padding(.top, ListsSpacing.s8)
                    } else {
                        if !overdue.isEmpty {
                            section(
                                title: "Overdue",
                                count: overdue.count,
                                tint: ListsTokens.Semantic.danger,
                                items: overdue,
                                isOverdue: true
                            )
                        }
                        if !todayItems.isEmpty {
                            section(
                                title: "Today",
                                count: todayItems.count,
                                tint: ListsTokens.Foreground.secondary,
                                items: todayItems,
                                isOverdue: false
                            )
                        }
                    }
                }
                .padding(.bottom, ListsSpacing.s9)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    AddButton(disabled: true)
                        .padding(.trailing, ListsSpacing.s5)
                        .padding(.bottom, ListsSpacing.s5)
                }
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
    }

    private var headerSubtitle: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: .now)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(
        title: String,
        count: Int,
        tint: Color,
        items: [Item],
        isOverdue: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHead(title: title, count: count, tint: tint)
            insetCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    ItemRow(item: item, isOverdue: isOverdue, store: store) {
                        Task { try? await store.toggleDone(item.id) }
                    }
                    if idx < items.count - 1 {
                        Divider()
                            .background(ListsTokens.Separator.translucent)
                            .padding(.leading, ListsDensity.rowPadX + 28 + ListsSpacing.s3)
                    }
                }
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
    }

    private func sectionHead(title: String, count: Int, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text("\(count)")
                .font(ListsTypography.monoSmall)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
            Spacer()
        }
        .padding(.horizontal, ListsSpacing.s2)
        .padding(.bottom, 2)
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

    // MARK: - Sectioned content

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
}

// MARK: - FAB

private struct AddButton: View {
    let disabled: Bool
    var body: some View {
        Button(action: {}) {
            Circle()
                .fill(ListsTokens.accent)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .opacity(disabled ? 0.5 : 1.0)
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}
