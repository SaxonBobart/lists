import SwiftUI
import UIKit

/// Document-style detail page for tasks, notes, and events (habits use
/// `HabitDetailView`). One scrollable page: the title at
/// the top, a one-line fact strip beneath it, and the markdown body editable
/// inline below — the item *is* a page you scroll and type into.
///
/// Behavioural contract:
/// - **Live-apply.** No Save/Discard ceremony: control changes persist
///   immediately; title/body keystrokes are debounced and flushed on close.
/// - **Facts stay on the page.** The strip under the title shows what's set
///   (date/time, event end, repeat cadence, priority, flag) exactly like a
///   row's meta line. The full controls live in a Details sheet, opened from
///   the ⓘ in the nav bar or by tapping the strip.
/// - **Quick bar on the title.** While editing the title, a glass keyboard
///   bar offers the fast edits (flag, priority, type, open Details) without
///   leaving the keyboard. Return hops into the body.
struct ItemDocumentView: View {
    let store: ItemStore
    let onBeginMove: ((Item) -> Void)?
    let onBeginDocumentLink: ((DocumentLinkSource) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CorePluginPreferences.habitsEnabledKey) private var habitsPluginEnabled = true

    @State private var draft: Item
    @State private var editorMode: MarkdownEditorMode = .live
    /// One sheet at a time — the Details controls, breadcrumb path, document navigator, or link picker.
    private enum ActiveSheet: Int, Identifiable { case details, breadcrumb, navigator, linkPicker; var id: Int { rawValue } }
    @State private var activeSheet: ActiveSheet?
    @State private var pendingLinkSelection: DocumentLinkEditorSelection?
    /// The item state captured when the Details sheet opened. The Details
    /// controls live-apply as you edit, so Cancel (✕) restores this snapshot;
    /// the tick keeps the edits.
    @State private var detailsSnapshot: Item?
    /// True while a field on this page holds the keyboard — the hide-keyboard
    /// tick only shows then (like the inline editor's Done on the list screens).
    /// Driven by keyboard show/hide notifications (observation only; no inset
    /// handling, so it doesn't touch UIKit's keyboard avoidance).
    @State private var isEditing = false
    /// The tag field is hidden until there's a tag or the quick bar's tags
    /// button reveals it; the token focuses it when revealed.
    @State private var showTagField = false
    @State private var tagFocusToken = 0
    /// The hosting stack's path, so the breadcrumb menu can push an ancestor's
    /// own document page. Nil outside a navigation stack (previews) — the
    /// breadcrumb entry just no-ops then.
    private let path: Binding<NavigationPath>?
    /// First-responder plumbing between the title and body text views (both
    /// UIKit representables — SwiftUI focus state can't reach them).
    @State private var focusBridge = DocumentFocusBridge()
    @State private var formatPanelSession: MarkdownFormatPanelSession?
    @State private var showsCollapsedTitle = false

    /// Which inline picker is currently visible. The row label toggles
    /// visibility, while the switch toggles the underlying enabled state.
    private enum ExpandedPicker { case none, date, time }
    @State private var expandedPicker: ExpandedPicker = .none

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var showingDeleteConfirm = false
    @State private var persistenceOperation: PersistenceOperation?
    @State private var persistenceFailure: PersistenceFailure?

    private enum PersistenceOperation: Equatable {
        case toggleDone
        case delete

        var title: String {
            switch self {
            case .toggleDone: "Couldn’t Update Item"
            case .delete: "Couldn’t Delete Item"
            }
        }
    }

    private struct PersistenceFailure: Equatable {
        let operation: PersistenceOperation
        let message: String
    }

    /// Pending debounced apply for title/body keystrokes.
    @State private var applyTask: Task<Void, Never>?

