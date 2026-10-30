import SwiftUI

/// Ranked, local search across nondeleted library content. Used as an overlay on
/// SidebarView when the search field has text.
struct SearchResultsView: View {
    let store: ItemStore
    let query: String
    let scope: ItemSearch.Scope?
    let calendarPreferences: CalendarPreferences
    let moveSession: ItemMoveSession
    let documentLinkSession: DocumentLinkSession
    var onMoveStarted: () -> Void = {}
    var onDocumentLinkStarted: () -> Void = {}
    var onOpenItem: () -> Void = {}

    @State private var detailItem: Item?
    @State private var lingeringIds: Set<UUID> = []
    @State private var rowMutationError: String?

    var body: some View {
        calendarScopedContent
    }

    @State private var filter: LibrarySearch.Filter = .all
    @State private var filePreview: FilePreview?
    private struct FilePreview: Identifiable { let url: URL; let title: String; var id: String { url.path } }

    private var calendarScopedContent: some View {
        VStack(spacing: 0) {
            if !documentLinkSession.isActive {
                Picker("Search in", selection: $filter) {
                    ForEach(LibrarySearch.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .accessibilityIdentifier("search.filter")
            }
            if results.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                    description: Text("No results for “\(query)”."))
                    .accessibilityIdentifier("search.empty")
            } else {
                List(results) { result in
                    resultRow(result)
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemBackground))
        .itemDetailCover(item: $detailItem, store: store, onBeginMove: beginMove, onBeginDocumentLink: beginDocumentLink)
        .sheet(item: $filePreview) { LocalFilePreviewScreen(url: $0.url, title: $0.title) }
        .itemMutationErrorAlert($rowMutationError)
    }

    @ViewBuilder private func resultRow(_ result: LibrarySearch.Result) -> some View {
        switch result {
        case .item(let item):
            VStack(alignment: .leading, spacing: 0) {
                ItemRow(item: item, isOverdue: isOverdue(item), store: store,
                    onToggle: { toggleAndLinger(item) }, onMutationFailure: { rowMutationError = $0 },
                    showMetadata: !documentLinkSession.isActive, onShowDetail: openOrLink,
                    onMoveItem: { beginMove(item) },
                    onPick: documentLinkSession.isActive ? { picked in
                        if documentLinkSession.canPick(picked) { documentLinkSession.commit(to: picked, store: store) }
                    } : nil,
                    enablesHierarchySwipeActions: false, isReadOnly: moveSession.isActive)
                Text(location(item.listId)).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            .disabled(documentLinkSession.isActive && !documentLinkSession.canPick(item))
            .accessibilityIdentifier("search.result.\(item.id.uuidString.lowercased())")
        case .list(let list):
            NavigationLink(value: list) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.name).foregroundStyle(.primary)
                        Text("List · " + location(list.parentId)).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: list.icon).foregroundStyle(ListsTokens.listColor(list.color)) }
                .frame(minHeight: 56)
            }.accessibilityIdentifier("search.list.\(list.id)")
        case .file(let file):
            Button {
                onOpenItem()
                Task {
                    do { filePreview = FilePreview(url: try await store.standaloneFileURL(file), title: file.fileName) }
                    catch { rowMutationError = error.localizedDescription }
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.fileName).foregroundStyle(.primary)
                        Text(location(file.listID)).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "doc").foregroundStyle(.secondary) }
                .frame(minHeight: 56)
            }.buttonStyle(.plain).accessibilityIdentifier("search.file.\(file.id)")
        }
    }

    private func location(_ id: String?) -> String {
        var names: [String] = []
        var next = id
        var visited = Set<String>()
        while let current = next, visited.insert(current).inserted,
              let list = store.lists.first(where: { $0.id == current }) {
            names.insert(list.name, at: 0); next = list.parentId
        }
        return names.isEmpty ? "Lists" : names.joined(separator: " › ")
    }

    private var results: [LibrarySearch.Result] {
        if let scope {
            return ItemSearch.results(in: store.items, scope: scope, lists: store.lists).map { .item($0) }
        }
        return LibrarySearch.results(query: query, items: store.items, lists: store.lists,
            files: store.standaloneFiles, filter: documentLinkSession.isActive ? .items : filter)
    }

    private func beginMove(_ item: Item) {
        documentLinkSession.cancel()
        moveSession.begin(item: item)
        onMoveStarted()
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        moveSession.cancel()
        documentLinkSession.begin(source: source)
        onDocumentLinkStarted()
    }

    private func openOrLink(_ item: Item) {
        onOpenItem()
        if documentLinkSession.isActive {
            documentLinkSession.commit(to: item, store: store)
        } else {
            detailItem = item
        }
    }

    private func isOverdue(_ item: Item) -> Bool {
        item.isOverdue()
    }

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: true,
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
        )
    }

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.18)) {
                _ = lingeringIds.remove(id)
            }
        }
    }
}
