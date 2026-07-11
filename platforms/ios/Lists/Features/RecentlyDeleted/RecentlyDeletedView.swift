import SwiftUI

/// Shows soft-deleted items + lists in a `.plain` SwiftUI List with the
/// same row treatment as live lists (title, body, date, tags). Leading
/// swipe = Restore (sage); trailing swipe = Delete Forever (red, with
/// confirm). 30-day auto-purge runs on bootstrap.
struct RecentlyDeletedView: View {
    private enum Operation {
        case restoreItem(UUID)
        case restoreList(String)
        case deleteItem(UUID)
        case deleteList(String)

        var failureTitle: String {
            switch self {
            case .restoreItem: "Couldn’t Restore Item"
            case .restoreList: "Couldn’t Restore List"
            case .deleteItem: "Couldn’t Delete Item"
            case .deleteList: "Couldn’t Delete List"
            }
        }
    }

    private struct OperationFailure {
        let operation: Operation
        let message: String
    }

    let store: ItemStore

    @State private var pendingPurgeItem: Item?
    @State private var pendingPurgeList: ItemList?
    @State private var activeOperation: Operation?
    @State private var operationFailure: OperationFailure?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if store.deletedItems.isEmpty,
               store.deletedLists.isEmpty,
               store.pendingRestoreCleanup == nil {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "trash",
                    description: Text("Deleted items and lists appear here for 30 days, then auto-purge.")
                )
            } else {
                List {
                    if let cleanup = store.pendingRestoreCleanup {
                        Section {
                            pendingRestoreCleanupRow(cleanup)
                                .listRowSeparator(.hidden)
                        } header: {
                            sectionHeader("Recovery")
                        }
                    }
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
        .disabled(activeOperation != nil)
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(ListsTokens.Semantic.danger)
        .navigationBarMinimizesOnScroll()
        .tint(ListsTokens.Semantic.danger)
        .alert("Delete forever?", isPresented: Binding(
            get: { pendingPurgeItem != nil },
            set: { if !$0 { pendingPurgeItem = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let id = pendingPurgeItem?.id {
                    perform(.deleteItem(id))
                }
                pendingPurgeItem = nil
            }
            Button("Cancel", role: .cancel) { pendingPurgeItem = nil }
        } message: {
            if let item = pendingPurgeItem {
                let count = store.allItemDescendantIds(of: item.id).count
                if count > 0 {
                    let noun = count == 1 ? "sub-item" : "sub-items"
                    Text("\"\(item.title)\" and \(count) \(noun) cannot be restored.")
                } else {
                    Text("\"\(item.title)\" cannot be restored.")
                }
            }
        }
        .alert("Delete list forever?", isPresented: Binding(
            get: { pendingPurgeList != nil },
            set: { if !$0 { pendingPurgeList = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let id = pendingPurgeList?.id {
                    perform(.deleteList(id))
                }
                pendingPurgeList = nil
            }
            Button("Cancel", role: .cancel) { pendingPurgeList = nil }
        } message: {
            if let name = pendingPurgeList?.name {
                Text("\"\(name)\" and all sub-lists and items in it cannot be restored.")
            }
        }
        .alert(
            operationFailure?.operation.failureTitle ?? "Couldn’t Complete Action",
            isPresented: isShowingOperationFailure
        ) {
            Button("Retry") {
                if let operation = operationFailure?.operation {
                    perform(operation)
                }
            }
            .accessibilityIdentifier("recently.deleted.persistence.error.retry")
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("recently.deleted.persistence.error.dismiss")
        } message: {
            if let operationFailure {
                Text(operationFailure.message)
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func pendingRestoreCleanupRow(
        _ cleanup: ItemStore.PendingRestoreCleanup
    ) -> some View {
        HStack(alignment: .top, spacing: ListsSpacing.s3) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                Text("Finish Restore")
                    .font(ListsTypography.body.weight(.semibold))
                Text("The restored data is active, but its recovery lock still needs clearing before permanent deletion can continue.")
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ListsSpacing.s2)
            Button("Retry") {
                perform(operation(for: cleanup))
            }
            .buttonStyle(.bordered)
            .tint(ListsTokens.accent)
        }
        .padding(.vertical, ListsSpacing.s2)
        .accessibilityIdentifier("recently.deleted.restore.cleanup")
    }

    private func operation(
        for cleanup: ItemStore.PendingRestoreCleanup
    ) -> Operation {
        switch cleanup {
        case .item(let id): .restoreItem(id)
        case .list(let id): .restoreList(id)
        }
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

                metaRow(date: item.deletedAt, tags: item.tags, prefix: "Deleted")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.horizontal, ListsDensity.rowPadX)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recentlyDeleted.item.\(item.id.uuidString)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                perform(.restoreItem(item.id))
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
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                perform(.restoreItem(item.id))
            }
            Button("Delete Forever", systemImage: "trash", role: .destructive) {
                pendingPurgeItem = item
            }
        }
        .accessibilityAction(named: "Restore") {
            perform(.restoreItem(item.id))
        }
        .accessibilityAction(named: "Delete Forever") {
            pendingPurgeItem = item
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recentlyDeleted.list.\(list.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                perform(.restoreList(list.id))
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
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                perform(.restoreList(list.id))
            }
            Button("Delete Forever", systemImage: "trash", role: .destructive) {
                pendingPurgeList = list
            }
        }
        .accessibilityAction(named: "Restore") {
            perform(.restoreList(list.id))
        }
        .accessibilityAction(named: "Delete Forever") {
            pendingPurgeList = list
        }
    }

    @ViewBuilder
    private func metaRow(date: Date?, tags: [String], prefix: String) -> some View {
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

    private var isShowingOperationFailure: Binding<Bool> {
        Binding(
            get: { operationFailure != nil },
            set: { isPresented in
                if !isPresented {
                    operationFailure = nil
                }
            }
        )
    }

    private func perform(_ operation: Operation) {
        guard activeOperation == nil else { return }
        operationFailure = nil
        activeOperation = operation
        Task {
            do {
                switch operation {
                case .restoreItem(let id):
                    try await store.restore(id)
                case .restoreList(let id):
                    try await store.restoreList(id)
                case .deleteItem(let id):
                    try await store.delete(id)
                case .deleteList(let id):
                    try await store.deleteList(id)
                }
                activeOperation = nil
            } catch {
                activeOperation = nil
                operationFailure = OperationFailure(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
        }
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