    init(item: Item,
         store: ItemStore,
         path: Binding<NavigationPath>? = nil,
         onBeginMove: ((Item) -> Void)? = nil,
         onBeginDocumentLink: ((DocumentLinkSource) -> Void)? = nil) {
        self.store = store
        self.onBeginMove = onBeginMove
        self.onBeginDocumentLink = onBeginDocumentLink
        self.path = path
        _draft = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            DocumentPageContent(
                title: titleBinding,
                bodyText: bodyBinding,
                tags: tagsBinding,
                item: draft,
                editorMode: editorMode,
                showsLeadingControl: showsLeadingControl,
                showTagField: showTagField,
                tagFocusToken: tagFocusToken,
                focusBridge: focusBridge,
                onToggleDone: toggleDone,
                onToggleFlag: { draft.flagged.toggle(); applyNow() },
                onSetPriority: { draft.priority = $0; applyNow() },
                onSetType: setType,
                onOpenDetails: openDetails,
                onAddTags: revealTagField,
                onTitleBeginEditing: titleWillBeginEditing,
                onRequestDocumentLink: requestDocumentLink,
                onFormatRequested: showFormatPanel
            )
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 46
        } action: { _, shouldShow in
            updateCollapsedTitleVisibility(shouldShow)
        }
        .background(ListsTokens.Background.base)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        .toolbarBackground(.visible, for: .navigationBar)
        // Animate the toggle so the tick rides iOS 26's liquid-glass toolbar
        // morph (separating in/out) instead of snapping — same spring as the
        // inline editor's Done on the list screens.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isEditing = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isEditing = false }
            // Drop a revealed-but-unused tag field when editing ends.
            if draft.tags.isEmpty { showTagField = false }
        }
        .onAppear { normalizeEventDates() }
        .onDisappear { finalizeAndFlush() }
        .overlay(alignment: .bottom) {
            formatPanel
        }
        .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\"\(draft.title)\" will move to Recently Deleted.")
        }
        .alert(
            persistenceFailure?.operation.title ?? "Couldn’t Update Item",
            isPresented: Binding(
                get: { persistenceFailure != nil },
                set: { if !$0 { persistenceFailure = nil } }
            )
        ) {
            Button("Try Again") { retryPersistenceOperation() }
                .accessibilityIdentifier("document.persistence.error.retry")
            Button("Keep Open", role: .cancel) {}
                .accessibilityIdentifier("document.persistence.error.dismiss")
        } message: {
            if let persistenceFailure { Text(persistenceFailure.message) }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .details:    detailsSheet
            case .breadcrumb: breadcrumbSheet
            case .navigator:  navigatorSheet
            case .linkPicker: linkPickerSheet
            }
        }
    }

    @ViewBuilder
    private var formatPanel: some View {
        if let formatPanelSession {
            MarkdownFormatPanelOverlay(session: formatPanelSession) {
                withAnimation(.smooth(duration: 0.18)) {
                    self.formatPanelSession = nil
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(10)
        }
    }

    private func showFormatPanel(_ session: MarkdownFormatPanelSession) {
        withAnimation(.smooth(duration: 0.18)) {
            formatPanelSession = session
        }
    }

    private func closeFormatPanel(refocusesBody: Bool) {
        guard let session = formatPanelSession else { return }
        withAnimation(.smooth(duration: 0.18)) {
            formatPanelSession = nil
        }
        session.restoreKeyboard(refocusesTextView: refocusesBody)
    }

    private func titleWillBeginEditing() {
        closeFormatPanel(refocusesBody: false)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                leavePage()
            } label: {
                Image(systemName: "chevron.backward")
                    .accessibilityLabel("Back")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.back")
        }
        ToolbarItem(placement: .principal) {
            if showsCollapsedTitle {
                collapsedToolbarTitle
            } else {
                breadcrumbTitle
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                openDetails()
            } label: {
                Image(systemName: "info.circle")
                    .accessibilityLabel("Details")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.info")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    focusBridge.endEditing()
                    activeSheet = .navigator
                } label: {
                    Label("Document Navigator", systemImage: "list.bullet.rectangle")
                }
                Button {
                    editorMode = editorMode == .live ? .raw : .live
                } label: {
                    if editorMode == .raw {
                        Label("Live Formatting", systemImage: "textformat")
                    } else {
                        Label("Raw Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.menu")
        }
        if isEditing || formatPanelSession != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    closeFormatPanel(refocusesBody: false)
                    focusBridge.endEditing()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isEditing = false }
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Hide Keyboard")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(ListsTokens.accent)
                .accessibilityIdentifier("document.done")
            }
        }
    }

    private func updateCollapsedTitleVisibility(_ shouldShow: Bool) {
        guard shouldShow != showsCollapsedTitle else { return }
        withAnimation(.smooth(duration: 0.16)) {
            showsCollapsedTitle = shouldShow
        }
    }

    private var collapsedToolbarTitle: some View {
        Text(collapsedTitleText)
            .font(ListsTypography.headline)
            .foregroundStyle(ListsTokens.Foreground.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 210)
            .accessibilityIdentifier("document.collapsedTitle")
    }

    private var collapsedTitleText: String {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? draft.type.titlePlaceholder : trimmed
    }

    /// Leave the page (the leading back button). Flush edits, then dismiss.
    private func leavePage() {
        finalizeAndFlush()
        dismiss()
    }

    /// Open the Details sheet — the keyboard resigns first so the sheet isn't
    /// fighting an active text view underneath it.
    private func openDetails() {
        closeFormatPanel(refocusesBody: false)
        focusBridge.endEditing()
        detailsSnapshot = draft
        activeSheet = .details
    }

    /// Cancel the Details edits — restore the snapshot captured on open and
    /// push it back to the store, then close.
    private func cancelDetails() {
        if let snap = detailsSnapshot {
            draft = snap
            applyNow()
        }
        detailsSnapshot = nil
        activeSheet = nil
    }

    /// The quick bar's tags button: reveal the tag field (if hidden) and focus
    /// it so the user can type a tag straight away.
    private func revealTagField() {
        withAnimation(.easeInOut(duration: 0.2)) { showTagField = true }
        tagFocusToken += 1
    }

    private func requestDocumentLink(_ selection: DocumentLinkEditorSelection) {
        focusBridge.endEditing()
        finalizeAndFlush()
        pendingLinkSelection = selection
        activeSheet = .linkPicker
    }

    private func beginDocumentLinkFromPicker(_ selection: DocumentLinkEditorSelection) {
        activeSheet = nil
        let source = DocumentLinkSource(
            itemId: draft.id,
            title: draft.title,
            selection: selection
        )
        onBeginDocumentLink?(source)
        if onBeginDocumentLink == nil {
            activeSheet = .navigator
        }
    }

    private func insertURLLink(label: String, url: URL, selection: DocumentLinkEditorSelection) {
        draft.body = DocumentMarkdownLinkBuilder.replacingSelection(
            selection,
            in: draft.body,
            label: label,
            url: url
        )
        applyNow()
        pendingLinkSelection = nil
        activeSheet = nil
    }

    // MARK: - Breadcrumb

    /// The principal title. When the item sits in a hierarchy — it has a parent
    /// or children — it's a tappable label (type name + chevron) that opens the
    /// breadcrumb as a sheet from the bottom. A standalone item is a plain label.
    @ViewBuilder
    private var breadcrumbTitle: some View {
        if hasHierarchyContext {
            Button {
                focusBridge.endEditing()
                activeSheet = .breadcrumb
            } label: {
                HStack(spacing: 4) {
                    Text(typeDisplayName)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(ListsTypography.headline)
                .foregroundStyle(ListsTokens.Foreground.primary)
            }
            .accessibilityIdentifier("document.breadcrumb")
        } else {
            Text(typeDisplayName)
                .font(ListsTypography.headline)
                .foregroundStyle(ListsTokens.Foreground.primary)
        }
    }

    /// Shown whenever the item is part of a hierarchy, so a top-level parent (no
    /// ancestors but with children) still exposes the breadcrumb.
    private var hasHierarchyContext: Bool { !ancestors.isEmpty || !children.isEmpty }

    /// The item's ancestor chain (root → … → immediate parent), oldest first.
    /// Empty for a top-level item.
    private var ancestors: [Item] {
        ItemHierarchy.ancestors(of: draft, in: store.items)
    }

    /// Direct children of this item, for jumping down the hierarchy from the
    /// breadcrumb sheet.
    private var children: [Item] {
        store.items
            .filter { $0.parentId == draft.id && $0.deletedAt == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The breadcrumb as a bottom sheet: the ancestor chain, this item (marked
    /// "Current"), then its direct children — tapping any other row jumps to
    /// that item's own document page, so you can move up or down the hierarchy.
    private var breadcrumbSheet: some View {
        DocumentBreadcrumbSheet(
            current: draft,
            ancestors: ancestors,
            children: children,
            onSelect: openBreadcrumb,
            onDone: { activeSheet = nil }
        )
    }

    /// Jump to an ancestor's own document page (pushed onto this stack). Flush
    /// pending edits first so nothing typed here is lost on the way up.
    private func openBreadcrumb(_ id: UUID) {
        focusBridge.endEditing()
        finalizeAndFlush()
        activeSheet = nil
        path?.wrappedValue.append(BreadcrumbDestination(id: id))
    }

    /// Only a *functional* control gets a leading slot on the page: the
    /// checkbox of a task or a completable event. A note or a plain event has
    /// only a decorative glyph, which is redundant here (the type already shows
    /// in the nav bar), so it's hidden and the title sits flush at the margin.
    private var showsLeadingControl: Bool {
        draft.type == .task || (draft.type == .event && draft.completable)
    }

    // MARK: - Details sheet

    /// All the item's controls, live-applying like everything else on the page.
    private var detailsSheet: some View {
        NavigationStack {
            Form {
                DocumentScheduleCard(
                    itemType: draft.type,
                    due: dueBinding,
                    end: endBinding,
                    allDay: allDayBinding,
                    reminderEnabled: reminderBinding,
                    alarmEnabled: alarmBinding,
                    hasDate: hasDateBinding,
                    hasTime: hasTimeBinding,
                    datePickerExpanded: expandedPicker == .date,
                    timePickerExpanded: expandedPicker == .time,
                    dateSubtitle: dateSubtitle,
                    timeSubtitle: timeSubtitle,
                    timeZoneLabel: TimeZoneLabel.display(for: draft.dueTimeZone),
                    onToggleDatePicker: {
                        withAnimation(.smooth) {
                            expandedPicker = expandedPicker == .date ? .none : .date
                        }
                    },
                    onToggleTimePicker: {
                        withAnimation(.smooth) {
                            expandedPicker = expandedPicker == .time ? .none : .time
                        }
                    },
                    onShowTimeZonePicker: { showTimeZonePicker = true }
                )
                if draft.due != nil {
                    DocumentRepeatCard(
                        repeatPreset: parsedRepeat.preset,
                        repeatDisplay: currentRepeatDisplay,
                        repeatUntil: parsedRepeat.until,
                        reminderEnabled: draft.reminder?.enabled == true,
                        earlyPreset: currentEarlyPreset,
                        earlyDisplay: currentEarlyDisplay,
                        endRepeat: endRepeatBinding,
                        endRepeatDate: endRepeatDateBinding,
                        onSelectRepeat: setRepeatPreset,
                        onSelectEarly: { preset in
                            if preset == .custom {
                                showEarlyCustom = true
                            } else {
                                setEarlyReminder(preset.value)
                            }
                        }
                    )
                }
                DocumentMetadataCard(
                    type: draft.type,
                    typeDisplayName: typeDisplayName,
                    completable: completableBinding,
                    flagged: flaggedBinding,
                    priority: priorityBinding,
                    showsHierarchyMoveControl: showsHierarchyMoveControl,
                    parentMoveLabel: parentMoveLabel,
                    sectionName: resolvedSectionName,
                    lists: activeLists,
                    selectedListId: draft.listId,
                    selectedList: selectedList,
                    habitsPluginEnabled: habitsPluginEnabled,
                    onSetType: setType,
                    onBeginParentMove: { beginMoveFromDetails(currentDraftItem) },
                    onShowSectionPicker: { showSectionPicker = true },
                    onSelectList: { list in
                        if draft.listId != list.id {
                            draft.listId = list.id
                            draft.section = nil
                            applyNow()
                        }
                    }
                )
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cancelDetails()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .accessibilityIdentifier("document.details.cancel")
                }
                ToolbarItem(placement: .principal) {
                    DetailSheetHeaderTitle(
                        item: draft,
                        store: store,
                        standaloneLabel: "Details",
                        accessibilityId: "document.details.parent",
                        onBeginMove: onBeginMove.map { begin in
                            { item in
                                beginMoveFromDetails(item, begin: begin)
                            }
                        }
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        detailsSnapshot = nil
                        activeSheet = nil
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Done")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.accent)
                    .accessibilityIdentifier("document.details.done")
                }
            }
            // Sub-editors present over the Details sheet, so their modifiers
            // hang off its content (a sheet modifier on the underlying page
            // couldn't present while Details is up).
            .sheet(isPresented: $showRepeatCustom) {
                CustomRepeatSheet(initialRRule: parsedRepeat.custom,
                                  startDate: draft.due ?? .now) { rrule in
                    setRecurrence(base: rrule, until: parsedRepeat.until)
                }
            }
            .sheet(isPresented: $showEarlyCustom) {
                EarlyReminderCustomSheet(
                    initialValue: draft.reminder?.early?.value ?? 5,
                    initialUnit: draft.reminder?.early?.unit ?? .minute
                ) { value, unit in
                    setEarlyReminder(EarlyReminder(value: value, unit: unit))
                }
            }
            .sheet(isPresented: $showTimeZonePicker) {
                TimeZonePickerSheet(identifier: timeZoneBinding)
            }
            .sheet(isPresented: $showSectionPicker) {
                SectionPickerSheet(store: store, listId: draft.listId, section: sectionBinding)
                    .tint(.primary)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
    }

    private var navigatorSheet: some View {
        DocumentNavigatorSheet(
            title: draft.title.isEmpty ? "Untitled" : draft.title,
            bodyText: draft.body,
            items: store.items,
            onClose: { activeSheet = nil },
            onSelectOutline: { entry in
                activeSheet = nil
                switch entry.target {
                case .title:
                    focusBridge.focusTitle()
                case .body(let range):
                    focusBridge.focusBody(range: range)
                }
            },
            onOpenLink: { link in
                activeSheet = nil
                switch link.destination {
                case .internalItem(let id):
                    if id != draft.id {
                        finalizeAndFlush()
                        path?.wrappedValue.append(BreadcrumbDestination(id: id))
                    }
                case .external(let url):
                    UIApplication.shared.open(url)
                case .unresolved:
                    break
                }
            },
            onSelectFindResult: { result in
                activeSheet = nil
                switch result.target {
                case .title(let range):
                    focusBridge.focusTitle(range: range)
                case .body(let range):
                    focusBridge.focusBody(range: range)
                }
            }
        )
    }

    private var linkPickerSheet: some View {
        DocumentLinkPickerSheet(
            selection: pendingLinkSelection ?? DocumentLinkEditorSelection(
                range: NSRange(location: (draft.body as NSString).length, length: 0),
                selectedText: ""
            ),
            onCancel: {
                pendingLinkSelection = nil
                activeSheet = nil
            },
            onDocument: { selection in
                beginDocumentLinkFromPicker(selection)
            },
            onURL: { label, url, selection in
                insertURLLink(label: label, url: url, selection: selection)
            }
        )
    }

    private var currentDraftItem: Item {
        store.item(draft.id) ?? draft
    }

    private var showsHierarchyMoveControl: Bool {
        onBeginMove != nil
            && (draft.parentId != nil || store.items.contains { $0.parentId == draft.id && $0.deletedAt == nil })
    }

    private var parentMoveLabel: String {
        if let parentId = draft.parentId,
           let parent = store.item(parentId) {
            return parent.title.isEmpty ? "Untitled" : parent.title
        }
        return "Move"
    }

    private func beginMoveFromDetails(_ item: Item, begin: ((Item) -> Void)? = nil) {
        detailsSnapshot = nil
        activeSheet = nil
        if let begin {
            begin(item)
        } else if let onBeginMove {
            onBeginMove(item)
        }
    }

    // MARK: - Live-apply plumbing

    /// Apply the draft to the store immediately (no-op when nothing changed,
    /// or when the item has been deleted out from under the page).
    private func applyNow() {
        applyTask?.cancel()
        applyTask = nil
        guard let live = store.item(draft.id), live.deletedAt == nil else { return }
        var candidate = draft
        candidate.modifiedAt = live.modifiedAt
        guard candidate != live else { return }
        store.applyUpdateWithSubtreeCascadesSync(draft)
        if let updated = store.item(draft.id) {
            draft.modifiedAt = updated.modifiedAt
        }
    }

    /// Debounced apply for title/body keystrokes — each change re-arms the
    /// timer with a fresh snapshot, so the last keystroke wins.
    private func scheduleApply() {
        applyTask?.cancel()
        let snapshot = draft
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            guard let live = store.item(snapshot.id), live.deletedAt == nil else { return }
            var candidate = snapshot
            candidate.modifiedAt = live.modifiedAt
            guard candidate != live else { return }
            store.applyUpdateWithSubtreeCascadesSync(snapshot)
        }
    }

    /// Closing flush: tags are metadata-only, so the title is preserved exactly.
    private func finalizeAndFlush() {
        applyNow()
    }

    /// Done goes through `toggleDone` (not a raw field write) so recurrence
    /// spawning and completion stamps behave exactly like the row checkbox.
    private func toggleDone() {
        guard persistenceOperation == nil else { return }
        finalizeAndFlush()
        persistenceOperation = .toggleDone
        persistenceFailure = nil
        Task {
            do {
                try await store.toggleDone(draft.id)
                persistenceOperation = nil
                if let live = store.item(draft.id) {
                    draft = live
                }
            } catch {
                persistenceOperation = nil
                persistenceFailure = PersistenceFailure(
                    operation: .toggleDone,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func delete() {
        guard persistenceOperation == nil else { return }
        applyTask?.cancel()
        applyTask = nil
        persistenceOperation = .delete
        persistenceFailure = nil
        Task {
            do {
                try await store.softDelete(draft.id)
                persistenceOperation = nil
                dismiss()
            } catch {
                persistenceOperation = nil
                persistenceFailure = PersistenceFailure(
                    operation: .delete,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func retryPersistenceOperation() {
        guard let operation = persistenceFailure?.operation else { return }
        persistenceFailure = nil
        switch operation {
        case .toggleDone: toggleDone()
        case .delete: delete()
        }
    }

    // MARK: - Bindings

    private var titleBinding: Binding<String> {
        Binding(
            get: { draft.title },
            set: { draft.title = $0; scheduleApply() }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { draft.body },
            set: { draft.body = $0; scheduleApply() }
        )
    }

    private var tagsBinding: Binding<[String]> {
        Binding(
            get: { draft.tags },
            set: { draft.tags = $0; applyNow() }
        )
    }

    private var sectionBinding: Binding<String?> {
        Binding(
            get: { draft.section },
            set: { draft.section = $0; applyNow() }
        )
    }

    private var timeZoneBinding: Binding<String?> {
        Binding(
            get: { draft.dueTimeZone },
            set: { draft.dueTimeZone = $0; applyNow() }
        )
    }

    private var flaggedBinding: Binding<Bool> {
        Binding(
            get: { draft.flagged },
            set: { draft.flagged = $0; applyNow() }
        )
    }

    private var priorityBinding: Binding<Item.Priority> {
        Binding(
            get: { draft.priority },
            set: { draft.priority = $0; applyNow() }
        )
    }

    private var hasTime: Bool { draft.due != nil && !draft.dueAllDay }

    /// Date on → seed a friendly due + auto-enable Reminder (mirrors the form
    /// sheets' cascades). Date off → everything hanging off the date goes too.
    private var hasDateBinding: Binding<Bool> {
        Binding(
            get: { draft.due != nil },
            set: { newValue in
                // An event must keep a start date — ignore turning Date off.
                if !newValue && draft.type == .event { return }
                withAnimation(.smooth) {
                    if newValue {
                        draft.due = draft.due ?? Self.defaultDue()
                        draft.dueAllDay = true
                        if draft.reminder?.enabled != true {
                            draft.reminder = Reminder(enabled: true, early: nil)
                        }
                        expandedPicker = .date
                    } else {
                        draft.due = nil
                        draft.dueAllDay = false
                        draft.end = nil
                        draft.reminder = nil
                        draft.triggers = nil
                        draft.recurrence = nil
                        expandedPicker = .none
                    }
                }
                applyNow()
            }
        )
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding(
            get: { hasTime },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        draft.due = draft.due ?? Self.defaultDue()
                        draft.dueAllDay = false
                        if draft.reminder?.enabled != true {
                            draft.reminder = Reminder(enabled: true, early: nil)
                        }
                        expandedPicker = .time
                    } else {
                        draft.dueAllDay = draft.due != nil
                        draft.triggers = nil
                        expandedPicker = .none
                    }
                }
                applyNow()
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { draft.due ?? Self.defaultDue() },
            set: { newValue in
                // Events keep their span via `EventDateRows`; tasks have no end.
                draft.due = newValue
                applyNow()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { draft.end ?? draft.due ?? .now },
            set: { draft.end = $0; applyNow() }
        )
    }

    /// All-day toggle for events: flips `dueAllDay`, which drops the time pills
    /// from the Starts/Ends pickers. Start + end stay set either way.
    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { draft.dueAllDay },
            set: { newValue in
                withAnimation(.smooth) { draft.dueAllDay = newValue }
                applyNow()
            }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { draft.reminder?.enabled ?? false },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        if draft.due == nil {
                            draft.due = Self.defaultDue()
                            draft.dueAllDay = true
                        }
                        draft.reminder = Reminder(enabled: true, early: draft.reminder?.early)
                    } else {
                        draft.reminder = nil
                        draft.triggers = nil
                    }
                }
                applyNow()
            }
        )
    }

    private var alarmBinding: Binding<Bool> {
        Binding(
            get: { draft.triggers?.alarm?.enabled ?? false },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        if draft.due == nil {
                            draft.due = Self.defaultDue()
                        }
                        draft.dueAllDay = false
                        if draft.reminder?.enabled != true {
                            draft.reminder = Reminder(enabled: true, early: draft.reminder?.early)
                        }
                        draft.triggers = Triggers(alarm: TriggerToggle(enabled: true))
                    } else {
                        draft.triggers = nil
                    }
                }
                applyNow()
            }
        )
    }

    private var completableBinding: Binding<Bool> {
        Binding(
            get: { draft.completable },
            set: { newValue in
                draft.completable = newValue
                if !newValue {
                    draft.done = false
                    draft.completedAt = nil
                }
                applyNow()
            }
        )
    }

    // MARK: - Recurrence plumbing

    /// Current recurrence decomposed into preset + custom base + UNTIL date,
    /// re-derived from the draft on every read so the controls and the model
    /// can't drift apart.
    private var parsedRepeat: (preset: RepeatPreset, custom: String?, until: Date?) {
        guard let rrule = draft.recurrence?.rrule, !rrule.isEmpty else { return (.never, nil, nil) }
        let parts = RRuleParts.splitUntil(from: rrule)
        let base = parts.base
        let until = parts.until.flatMap { ScheduleFormatting.parseUntil($0) }
        for preset in RepeatPreset.taskOptions where preset != .custom && preset != .never {
            if preset.rrule == base {
                return (preset, nil, until)
            }
        }
        return (.custom, base, until)
    }

    private func setRepeatPreset(_ preset: RepeatPreset) {
        switch preset {
        case .never:
            draft.recurrence = nil
            applyNow()
        case .custom:
            showRepeatCustom = true
        default:
            setRecurrence(base: preset.rrule, until: parsedRepeat.until)
        }
    }

    private func setRecurrence(base: String?, until: Date?) {
        guard let base, !base.isEmpty else {
            draft.recurrence = nil
            applyNow()
            return
        }
        if let until {
            draft.recurrence = Recurrence(rrule: "\(base);UNTIL=\(ScheduleFormatting.formatUntil(until))")
        } else {
            draft.recurrence = Recurrence(rrule: base)
        }
        applyNow()
    }

    private var endRepeatBinding: Binding<Bool> {
        Binding(
            get: { parsedRepeat.until != nil },
            set: { newValue in
                let current = parsedRepeat
                withAnimation(.smooth) {
                    setRecurrence(
                        base: current.preset == .custom ? current.custom : current.preset.rrule,
                        until: newValue ? Self.defaultEndRepeat() : nil
                    )
                }
            }
        )
    }

    private var endRepeatDateBinding: Binding<Date> {
        Binding(
            get: { parsedRepeat.until ?? Self.defaultEndRepeat() },
            set: { newValue in
                let current = parsedRepeat
                setRecurrence(
                    base: current.preset == .custom ? current.custom : current.preset.rrule,
                    until: newValue
                )
            }
        )
    }

    private var currentRepeatDisplay: String {
        let current = parsedRepeat
        if current.preset == .custom {
            return current.custom.flatMap { RecurrenceRule.parse($0)?.shortLabel } ?? "Custom"
        }
        return current.preset.displayName
    }

    // MARK: - Early reminder plumbing

    private func setEarlyReminder(_ early: EarlyReminder?) {
        draft.reminder = Reminder(enabled: true, early: early)
        applyNow()
    }

    private var currentEarlyPreset: EarlyReminderPreset {
        guard let early = draft.reminder?.early else { return .none }
        for preset in EarlyReminderPreset.allCases where preset != .none && preset != .custom {
            if let v = preset.value, v.value == early.value && v.unit == early.unit {
                return preset
            }
        }
        return .custom
    }

    private var currentEarlyDisplay: String {
        if currentEarlyPreset == .custom {
            return CustomEarlyReminder.displayName(for: draft.reminder?.early)
        }
        return currentEarlyPreset.displayName
    }

    // MARK: - Type switching

    /// Type-flip rule: an event is a calendar block — switching to Event makes
    /// it a plain (non-completable) event so its glyph becomes the calendar, and
    /// guarantees it has a start + end. Flips that lose the checkbox clear the
    /// done state so it can't linger invisibly.
    private func setType(_ newType: Item.ItemType) {
        guard itemTypePolicy.isAvailable(newType) else { return }
        guard newType != draft.type else { return }
        ItemTypeTransition.apply(newType, to: &draft)
        applyNow()
    }

    /// An event must always have a start and an end. Seed sensible defaults for
    /// whichever is missing (next top-of-the-hour start, +1h end), preserving
    /// any start the item already carried.
    private func ensureEventDates() {
        EventDefaults.normalize(&draft)
    }

    /// Run on open so an event that predates the start+end rule (or arrived from
    /// elsewhere without an end) is normalised. No-op for non-events.
    private func normalizeEventDates() {
        guard draft.type == .event else { return }
        ensureEventDates()
        applyNow()
    }

    // MARK: - Computed display helpers

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    private var typeDisplayName: String { Self.displayName(for: draft.type) }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == draft.listId }
    }

    private var resolvedSectionName: String? {
        guard let s = draft.section, !s.isEmpty else { return nil }
        return selectedList?.sections.first { $0.id.uuidString == s }?.name
    }

    private var dateSubtitle: String {
        guard let due = draft.due else { return "" }
        return ScheduleFormatting.relativeDateSubtitle(for: due)
    }

    private var timeSubtitle: String {
        guard let due = draft.due else { return "" }
        return ScheduleFormatting.timeSubtitle(for: due)
    }

    private static func displayName(for type: Item.ItemType) -> String {
        switch type {
        case .task:  return "Task"
        case .note:  return "Note"
        case .habit: return "Habit"
        case .event: return "Event"
        }
    }

    private static func defaultDue() -> Date {
        ReminderPreferences.defaultTime()
    }

    private static func defaultEndRepeat() -> Date {
        ScheduleFormatting.defaultEndRepeat()
    }

}

private struct DocumentLinkPickerSheet: View {
    let selection: DocumentLinkEditorSelection
    let onCancel: () -> Void
    let onDocument: (DocumentLinkEditorSelection) -> Void
    let onURL: (String, URL, DocumentLinkEditorSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsURLFields = false
    @State private var label: String
    @State private var urlText = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case label
        case url
    }

    init(selection: DocumentLinkEditorSelection,
         onCancel: @escaping () -> Void,
         onDocument: @escaping (DocumentLinkEditorSelection) -> Void,
         onURL: @escaping (String, URL, DocumentLinkEditorSelection) -> Void) {
        self.selection = selection
        self.onCancel = onCancel
        self.onDocument = onDocument
        self.onURL = onURL
        let selected = selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        _label = State(initialValue: selected.nilIfEmpty ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if showsURLFields {
                    urlForm
                } else {
                    choiceRows
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .background(ListsTokens.Background.base)
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                        onCancel()
                    } label: {
                        Text("Cancel")
                    }
                        .accessibilityIdentifier("document.linkPicker.cancel")
                }
                if showsURLFields {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Insert") {
                            guard let normalizedURL else { return }
                            dismiss()
                            onURL(labelText, normalizedURL, selection)
                        }
                        .fontWeight(.semibold)
                        .disabled(normalizedURL == nil)
                        .accessibilityIdentifier("document.linkPicker.url.insert")
                    }
                }
            }
        }
        .presentationDetents(showsURLFields ? [.medium] : [.height(260)])
        .presentationDragIndicator(.visible)
        .onChange(of: showsURLFields) { _, visible in
            if visible {
                focusedField = labelText.isEmpty ? .label : .url
            }
        }
        .accessibilityIdentifier("document.linkPicker")
    }

    private var choiceRows: some View {
        VStack(spacing: 12) {
            Button {
                dismiss()
                onDocument(selection)
            } label: {
                linkChoiceRow(title: "Document",
                              subtitle: "Link to another item in Lists",
                              systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.linkPicker.document")

            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    showsURLFields = true
                }
            } label: {
                linkChoiceRow(title: "URL",
                              subtitle: "Insert a web or email link",
                              systemImage: "link")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.linkPicker.url")
        }
    }

    private func linkChoiceRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ListsTokens.accent)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ListsTypography.body.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.primary)
                Text(subtitle)
                    .font(ListsTypography.caption1)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemFill))
        }
    }

    private var urlForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Label (optional)", text: $label)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .label)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                }
                .accessibilityIdentifier("document.linkPicker.url.label")

            TextField("URL", text: $urlText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .url)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                }
                .accessibilityIdentifier("document.linkPicker.url.url")

            if let normalizedURL {
                Label(normalizedURL.absoluteString, systemImage: "checkmark.circle.fill")
                    .font(ListsTypography.caption1)
                    .foregroundStyle(ListsTokens.accent)
                    .lineLimit(1)
            } else if !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Enter a valid link", systemImage: "exclamationmark.circle")
                    .font(ListsTypography.caption1)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var labelText: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedURL: URL? {
        DocumentMarkdownLinkBuilder.normalizedURL(from: urlText)
    }
}
