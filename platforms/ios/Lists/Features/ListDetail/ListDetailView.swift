import SwiftUI
import UniformTypeIdentifiers

/// Single user-list view. Items are grouped by section when sections exist,
/// otherwise flat. The body is a UIKit collection/list bridge so rows can
/// support inline editing, reorder, hierarchy, swipe actions, and drag targets.
///
/// Top-trailing toolbar exposes a `•••` overflow menu with:
/// - Sort By (Manual / Due Date / Title / Date Added / Priority)
/// - Show Completed toggle
/// - Edit List → ListEditSheet
/// - Delete List → confirm → softDeleteList + pop nav
///
/// FloatingAddButton at bottom-right: tap → inline item, drag → positioned
/// inline item, long-press → Quick Capture for this list.
struct ListDetailView: View {
    let store: ItemStore
    /// The list value the navigation was created with — used only as a
    /// stable seed for the `listId` lookup and as a fallback if the list
    /// later vanishes from the store. **Never read inside the view body**;
    /// always go through the computed `list` accessor so SwiftUI re-reads
    /// the current value out of the observable store on every render.
    private let initialList: ItemList
    /// Shared global UI prefs (owned by the Sidebar). Read here for the
    /// default item type; passed down to sub-lists so the
    /// choice is consistent at every depth.
    let autoListPrefs: AutoListPreferences
    let calendarPreferences: CalendarPreferences
    let moveSession: ItemMoveSession
    let documentLinkSession: DocumentLinkSession

    init(
        store: ItemStore,
        list: ItemList,
        autoListPrefs: AutoListPreferences,
        calendarPreferences: CalendarPreferences,
        moveSession: ItemMoveSession = ItemMoveSession(),
        documentLinkSession: DocumentLinkSession = DocumentLinkSession()
    ) {
        self.store = store
        self.initialList = list
        self.autoListPrefs = autoListPrefs
        self.calendarPreferences = calendarPreferences
        self.moveSession = moveSession
        self.documentLinkSession = documentLinkSession
    }

    @State private var showingCalendarConnections = false
    @State private var showingFileImporter = false
    @State private var isImportingFiles = false

