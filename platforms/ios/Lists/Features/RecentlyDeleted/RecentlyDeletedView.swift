import SwiftUI

/// Shows soft-deleted items + lists in a `.plain` SwiftUI List with the
/// same row treatment as live lists (title, body, date, tags). Leading
/// swipe = Restore (sage); trailing swipe = Delete Forever (red, with
/// confirm). 30-day auto-purge runs on bootstrap.
struct RecentlyDeletedView: View {
    let store: ItemStore

    @State private var pendingPurgeItem: Item?
    @State private var pendingPurgeList: ItemList?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if store.deletedItems.isEmpty && store.deletedLists.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "trash",
                    description: Text("Deleted items and lists appear here for 30 days, then auto-purge.")
                )
            } else {
                List {
                    if !store.deletedLists.isEmpty {
                        Section {
                            ForEach(store.deletedLists) { list in
                                deletedListRow(list)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                            }
                        } header: {
                            sectionHeader("Lists")
                        }
                    }
                    if !store.deletedItems.isEmpty {
                        Section {
                            ForEach(store.deletedItems) { item in
                                deletedItemRow(item)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                            }
                        } header: {
                            sectionHeader("Items")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(ListsTokens.Semantic.danger)
        .tint(ListsTokens.Semantic.danger)
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

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Item row (mirror of ItemRow visual treatment, sans checkbox)

    private func deletedItemRow(_ item: Item) -> some View {
        HStack(alignment: .titleCenterDeleted, spacing: ListsSpacing.s3) {
            Image(systemName: "trash")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28)
                .alignmentGuide(.titleCenterDeleted) { d in d[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(ListsTypography.body)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .lineLimit(2)
                    .alignmentGuide(.titleCenterDeleted) { d in d[VerticalAlignment.center] }

                if !item.body.isEmpty {
                    Text(item.body.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(ListsTypography.subheadline)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(1)
                }

                metaRow(date: item.deletedAt, allDay: false, tags: item.tags, prefix: "Deleted")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.horizontal, ListsDensity.rowPadX)
        .contentShape(Rectangle())
        .accessibilityIdentifier("recentlyDeleted.item.\(item.id.uuidString)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { try? await store.restore(item.id) }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(ListsTokens.accent)
            .accessibilityIdentifier("recentlyDeleted.item.\(item.id.uuidString).swipe.restore")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingPurgeItem = item
            } label: {
                Label("Delete Forever", systemImage: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier("recentlyDeleted.item.\(item.id.uuidString).swipe.deleteForever")
        }
    }

    // MARK: - List row

    private func deletedListRow(_ list: ItemList) -> some View {
        HStack(alignment: .titleCenterDeleted, spacing: ListsSpacing.s3) {
            IconBadge(systemName: list.icon, hue: ListsTokens.listColor(list.color))
                .alignmentGuide(.titleCenterDeleted) { d in d[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(ListsTypography.body)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .lineLimit(2)
                    .alignmentGuide(.titleCenterDeleted) { d in d[VerticalAlignment.center] }

                if let when = list.deletedAt {
                    Text("Deleted \(relative(when))")
                        .font(ListsTypography.footnote)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.horizontal, ListsDensity.rowPadX)
        .contentShape(Rectangle())
        .accessibilityIdentifier("recentlyDeleted.list.\(list.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { try? await store.restoreList(list.id) }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(ListsTokens.accent)
            .accessibilityIdentifier("recentlyDeleted.list.\(list.id).swipe.restore")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingPurgeList = list
            } label: {
                Label("Delete Forever", systemImage: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier("recentlyDeleted.list.\(list.id).swipe.deleteForever")
        }
    }

    @ViewBuilder
    private func metaRow(date: Date?, allDay: Bool, tags: [String], prefix: String) -> some View {
        let dateText: String? = date.map { "\(prefix) \(relative($0))" }
        if dateText != nil || !tags.isEmpty {
            HStack(spacing: 6) {
                if let dateText {
                    Text(dateText)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                }
                if !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
                        .foregroundStyle(ListsTokens.tagAccent)
                }
            }
            .font(ListsTypography.footnote)
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }
}

private extension VerticalAlignment {
    enum TitleCenterDeletedID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let titleCenterDeleted = VerticalAlignment(TitleCenterDeletedID.self)
}
