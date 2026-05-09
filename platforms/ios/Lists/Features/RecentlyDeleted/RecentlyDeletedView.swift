import SwiftUI

/// Shows soft-deleted items + lists. 30-day auto-purge runs on bootstrap.
/// Each row has Restore (sage) and Delete Forever (red) actions.
struct RecentlyDeletedView: View {
    let store: ItemStore

    @State private var pendingPurgeItem: Item?
    @State private var pendingPurgeList: ItemList?

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            ScrollView {
                if store.deletedItems.isEmpty && store.deletedLists.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "trash",
                        description: Text("Deleted items and lists appear here for 30 days, then auto-purge.")
                    )
                    .padding(.top, ListsSpacing.s8)
                } else {
                    VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                        if !store.deletedLists.isEmpty {
                            section(title: "Lists") {
                                ForEach(store.deletedLists) { list in
                                    listRow(list)
                                    if list.id != store.deletedLists.last?.id {
                                        Divider()
                                            .background(ListsTokens.Separator.translucent)
                                            .padding(.leading, 50)
                                    }
                                }
                            }
                        }
                        if !store.deletedItems.isEmpty {
                            section(title: "Items") {
                                ForEach(store.deletedItems) { item in
                                    itemRow(item)
                                    if item.id != store.deletedItems.last?.id {
                                        Divider()
                                            .background(ListsTokens.Separator.translucent)
                                            .padding(.leading, 50)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.top, ListsSpacing.s4)
                    .padding(.bottom, ListsSpacing.s8)
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete forever?", isPresented: Binding(
            get: { pendingPurgeItem != nil },
            set: { if !$0 { pendingPurgeItem = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let id = pendingPurgeItem?.id {
                    Task { try? await store.delete(id) }
                }
                pendingPurgeItem = nil
            }
            Button("Cancel", role: .cancel) { pendingPurgeItem = nil }
        } message: {
            if let title = pendingPurgeItem?.title {
                Text("\"\(title)\" cannot be restored.")
            }
        }
        .alert("Delete list forever?", isPresented: Binding(
            get: { pendingPurgeList != nil },
            set: { if !$0 { pendingPurgeList = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let id = pendingPurgeList?.id {
                    Task { try? await store.deleteList(id) }
                }
                pendingPurgeList = nil
            }
            Button("Cancel", role: .cancel) { pendingPurgeList = nil }
        } message: {
            if let name = pendingPurgeList?.name {
                Text("\"\(name)\" and all items in it cannot be restored.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(card)
        }
    }

    // MARK: - Rows

    private func itemRow(_ item: Item) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "doc.text", hue: ListsTokens.Hue.grey)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(ListsTypography.body)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .lineLimit(1)
                if let when = item.deletedAt {
                    Text("Deleted \(relative(when))")
                        .font(ListsTypography.footnote)
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
            }
            Spacer()
            actionButton(label: "Restore", tint: ListsTokens.accent) {
                Task { try? await store.restore(item.id) }
            }
            actionButton(label: "Delete", tint: ListsTokens.Semantic.danger) {
                pendingPurgeItem = item
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private func listRow(_ list: ItemList) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: list.icon, hue: hue(for: list.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(ListsTypography.body)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .lineLimit(1)
                if let when = list.deletedAt {
                    Text("Deleted \(relative(when))")
                        .font(ListsTypography.footnote)
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
            }
            Spacer()
            actionButton(label: "Restore", tint: ListsTokens.accent) {
                Task { try? await store.restoreList(list.id) }
            }
            actionButton(label: "Delete", tint: ListsTokens.Semantic.danger) {
                pendingPurgeList = list
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private func actionButton(label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(ListsTypography.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    private func hue(for color: ItemList.ListColor) -> Color {
        switch color {
        case .sage:   return ListsTokens.accent
        case .blue:   return ListsTokens.Hue.blue
        case .teal:   return ListsTokens.Hue.teal
        case .green:  return ListsTokens.Hue.green
        case .amber:  return ListsTokens.Hue.amber
        case .orange: return ListsTokens.Hue.orange
        case .pink:   return ListsTokens.Hue.pink
        case .purple: return ListsTokens.Hue.purple
        case .grey:   return ListsTokens.Hue.grey
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }
}