    /// Always read the freshest value out of the store. This keeps section
    /// renames, reorders, additions, and other mutations reflecting in
    /// real time — without this, the view would snapshot at navigation
    /// time and edits would only appear after leaving + re-entering.
    private var list: ItemList {
        store.lists.first(where: { $0.id == initialList.id }) ?? initialList
    }

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    /// Bridge to the collection-view coordinator for FAB-drag inline create.
    @State private var cvBridge = ListDetailBridge()
    @State private var prefs = ListViewPreferences()
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingNewSubList = false
    @State private var showingEditSections = false
    @State private var pendingDeleteSectionId: UUID?
    @State private var pendingDeleteSectionName: String = ""
    @State private var pendingDeleteSectionCount: Int = 0
    /// Item presented from row taps or swipe actions. The parent owns the
    /// detail route so a move started from detail can dismiss and continue in
    /// the shared bottom shelf.
    @State private var detailItem: Item?
    /// Pending sub-list navigation. Set by tapping a sub-list row in the
    /// collection view; presented via `navigationDestination(item:)` so we
    /// can route the tap manually (no NavigationLink in the cell) and keep
    /// the chevron aligned with the Sub-Lists header.
    @State private var navigatingSubList: ItemList?
    @Environment(\.listHierarchyRevealSession) private var hierarchyReveal
    /// Multi-select mode — shows a trailing selection circle and the
    /// system drag handles on every row, swaps the row tap from "open
    /// detail" to "toggle selection", and replaces the `•••` toolbar with
    /// a Done button.
    @State private var inSelectMode = false
    @State private var selection: Set<UUID> = []
    /// Id of the row being edited inline (title + notes in place). Set by
    /// tapping a row's text; cleared when inline editing ends.
    @State private var editingItemId: UUID?
    /// Section key whose header is being renamed inline. Set by "New Section"
    /// (so you name it in place); cleared when the rename finishes.
    @State private var editingSectionKey: String?
    /// IDs of just-completed items kept visible during the linger window so
    /// the row can fade out instead of vanishing instantly. Cleared when the
    /// linger Task wakes up after ~1.5s, or immediately if the item is
    /// un-completed.
    @State private var lingeringIds: Set<UUID> = []
    @State private var rowMutationError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        calendarScopedContent.modifier(CalendarMenuScope())
    }

    private func revealHierarchy() {
        cvBridge.coordinator?.collectionView?.endEditing(true)
        guard let hierarchyReveal else { return }
        if hierarchyReveal.isRevealed && hierarchyReveal.ownerID == list.id { hierarchyReveal.close() }
        else { hierarchyReveal.reveal(list: list) { navigatingSubList = $0 } }
    }

    private var calendarScopedContent: some View {
        ZStack(alignment: .bottomTrailing) {
                Color(.systemBackground).ignoresSafeArea()

                if effectiveViewMode == .calendar {
                    VStack(spacing: 0) {
                        CalendarPlannerView(
                            store: store,
                            items: calendarItems,
                            preferences: calendarPreferences,
                            surfaceKey: "list:\(list.id)",
                            tint: ListsTokens.listColor(list.color),
                            defaultListId: list.id,
                            defaultSection: nil,
                            defaultNewItemType: effectiveDefaultNewItemType,
                            moveSession: moveSession,
                            documentLinkSession: documentLinkSession
                        )
                    }
                } else {
                    // Keep the collection view mounted even when the list is
                    // empty and overlay the empty state, rather than swapping
                    // the two. Swapping loses UIKit's large-title scroll link.
                    ListDetailCollectionView(
                        store: store,
                        listId: list.id,
                        prefs: prefs,
                        listColor: ListsTokens.listColor(list.color),
                        presentation: effectiveViewMode == .columns ? .columns : .list,
                        bridge: cvBridge,
                        inSelectMode: $inSelectMode,
                        selection: $selection,
                        editingItemId: $editingItemId,
                        editingSectionKey: $editingSectionKey,
                        lingeringIds: lingeringIds,
                        defaultNewItemType: effectiveDefaultNewItemType,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        onToggleItem: { toggleAndLinger($0) },
                        onSelectToggle: { toggleSelection($0) },
                        onPromptDeleteSection: { promptDeleteSection($0, name: $1) },
                        onSoftDeleteSubList: { id in
                            Task { do { try await store.softDeleteList(id) } catch { rowMutationError = error.localizedDescription } }
                        },
                        onSoftDeleteItem: { id in
                            Task { do { try await store.softDelete(id) } catch { rowMutationError = error.localizedDescription } }
                        },
                        onPromoteOthers: { name in
                            Task { do { try await store.promoteOthersToSection(in: list.id, name: name) } catch { rowMutationError = error.localizedDescription } }
                        },
                        onRenameSection: { uuid, name in
                            Task { do { try await store.renameSection(uuid, in: list.id, to: name) } catch { rowMutationError = error.localizedDescription } }
                        },
                        onShowItemDetail: openOrLink,
                        onOpenSubList: { navigatingSubList = $0 },
                        onBrowseSubLists: { revealHierarchy() },
                        onPullToReveal: { if hierarchyReveal?.isRevealed != true { revealHierarchy() } },
                        onBeginInlineEdit: { id in
                            guard store.item(id) != nil else { return }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                editingItemId = id
                            }
                        },
                        onBeginMove: { beginMove($0) },
                        onEndInlineEdit: { endedId in
                            if editingItemId == endedId { editingItemId = nil }
                        },
                        onEndEditSection: { editingSectionKey = nil }
                    )
                    .id(effectiveViewMode)
                    .ignoresSafeArea()
                    .overlay {
                        if shouldShowEmptyState {
                            emptyState
                        }
                    }
                }

                if !documentLinkSession.isActive && effectiveViewMode != .calendar {
                    ListDetailBottomChrome(
                        store: store,
                        listId: list.id,
                        listColor: ListsTokens.listColor(list.color),
                        defaultNewItemType: effectiveDefaultNewItemType,
                        cvBridge: cvBridge,
                        moveSession: moveSession,
                        inSelectMode: $inSelectMode,
                        selection: $selection,
                        editingItemId: $editingItemId,
                        fabIsInteracting: $fabIsInteracting,
                        onOpenQuickCapture: {
                            captureTarget = CaptureTarget(
                                listId: list.id,
                                section: cvBridge.preferredSectionForCapture()
                            )
                        }
                    )
                }
            }
        .navigationDestination(item: $navigatingSubList) { child in
            ListDetailView(
                store: store,
                list: child,
                autoListPrefs: autoListPrefs,
                calendarPreferences: calendarPreferences,
                moveSession: moveSession,
                documentLinkSession: documentLinkSession
            )
        }
        .environment(\.attachmentMoveSession, moveSession)
        .navigationTitle(list.name)
        // A focused UIKit editor causes the large-title navigation bar to lose
        // its title/back chrome on iOS 27 while retaining the expanded inset.
        // Inline mode keeps navigation visible and returns vertical room to the
        // editor. Columns and Calendar use compact titles to keep navigation
        // from reserving large-title space above their content.
        .navigationBarTitleDisplayMode(editingItemId == nil && effectiveViewMode == .list ? .large : .inline)
        .navigationBarTitleColor(ListsTokens.listColor(list.color))
        .tint(ListsTokens.listColor(list.color))
        .toolbar {
            // List options are unrelated to the active field edit. Hiding the
            // menu during that edit leaves enough compact-bar space for the
            // system Back button, inline list title, and commit tick.
            if !documentLinkSession.isActive && (inSelectMode || editingItemId == nil) {
                if !inSelectMode && effectiveViewMode != .calendar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingFileImporter = true } label: {
                            Image(systemName: "doc.badge.plus").accessibilityLabel("Add Files")
                        }
                        .disabled(moveSession.isActive || isImportingFiles)
                        .accessibilityIdentifier("list.files.import")
                    }
                }
                if !inSelectMode && !childLists.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { revealHierarchy() } label: {
                            Image(systemName: hierarchyReveal?.isRevealed == true ? "chevron.up" : "chevron.down")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Browse sub-lists")
                        .accessibilityValue(hierarchyReveal?.isRevealed == true ? "Expanded" : "Collapsed")
                        .accessibilityIdentifier("list.sublists.browse")
                        .accessibilityHint("Pull down at the top to reveal sub-lists")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if inSelectMode {
                        Button("Done") {
                            inSelectMode = false
                            selection.removeAll()
                        }
                        .accessibilityIdentifier("list.selectMode.done")
                    } else {
                        ListDetailToolbarMenu(
                            listId: list.id,
                            hasSections: list.sections.isEmpty == false,
                            prefs: prefs,
                            isMoving: moveSession.isActive,
                            onNewSection: createSectionAndRename,
                            onEditSections: { showingEditSections = true },
                            onNewSublist: { showingNewSubList = true },
                            onSelectItems: { inSelectMode = true },
                            onEditList: { showingEdit = true },
                            onDeleteList: { showingDeleteConfirm = true },
                            onConnectCalendar: { showingCalendarConnections = true },
                            onPaste: {
                                Task {
                                    do { try await ItemClipboard.shared.paste(into: .init(listId: list.id), store: store) }
                                    catch { rowMutationError = error.localizedDescription }
                                }
                            }
                        )
                    }
                }
            }
            // Separate trailing button (its own glass circle) — the blue ✓ that
            // commits the inline edit. The spacer breaks iOS 26's shared-glass
            // grouping so the ✓ sits apart from the ⋯ pill, not inside it.
            if editingItemId != nil && !inSelectMode && !isDestinationModeActive {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    inlineDoneTick
                }
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { rowMutationError = error.localizedDescription }
            case .success(let urls):
                isImportingFiles = true
                Task {
                    defer { isImportingFiles = false }
                    var failures: [String] = []
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        do { _ = try await store.importStandaloneFile(fileURL: url, into: list.id) }
                        catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                    }
                    if !failures.isEmpty { rowMutationError = failures.joined(separator: "\n") }
                }
            }
        }
        .onChange(of: store.standaloneFiles) { _, _ in cvBridge.coordinator?.applySnapshot(animated: true) }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(
                store: store,
                defaultListId: target.listId,
                defaultSection: target.section,
                defaultNewItemType: effectiveDefaultNewItemType,
                onOpenCreatedItem: { detailItem = $0 }
            )
        }
        .itemDetailCover(
            item: $detailItem,
            store: store,
            onBeginMove: beginMove,
            onBeginDocumentLink: beginDocumentLink
        )
        .sheet(isPresented: $showingCalendarConnections) { CalendarConnectionSheet(store: store, initialListID: list.id) }
        .sheet(isPresented: $showingEdit) {
            ListEditSheet(existing: list, store: store)
        }
        .sheet(isPresented: $showingNewSubList) {
            ListEditSheet(store: store, initialParentId: list.id)
        }
        .sheet(isPresented: $showingEditSections) {
            EditSectionsSheet(store: store, list: list)
        }
        .onChange(of: moveSession.isActive) { _, _ in
            if moveSession.isActive { clearTransientModesForMove() }
            cvBridge.coordinator?.applySnapshot(animated: false)
        }
        .onChange(of: documentLinkSession.isActive) { _, active in
            guard active else { return }
            clearTransientModesForLinking()
        }
        .onChange(of: list.sections.isEmpty) { _, isEmpty in
            if isEmpty && prefs.viewMode(for: list.id) == .columns {
                prefs.setViewMode(.list, for: list.id)
            }
        }
        .task(id: list.id) {
            do { try await store.migrateLegacySectionsIfNeeded(listId: list.id) }
            catch { rowMutationError = error.localizedDescription }
        }
        .alert("Delete this list?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await store.softDeleteList(list.id)
                        dismiss()
                    } catch { rowMutationError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteListMessage)
        }
        .alert(
            "Delete \"\(pendingDeleteSectionName)\"?",
            isPresented: Binding(
                get: { pendingDeleteSectionId != nil },
                set: { if !$0 { pendingDeleteSectionId = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { confirmDeleteSection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if pendingDeleteSectionCount > 0 {
                let noun = pendingDeleteSectionCount == 1 ? "item" : "items"
                Text("This section and its \(pendingDeleteSectionCount) \(noun) will move to Recently Deleted.")
            } else {
                Text("This section will be removed.")
            }
        }
        .onChange(of: store.items) { _, _ in cvBridge.coordinator?.applySnapshot(animated: false) }
        .itemMutationErrorAlert($rowMutationError, title: "Couldn’t Complete Action")
    }

    // MARK: - Toolbar

    /// Solid blue ✓ shown while editing inline. Uses the prominent button style
    /// so iOS fills the whole toolbar circle blue (rather than a glass ring
    /// around a smaller filled circle).
    private var inlineDoneTick: some View {
        Button {
            editingItemId = nil
        } label: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .accessibilityLabel("Done editing")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(ListsTokens.accent)
        .accessibilityIdentifier("inline.editor.done")
    }

    // MARK: - Empty state inputs

    /// Direct child lists of the current list, non-deleted, sorted by
    /// position. Empty when this is a leaf list.
    private var childLists: [ItemList] {
        store.lists
            .filter { $0.parentId == list.id && $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    private func promptDeleteSection(_ id: UUID, name: String) {
        let sidStr = id.uuidString
        let count = store.items.filter {
            $0.listId == list.id && $0.section == sidStr && $0.deletedAt == nil
        }.count
        pendingDeleteSectionId = id
        pendingDeleteSectionName = name
        pendingDeleteSectionCount = count
    }

    private func confirmDeleteSection() {
        guard let sid = pendingDeleteSectionId else { return }
        let listId = list.id
        Task { do { try await store.deleteSection(sid, in: listId, cascadingItems: true) } catch { rowMutationError = error.localizedDescription } }
        pendingDeleteSectionId = nil
    }

    private var deleteListMessage: String {
        if store.descendantIds(of: list.id).isEmpty {
            return "\"\(list.name)\" and its items will move to Recently Deleted."
        }
        return "\"\(list.name)\", its sub-lists, and its items will move to Recently Deleted."
    }

    private func createSectionAndRename() {
        Task {
            do {
                if let section = try await store.addSection(in: list.id, name: "New Section") {
                    editingSectionKey = section.id.uuidString
                }
            } catch { rowMutationError = error.localizedDescription }
        }
    }

    private var emptyState: some View {
        ListDetailEmptyStateView(
            icon: list.icon,
            color: ListsTokens.listColor(list.color),
            childCount: childLists.count,
            onBrowseSubLists: revealHierarchy
        )
    }

    private var effectiveViewMode: ListViewPreferences.ViewMode {
        let requested = prefs.viewMode(for: list.id)
        if requested == .columns && list.sections.isEmpty {
            return .list
        }
        return requested
    }

    private var shouldShowEmptyState: Bool {
        guard !isDestinationModeActive else { return false }
        if effectiveViewMode == .columns && !list.sections.isEmpty {
            return false
        }
        return editingItemId == nil && visibleItems.isEmpty && !store.standaloneFiles.contains { $0.listID == list.id }
    }

    // MARK: - Data

    /// Top-level items in this list — filtered by "show completed" and
    /// reordered by the active sort mode. Just-completed items in
    /// `lingeringIds` stay visible for the fade window.
    private var visibleItems: [Item] {
        let showCompleted = prefs.showCompleted(for: list.id)
        let showPastEvents = prefs.showPastEvents(for: list.id)
        let now = Date.now
        let calendar = Calendar.current
        let filtered = store.items.filter { item in
            item.listId == list.id
                && item.deletedAt == nil
                && item.parentId == nil

                && (showCompleted || !item.isComplete(at: now) || lingeringIds.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
        }
        return applySort(filtered)
    }

    /// Calendar is a date projection, not the list-view filter. Include every
    /// active document in the list (including children and completed items);
    /// CalendarPreferences decides which projected entries are visible.
    private var calendarItems: [Item] {
        store.items.filter {
            $0.listId == list.id
                && $0.deletedAt == nil

        }
    }

    private var effectiveDefaultNewItemType: Item.ItemType {
        autoListPrefs.defaultNewItemType
    }

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: prefs.showCompleted(for: list.id),
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
        )
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func beginMove(_ item: Item) {
        clearTransientModesForMove()
        documentLinkSession.cancel()
        moveSession.begin(item: item)
    }

    private func clearTransientModesForMove() {
        editingItemId = nil
        editingSectionKey = nil
        inSelectMode = false
        selection.removeAll()
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        clearTransientModesForLinking()
        moveSession.cancel()
        documentLinkSession.begin(source: source)
    }

    private func clearTransientModesForLinking() {
        editingItemId = nil
        editingSectionKey = nil
        inSelectMode = false
        selection.removeAll()
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

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.4)) {
                _ = lingeringIds.remove(id)
            }
        }
    }

    private func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: list.id), direction: prefs.sortDirection(for: list.id))
    }

}
