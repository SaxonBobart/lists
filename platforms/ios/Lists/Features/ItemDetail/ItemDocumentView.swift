import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import VisionKit
import QuickLook
import ImageIO

/// A live-editing document with a compact inline property toolbar between its
/// title and Markdown body. Title/body typing is debounced and flushed on
/// close; property controls reuse the existing immediate persistence bindings.
struct ItemDocumentView: View {
    let store: ItemStore
    let onBeginMove: ((Item) -> Void)?
    let onBeginDocumentLink: ((DocumentLinkSource) -> Void)?
    private let initialHeading: String?
    private let initialEditorFocus: DocumentEditorFocusTarget?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var itemUndoManager
    @Environment(\.attachmentMoveSession) private var attachmentMoveSession
    @State private var itemActionError: String?

    @State private var draft: Item
    @State private var editorMode: MarkdownEditorMode = .live
    /// One route sheet at a time — breadcrumb, navigator, or link picker.
    private enum ActiveSheet: Int, Identifiable { case breadcrumb, navigator, linkPicker, help, find, properties; var id: Int { rawValue } }
    private enum CopyScope: String { case selection, document }
    @State private var activeSheet: ActiveSheet?
    @State private var pendingLinkSelection: DocumentLinkEditorSelection?
    @State private var pendingAttachmentSelection: DocumentLinkEditorSelection?
    @State private var restoresAttachmentEditorFocus = true
    @State private var showingAttachmentSources = false
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var importTask: Task<Void, Never>?
    @State private var importProgress = ""
    @State private var showingVideoCamera = false
    @State private var isImportingAttachment = false
    @State private var showingAttachmentBrowser = false
    @State private var attachmentFailureMessage: String?
    @State private var unavailableLinkMessage: String?
    @State private var quickLookURL: URL?
    /// Restored only after the link picker has fully dismissed. Keeping this
    /// separate from `pendingLinkSelection` distinguishes Cancel from Insert.
    @State private var linkSelectionToRestore: DocumentEditorFocusTarget?
    @State private var propertyVisibility = DocumentPropertyVisibility()
    @State private var editingProperty: DocumentPropertyKind?
    @State private var showingDateTimeEditor = false
    @State private var showingListPicker = false
    @State private var customPropertyDraft: ItemCustomProperty?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// True while a field on this page holds the keyboard — the hide-keyboard
    /// tick only shows then (like the inline editor's Done on the list screens).
    /// Driven by keyboard show/hide notifications (observation only; no inset
    /// handling, so it doesn't touch UIKit's keyboard avoidance).
    @State private var isEditing = false
    @State private var isTableSelectionActive = false
    @State private var hasCopySelection = false
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
    @State private var documentWidth: CGFloat = 390
    @State private var recordingPresentationID = UUID()
    @State private var didApplyInitialHeading = false
    @State private var didApplyInitialEditorFocus = false
    @State private var needsRestoredKeyboardRefresh = false

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var showingDeleteConfirm = false
    @State private var persistenceOperation: PersistenceOperation?
    @State private var persistenceFailure: PersistenceFailure?
    @State private var propertyUpdateRejected = false

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
    private enum PendingTextField: Hashable { case title, body }
    /// Baselines exist only for net local text edits, never live metadata.
    @State private var pendingTextBaselines: [PendingTextField: String] = [:]

    init(item: Item,
         store: ItemStore,
         path: Binding<NavigationPath>? = nil,
         initialHeading: String? = nil,
         initialEditorFocus: DocumentEditorFocusTarget? = nil,
         onBeginMove: ((Item) -> Void)? = nil,
         onBeginDocumentLink: ((DocumentLinkSource) -> Void)? = nil) {
        self.store = store
        self.initialHeading = initialHeading
        self.initialEditorFocus = initialEditorFocus
        self.onBeginMove = onBeginMove
        self.onBeginDocumentLink = onBeginDocumentLink
        self.path = path
        _draft = State(initialValue: item)
        // Keep the revealed field mounted when the final saved tag is removed.
        _showTagField = State(initialValue: !item.tags.isEmpty)
        _propertyVisibility = State(initialValue: DocumentPropertyVisibility.load(for: item.id))
    }

    private var documentContent: some View {
        ScrollViewReader { _ in
            ScrollView {
                DocumentPageContent(
                    title: titleBinding,
                    bodyText: bodyBinding,
                    tags: tagsBinding,
                    item: draft,
                    attachmentStore: store,
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
                    onRequestAttachment: requestAttachment,
                    onOpenAttachment: openAttachment,
                    onOpenLink: openInlineLink,
                    onFormatRequested: showFormatPanel,
                    onTableSelectionChanged: { isActive in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isTableSelectionActive = isActive
                        }
                    },
                    onCopySelectionChanged: { hasCopySelection = $0 },
                    properties: inlineProperties
                )
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { documentWidth = $0 }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 46
            } action: { _, shouldShow in
                updateCollapsedTitleVisibility(shouldShow)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PendingSaveBanner(store: store)
                if propertyUpdateRejected {
                    HStack(alignment: .top, spacing: 12) {
                        Text("That property change wasn’t applied. Please try again.")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("document.property.error.message")
                        Button("Dismiss") { propertyUpdateRejected = false }
                            .accessibilityIdentifier("document.property.error.dismiss")
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .accessibilityIdentifier("document.property.error.banner")
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            refreshRestoredKeyboardIfNeeded()
            // Restoring focus can precede keyboard avoidance's final layout.
            // Recheck the current selection without changing it after that settles.
            DispatchQueue.main.async { focusBridge.revealFocusedSelection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
            // Switching from the URL field to a table cell can resize an
            // already-visible keyboard instead of posting another did-show.
            refreshRestoredKeyboardIfNeeded()
            DispatchQueue.main.async { focusBridge.revealFocusedSelection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isEditing = false }
            // Hiding the keyboard can be a title/body → tags focus transfer.
            // Keep an explicitly revealed field mounted for this document's
            // lifetime so its pending focus and uncommitted text survive.
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Promote the local debounced draft before the app's inactive
            // store flush; that flush cannot see a draft still in this view.
            // Idle pages must not replay an older copy over external changes.
            promotePendingTextDraft()
        }
        .onAppear {
            normalizeEventDates()
            scrollToInitialHeadingIfNeeded()
        }
        .task {
            guard !didApplyInitialEditorFocus, let initialEditorFocus else { return }
            // The returned document must mount its TextKit body/table before
            // focus is restored; cancellation leaves the captured range intact.
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if focusBridge.bodyView?.window != nil {
                    didApplyInitialEditorFocus = true
                    needsRestoredKeyboardRefresh = true
                    focusBridge.focusEditor(initialEditorFocus)
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        .fullScreenCover(isPresented: $showingAttachmentBrowser, onDismiss: {
            if let live = store.item(draft.id), live.body != draft.body {
                draft.body = live.body
                focusBridge.replaceBody(live.body)
            }
            if attachmentMoveSession?.movingFileID != nil { dismiss() }
        }) {
            ItemAttachmentsSheet(references: MarkdownMediaReference.distinctReferences(in: draft.body), itemID: draft.id, store: store)
        }
        .onDisappear { finalizeAndFlush(); MarkdownPlayback.shared.stop() }
        .onChange(of: MarkdownAudioRecording.shared.session?.fileName) { previous, current in
            guard let previous, current == nil else { return }
            if let item = store.items.first(where: { $0.id == draft.id }),
               !MarkdownMediaReference.references(in: item.body).contains(where: { $0.path.hasSuffix(previous) }) {
                var body = draft.body
                for ref in MarkdownMediaReference.references(in: body).reversed() where ref.path.hasSuffix(previous) {
                    body = (body as NSString).replacingCharacters(in: ref.range, with: "")
                }
                if body != draft.body { focusBridge.replaceBody(body) }
            }
        }
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
        .alert(
            "Couldn’t Add Attachment",
            isPresented: Binding(
                get: { attachmentFailureMessage != nil },
                set: { if !$0 { attachmentFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentFailureMessage ?? "The file could not be imported.")
        }
        .alert(
            "Linked Item Unavailable",
            isPresented: Binding(
                get: { unavailableLinkMessage != nil },
                set: { if !$0 { unavailableLinkMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("document.link.unavailable.dismiss")
        } message: {
            Text(unavailableLinkMessage ?? "This linked item is no longer available.")
        }
        .sheet(item: $activeSheet, onDismiss: restoreLinkSelectionAfterDismiss) { sheet in
            switch sheet {
            case .properties:
                DocumentAddPropertyPicker(fields: availablePropertyFields,
                    visible: Set(toolbarPropertyFields.map(\.rawValue)), hidden: propertyVisibility.hidden,
                    unavailable: unavailablePropertyFields, onAdd: addProperty)
            case .breadcrumb: breadcrumbSheet
            case .navigator:  navigatorSheet
            case .linkPicker: linkPickerSheet
            case .help: EditorHelpView()
            case .find: DocumentFindReplaceView(source: draft.body, onReplace: { source in
                focusBridge.replaceBody(source)
            }, onFind: { range in
                activeSheet = nil
                DispatchQueue.main.async { focusBridge.focusBody(range: range) }
            })
            }
        }
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
        .sheet(isPresented: $showingDateTimeEditor, onDismiss: {
            if let live = store.item(draft.id) { draft = live }
        }) {
            InlineDateTimePopover(item: store.item(draft.id) ?? draft, store: store)
        }
        .fullScreenCover(isPresented: $showingListPicker) {
            DocumentListHierarchyPicker(store: store, selectedListID: draft.listId) { list in
                guard list.deletedAt == nil, store.lists.contains(where: { $0.id == list.id && $0.deletedAt == nil }) else { return }
                if draft.listId != list.id {
                    draft.listId = list.id
                    draft.section = nil
                    applyNow()
                }
                showingListPicker = false
            }
        }
    }

    private var attachmentContent: some View {
        documentContent
        .disabled(isImportingAttachment)
        .confirmationDialog(
            "Add Attachment",
            isPresented: $showingAttachmentSources,
            titleVisibility: .visible
        ) {
            Button("Photos and Videos", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }.accessibilityIdentifier("document.attachment.photos")
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo", systemImage: "camera") { showingCamera = true }.accessibilityIdentifier("document.attachment.camera")
                Button("Record Video", systemImage: "video") {
                    if MarkdownAudioRecording.shared.session == nil { showingVideoCamera = true }
                    else { attachmentFailureMessage = "Stop and save the current recording before recording video."; restoreAttachmentSelection() }
                }.accessibilityIdentifier("document.attachment.video")
            }
            if VNDocumentCameraViewController.isSupported {
                Button("Scan Document", systemImage: "doc.viewfinder") { showingScanner = true }.accessibilityIdentifier("document.attachment.scan")
            }
            Button("Record Audio", systemImage: "mic") {
                guard let selection = pendingAttachmentSelection else { return }
                Task {
                    do {
                        let path = try await MarkdownAudioRecording.shared.start(itemID: draft.id, title: draft.title)
                        let destination = DocumentMarkdownIndex.attachmentDestination(path, from: draft, lists: store.lists)
                        insertAttachmentMarkdown("[Audio recording](\(destination))", selection: selection)
                        finalizeAndFlush()
                    } catch { attachmentImportFailed(error) }
                }
            }.accessibilityIdentifier("document.record.audio")
            Button("Attach Files", systemImage: "folder") { showingFileImporter = true }.accessibilityIdentifier("document.attachment.files")
            Button("Cancel", role: .cancel) { restoreAttachmentSelection() }.accessibilityIdentifier("document.attachment.cancel")
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotos, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            importTask = Task { await importPhotos(items) }
        }
        .onChange(of: showingPhotoPicker) { _, visible in
            if !visible, selectedPhotos.isEmpty, !isImportingAttachment { restoreAttachmentSelection() }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            importSelectedFile(result)
        }
        .overlay(alignment: .bottom) { importOverlay }
    }

    var body: some View {
        attachmentContent
        .safeAreaInset(edge: .bottom, spacing: 0) { MarkdownRecordingStrip(store: store) }
        .onAppear {
            MarkdownAudioRecording.shared.visibleDocuments.insert(recordingPresentationID)
            focusBridge.attachmentMenu = keyboardAttachmentMenu
        }
        .onDisappear { MarkdownAudioRecording.shared.visibleDocuments.remove(recordingPresentationID); focusBridge.attachmentMenu = nil }
        .fullScreenCover(isPresented: $showingVideoCamera, onDismiss: restoreAttachmentSelectionIfNeeded) {
            MarkdownVideoCameraPicker { url in
                showingVideoCamera = false
                guard let url else { restoreAttachmentSelection(); return }
                importSelectedFile(.success([url]))
            }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: restoreAttachmentSelectionIfNeeded) {
            MarkdownCameraPicker { image in
                showingCamera = false
                guard let image else {
                    restoreAttachmentSelection()
                    return
                }
                Task { await importImageData(image, fileName: "Photo.jpg") }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingScanner, onDismiss: restoreAttachmentSelectionIfNeeded) {
            MarkdownDocumentScanner { images in
                showingScanner = false
                guard images.isEmpty == false else {
                    restoreAttachmentSelection()
                    return
                }
                Task { await importScannedDocument(images) }
            } onFailure: { error in
                showingScanner = false
                attachmentImportFailed(error)
            }
            .ignoresSafeArea()
        }
        .quickLookPreview($quickLookURL)
    }

    @ViewBuilder private var importOverlay: some View {
        if isImportingAttachment {
            HStack {
                ProgressView()
                Text(importProgress.isEmpty ? "Adding attachment…" : importProgress).font(.callout)
                if importTask != nil { Button("Cancel") { importTask?.cancel() }.accessibilityIdentifier("document.import.cancel") }
            }.padding().background(.regularMaterial, in: Capsule()).padding()
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
        ToolbarItem(placement: .topBarLeading) {
            if showsCollapsedTitle { collapsedToolbarTitle }
        }.sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                finalizeAndFlush()
                focusBridge.endEditing()
                showingAttachmentBrowser = true
            } label: {
                Image(systemName: "paperclip")
                    .accessibilityLabel("Attachments")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.attachments.open")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ItemActionsMenu(actions: ItemActions(item: draft, store: store,
                    onOpen: openDetails, onDelete: { showingDeleteConfirm = true },
                    onError: { itemActionError = $0 }, onSchedule: openDetails,
                    onMove: onBeginMove.map { begin in { applyNow(); beginMoveFromDetails(draft, begin: begin) } },
                    undoManager: itemUndoManager, onCut: {
                        applyNow()
                        Task {
                            do {
                                try await ItemClipboard.shared.cut(draft, store: store, undoManager: itemUndoManager)
                                dismiss()
                            } catch { itemActionError = error.localizedDescription }
                        }
                    }, onToggle: toggleDone,
                    onFlag: { draft.flagged.toggle(); applyNow() },
                    onPriority: { draft.priority = $0; applyNow() }))
                organizationMenu
                Divider()
                Section {
                    Button("Undo", systemImage: "arrow.uturn.backward") { focusBridge.undo() }
                        .disabled(!focusBridge.canUndo)
                        .accessibilityIdentifier("document.undo")
                    Button("Redo", systemImage: "arrow.uturn.forward") { focusBridge.redo() }
                        .disabled(!focusBridge.canRedo)
                        .accessibilityIdentifier("document.redo")
                    Button("Find and Replace", systemImage: "magnifyingglass") { activeSheet = .find }
                        .accessibilityIdentifier("document.find")
                    Button("Attachments", systemImage: "paperclip") { focusBridge.requestAttachment?() }
                        .accessibilityIdentifier("document.attachments.add")
                    Button("Editor Help", systemImage: "questionmark.circle") { activeSheet = .help }
                        .accessibilityIdentifier("document.help")
                    if hasHierarchyContext {
                        Button("Related Items", systemImage: "point.3.connected.trianglepath.dotted") {
                            focusBridge.endEditing()
                            activeSheet = .breadcrumb
                        }.accessibilityIdentifier("document.related")
                    }
                }
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
                Menu {
                    Section("Selection") {
                        copyActions(scope: .selection)
                    }
                    Section("Document") {
                        copyActions(scope: .document)
                    }
                } label: {
                    Label("Copy As", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("document.copy.menu")
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.menu")
            .itemMutationErrorAlert($itemActionError)
        }
        if isEditing || isTableSelectionActive || formatPanelSession != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    closeFormatPanel(refocusesBody: false)
                    focusBridge.endEditing()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isEditing = false
                        isTableSelectionActive = false
                    }
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

    @ViewBuilder
    private func copyActions(scope: CopyScope) -> some View {
        ForEach(MarkdownCopyFormat.allCases, id: \.self) { format in
            Button {
                let source = scope == .selection
                    ? focusBridge.currentCopySelection()
                    : draft.body
                guard let source else { return }
                MarkdownClipboard.copy(source, as: format)
            } label: {
                Label(format.title, systemImage: format.systemImage)
            }
            .disabled(scope == .selection && !hasCopySelection)
            .accessibilityIdentifier(
                "document.copy.\(scope.rawValue).\(copyFormatIdentifier(format))"
            )
        }
    }

    private func copyFormatIdentifier(_ format: MarkdownCopyFormat) -> String {
        switch format {
        case .markdown: "markdown"
        case .richText: "rich"
        case .plainText: "plain"
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
            .frame(width: max(40, min(170, documentWidth - (isEditing || isTableSelectionActive || formatPanelSession != nil ? 310 : 250))), alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
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

    /// Keyboard shortcuts open the same on-demand property picker.
    private func openDetails() {
        closeFormatPanel(refocusesBody: false)
        focusBridge.endEditing()
        editingProperty = .date
    }

    /// The quick bar's tags button: reveal the tag field (if hidden) and focus
    /// it so the user can type a tag straight away.
    private func revealTagField() {
        withAnimation(.easeInOut(duration: 0.2)) {
            propertyVisibility.add(.tags)
            propertyVisibility.save(for: draft.id)
            showTagField = true
            editingProperty = nil
        }
        tagFocusToken += 1
    }

    private func requestDocumentLink(_ selection: DocumentLinkEditorSelection) {
        focusBridge.endEditing()
        finalizeAndFlush()
        pendingLinkSelection = selection
        linkSelectionToRestore = selection.focusTarget
        activeSheet = .linkPicker
    }

    private func keyboardAttachmentMenu() -> UIMenu {
        func action(_ title: String, _ symbol: String, _ id: String, perform: @escaping () -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol), identifier: UIAction.Identifier(id)) { _ in
                guard let body = focusBridge.bodyView else { return }
                let range = DocumentMarkdownLinkBuilder.validSelection(body.selectedRange, in: draft.body)
                pendingAttachmentSelection = DocumentLinkEditorSelection(range: range, selectedText: (draft.body as NSString).substring(with: range))
                finalizeAndFlush()
                perform()
            }
        }
        var actions: [UIMenuElement] = [action("Photos and Videos", "photo.on.rectangle", "document.attachment.photos") { showingPhotoPicker = true }]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actions.append(action("Take Photo", "camera", "document.attachment.camera") { showingCamera = true })
            actions.append(action("Record Video", "video", "document.attachment.video") {
                if MarkdownAudioRecording.shared.session == nil { showingVideoCamera = true }
                else { attachmentFailureMessage = "Stop and save the current recording before recording video."; restoreAttachmentSelection() }
            })
        }
        if VNDocumentCameraViewController.isSupported {
            actions.append(action("Scan Document", "doc.viewfinder", "document.attachment.scan") { showingScanner = true })
        }
        actions.append(action("Record Audio", "mic", "document.record.audio") {
            guard let selection = pendingAttachmentSelection else { return }
            Task {
                do {
                    let path = try await MarkdownAudioRecording.shared.start(itemID: draft.id, title: draft.title)
                    let destination = DocumentMarkdownIndex.attachmentDestination(path, from: draft, lists: store.lists)
                    insertAttachmentMarkdown("[Audio recording](\(destination))", selection: selection)
                    finalizeAndFlush()
                } catch { attachmentImportFailed(error) }
            }
        })
        actions.append(action("Attach Files", "folder", "document.attachment.files") { showingFileImporter = true })
        return UIMenu(children: actions)
    }

    private func requestAttachment(_ selection: DocumentLinkEditorSelection, pastedImageData: Data?) {
        finalizeAndFlush()
        restoresAttachmentEditorFocus = true
        pendingAttachmentSelection = selection
        if let pastedImageData {
            isImportingAttachment = true
            Task {
                defer { isImportingAttachment = false }
                if let source = CGImageSourceCreateWithData(pastedImageData as CFData, nil),
                   let type = CGImageSourceGetType(source) {
                    let ext = UTType(type as String)?.preferredFilenameExtension ?? "png"
                    await importAttachmentData(pastedImageData, fileName: "Pasted Image.\(ext)", isImage: true)
                } else {
                    attachmentImportFailed(AttachmentStorageError.emptyData)
                }
            }
        } else {
            showingAttachmentSources = true
        }
    }

    private func attachmentMarkdown(_ attachment: StoredAttachment, label: String, isImage: Bool) -> String {
        let destination = DocumentMarkdownIndex.attachmentDestination(attachment.relativePath, from: draft, lists: store.lists)
        return "\(isImage ? "!" : "")[\(DocumentMarkdownLinkBuilder.escapedLabel(label))](\(destination))"
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard let selection = pendingAttachmentSelection else { return }
        isImportingAttachment = true
        defer { isImportingAttachment = false; selectedPhotos = []; importTask = nil }
        var inserted: [String] = []
        var failures: [String] = []
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            importProgress = "Adding \(index + 1) of \(items.count)…"
            do {
                guard let file = try await item.loadTransferable(type: MarkdownPickedFile.self) else { throw AttachmentStorageError.emptyData }
                defer { try? FileManager.default.removeItem(at: file.url) }
                try Task.checkCancellation()
                let attachment = try await store.importAttachment(fileURL: file.url)
                let image = item.supportedContentTypes.contains { $0.conforms(to: .image) }
                inserted.append(attachmentMarkdown(attachment, label: image ? "Photo" : "Video", isImage: image))
            } catch is CancellationError { break }
            catch { failures.append(error.localizedDescription) }
        }
        if !inserted.isEmpty { insertAttachmentMarkdown(inserted.joined(separator: "\n\n"), selection: selection) }
        else { restoreAttachmentSelection() }
        if !failures.isEmpty { attachmentFailureMessage = failures.joined(separator: "\n") }
    }

    private func importImageData(_ image: UIImage, fileName: String) async {
        isImportingAttachment = true
        defer { isImportingAttachment = false }
        guard let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData() else {
            attachmentImportFailed(AttachmentStorageError.emptyData)
            return
        }
        await importAttachmentData(data, fileName: fileName, isImage: true)
    }

    private func importSelectedFile(_ result: Result<[URL], any Error>) {
        guard let selection = pendingAttachmentSelection else { return }
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { restoreAttachmentSelection() }
            else { attachmentImportFailed(error) }
        case .success(let urls):
            isImportingAttachment = true
            importTask = Task {
                defer { isImportingAttachment = false; importTask = nil }
                var inserted: [String] = []
                var failures: [String] = []
                for (index, url) in urls.enumerated() {
                    if Task.isCancelled { break }
                    importProgress = "Adding \(index + 1) of \(urls.count)…"
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let attachment = try await store.importAttachment(fileURL: url)
                        inserted.append(attachmentMarkdown(attachment, label: url.deletingPathExtension().lastPathComponent, isImage: false))
                    } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                if !inserted.isEmpty { insertAttachmentMarkdown(inserted.joined(separator: "\n\n"), selection: selection) }
                else { restoreAttachmentSelection() }
                if !failures.isEmpty { attachmentFailureMessage = failures.joined(separator: "\n") }
            }
        }
    }

    private func importScannedDocument(_ images: [UIImage]) async {
        isImportingAttachment = true
        defer { isImportingAttachment = false }
        let data = Self.pdfData(from: images)
        await importAttachmentData(data, fileName: "Scanned Document.pdf", isImage: false)
    }

    private func importAttachmentData(_ data: Data, fileName: String, isImage: Bool) async {
        guard let selection = pendingAttachmentSelection else { return }
        do {
            let attachment = try await store.importAttachment(
                data: data,
                originalFileName: fileName
            )
            let rawLabel = selection.selectedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            let label = DocumentMarkdownLinkBuilder.escapedLabel(rawLabel)
            let destination = DocumentMarkdownIndex.attachmentDestination(attachment.markdownDestination, from: draft, lists: store.lists)
            let markdown = isImage
                ? "![\(label)](\(destination))"
                : "[\(label)](\(destination))"
            insertAttachmentMarkdown(markdown, selection: selection)
        } catch {
            attachmentImportFailed(error)
        }
    }

    private func insertAttachmentMarkdown(
        _ markdown: String,
        selection: DocumentLinkEditorSelection
    ) {
        let valid = DocumentMarkdownLinkBuilder.validSelection(selection.range, in: draft.body)
        let ns = draft.body as NSString
        let needsLeadingBreak = valid.location > 0 && ns.character(at: valid.location - 1) != 0x0A
        let needsTrailingBreak = NSMaxRange(valid) < ns.length
            && ns.character(at: NSMaxRange(valid)) != 0x0A
        let inserted = (needsLeadingBreak ? "\n" : "")
            + markdown
            + (needsTrailingBreak ? "\n" : "")
        focusBridge.replaceBody((draft.body as NSString).replacingCharacters(in: valid, with: inserted))
        applyNow()
        pendingAttachmentSelection = nil
        let caret = NSRange(location: valid.location + (inserted as NSString).length, length: 0)
        if restoresAttachmentEditorFocus {
            DispatchQueue.main.async { focusBridge.focusBody(range: caret) }
        }
    }

    private func attachmentImportFailed(_ error: Error) {
        attachmentFailureMessage = error.localizedDescription
        restoreAttachmentSelection()
    }

    private func restoreAttachmentSelectionIfNeeded() {
        if isImportingAttachment == false { restoreAttachmentSelection() }
    }

    private func restoreAttachmentSelection() {
        guard let selection = pendingAttachmentSelection else { return }
        pendingAttachmentSelection = nil
        if restoresAttachmentEditorFocus {
            DispatchQueue.main.async { focusBridge.focusBody(range: selection.range) }
        }
    }

    private func openAttachment(_ relativePath: String) {
        Task {
            do {
                quickLookURL = try await store.attachmentURL(for: relativePath)
            } catch {
                attachmentFailureMessage = error.localizedDescription
            }
        }
    }

    private func openInlineLink(_ url: URL) {
        if MarkdownAttachmentIndex.isSafeRelativePath(url.relativeString) {
            openAttachment(url.relativeString)
            return
        }
        let resolved = DocumentMarkdownIndex.resolveInternalDestination(
            url.relativeString,
            from: draft,
            items: store.items,
            lists: store.lists,
            documentFileNames: store.documentFileNamesById
        )
        guard let targetID = resolved?.itemId else {
            if url.scheme == "lists" || DocumentMarkdownIndex.isPotentialInternalDestination(url.relativeString) {
                unavailableLinkMessage = "This Lists link does not point to an available item."
                return
            }
            UIApplication.shared.open(url)
            return
        }
        guard store.items.contains(where: { $0.id == targetID && $0.deletedAt == nil }) else {
            unavailableLinkMessage = "The linked item may have been deleted or moved out of this library."
            return
        }

        let heading = resolved?.heading
        let targetItem = targetID == draft.id ? draft : store.item(targetID)
        if let heading, let targetItem,
           DocumentMarkdownIndex.heading(heading, title: targetItem.title, body: targetItem.body) == nil {
            unavailableLinkMessage = "The linked heading could not be found. It may have been renamed or removed."
            return
        }
        if targetID == draft.id {
            guard let heading,
                  let outline = DocumentMarkdownIndex.heading(heading, title: draft.title, body: draft.body),
                  case .body(let range) = outline.target else {
                focusBridge.endEditing()
                return
            }
            focusBridge.endEditing()
            focusBridge.scrollBody(range: range)
            return
        }

        focusBridge.endEditing()
        finalizeAndFlush()
        path?.wrappedValue.append(BreadcrumbDestination(id: targetID, heading: heading))
    }

    private static func pdfData(from images: [UIImage]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let page = context.pdfContextBounds.insetBy(dx: 24, dy: 24)
                let scale = min(page.width / image.size.width, page.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(
                    x: page.midX - size.width / 2,
                    y: page.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                ))
            }
        }
    }

    private func insertDocumentLink(target: Item,
                                    heading: DocumentOutlineEntry?,
                                    selection: DocumentLinkEditorSelection) {
        let selectedLabel = selection.selectedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTitle = target.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Untitled"
        let label = selectedLabel.nilIfEmpty ?? heading?.title ?? targetTitle
        let destination = DocumentMarkdownIndex.portableDestination(
            from: draft,
            to: target,
            heading: heading?.anchor,
            lists: store.lists,
            documentFileNames: store.documentFileNamesById
        )
        let inserted = DocumentMarkdownLinkBuilder.markdownLink(label: label, destination: destination)
        let replacement = DocumentMarkdownLinkBuilder.replacement(
            selection,
            in: draft.body,
            insertedMarkdown: inserted
        )
        draft.body = replacement.body
        applyNow()
        linkSelectionToRestore = replacement.focusTarget
        pendingLinkSelection = nil
        activeSheet = nil
    }

    private func insertURLLink(label: String, url: URL, selection: DocumentLinkEditorSelection) {
        let replacement = DocumentMarkdownLinkBuilder.replacement(
            selection,
            in: draft.body,
            label: label,
            url: url
        )
        draft.body = replacement.body
        applyNow()
        linkSelectionToRestore = replacement.focusTarget
        pendingLinkSelection = nil
        activeSheet = nil
    }

    private func restoreLinkSelectionAfterDismiss() {
        guard let target = linkSelectionToRestore else { return }
        linkSelectionToRestore = nil
        pendingLinkSelection = nil
        needsRestoredKeyboardRefresh = true
        focusBridge.focusEditor(target)
        // Recheck visibility now; refresh the input views once the keyboard's
        // did-show/did-change notification confirms its responder transition.
        DispatchQueue.main.async {
            focusBridge.revealFocusedSelection()
        }
    }

    private func refreshRestoredKeyboardIfNeeded() {
        guard needsRestoredKeyboardRefresh else { return }
        // UIKit can initially omit the restored editor's accessory height.
        // Reload once after attachment so native avoidance includes the bar.
        needsRestoredKeyboardRefresh = false
        focusBridge.reloadFocusedInputViews()
    }

    private func scrollToInitialHeadingIfNeeded() {
        guard didApplyInitialHeading == false,
              let initialHeading else { return }
        didApplyInitialHeading = true
        guard let entry = DocumentMarkdownIndex.heading(initialHeading, title: draft.title, body: draft.body),
              case .body(let range) = entry.target else {
            unavailableLinkMessage = "The linked heading could not be found. It may have been renamed or removed."
            return
        }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                focusBridge.scrollBody(range: range)
            }
        }
    }

    // MARK: - Breadcrumb

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

    private var availablePropertyFields: [DocumentPropertyKind] {
        DocumentPropertyKind.allCases.filter { field in
            switch field {
            case .allDay, .completable: draft.type == .event
            case .date, .time: draft.type != .event
            case .history: showsRecurrenceHistory
            case .source: draft.calendarImport != nil
        case .section: draft.section != nil
        case .list: true
            default: true
            }
        }
    }

    private var unavailablePropertyFields: Set<String> {
        var fields = Set<String>()
        if draft.due == nil { fields.formUnion([DocumentPropertyKind.time.rawValue, DocumentPropertyKind.repeatRule.rawValue]) }
        if !hasTime { fields.insert(DocumentPropertyKind.timeZone.rawValue) }
        if draft.reminder?.enabled != true { fields.insert(DocumentPropertyKind.earlyReminder.rawValue) }
        return fields
    }

    private func isPropertyActive(_ field: DocumentPropertyKind) -> Bool {
        switch field {
        case .flag: draft.flagged
        case .priority: draft.priority != .none
        case .tags: !draft.tags.isEmpty
        case .date: draft.due != nil
        case .time: hasTime
        case .reminder: draft.reminder?.enabled == true
        case .alarm: draft.triggers?.alarm?.enabled == true
        case .repeatRule: parsedRepeat.preset != .never
        case .earlyReminder: draft.reminder?.early != nil
        case .allDay: draft.dueAllDay
        case .completable: draft.completable
        case .timeZone: draft.dueTimeZone != nil
        case .history: showsRecurrenceHistory
        case .source: draft.calendarImport != nil
        case .section: draft.section != nil
        case .list: true
        }
    }

    private func addProperty(_ field: DocumentPropertyKind) {
        propertyVisibility.add(field)
        propertyVisibility.save(for: draft.id)
        if field == .tags { showTagField = true }
    }

    private var toolbarPropertyFields: [DocumentPropertyKind] { [.date, .flag, .priority, .tags, .section, .list] }

    private var inlineProperties: some View {
        VStack(alignment: .leading, spacing: 8) {
            DocumentPropertyToolbar(usesGrid: documentWidth < 360 || dynamicTypeSize.isAccessibilitySize,
                                    accessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                ForEach(toolbarPropertyFields) { field in
                    propertyToolbarButton(field)
                }
            } addControl: {
                Button {
                    focusBridge.endEditing()
                    customPropertyDraft = ItemCustomProperty(name: "")
                } label: {
                    Image(systemName: "plus").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain).padding(.top, 4)
                .disabled(draft.hasCustomPropertyStorageConflict)
                .accessibilityLabel("New custom property")
                .accessibilityIdentifier("document.custom.add")
                .popover(item: $customPropertyDraft) { property in
                    DocumentCustomPropertyEditor(property: property, existingProperties: draft.customProperties,
                        onSave: saveCustomProperty, onCancel: { customPropertyDraft = nil })
                        .frame(width: min(340, max(240, documentWidth - 32)))
                        .presentationCompactAdaptation(.popover)
                }
            }
            if draft.hasCustomPropertyStorageConflict {
                Text("Existing custom-property metadata is preserved, but cannot be edited here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(draft.customProperties) { property in
                Button { focusBridge.endEditing(); customPropertyDraft = property } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(property.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(property.value.isEmpty ? "Add value" : property.value)
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("document.custom.row.\(property.id.uuidString.lowercased())")
                .contextMenu {
                    Button("Remove property", systemImage: "trash", role: .destructive) {
                        draft.customProperties.removeAll { $0.id == property.id }; applyNow()
                    }.accessibilityIdentifier("document.custom.remove.\(property.id.uuidString.lowercased())")
                }
            }
        }.id("document.properties")
    }

    @ViewBuilder
    private func propertyToolbarButton(_ field: DocumentPropertyKind) -> some View {
        let icon = propertyToolbarIcon(field)
        if field == .priority {
            Menu {
                ForEach(Item.Priority.allCases, id: \.self) { priority in
                    Button {
                        priorityBinding.wrappedValue = priority
                    } label: {
                        if draft.priority == priority { Label(priority.displayName, systemImage: "checkmark") }
                        else { Text(priority.displayName) }
                    }
                    .accessibilityIdentifier("document.priority.option.\(priority.rawValue)")
                }
            } label: { icon }
            .accessibilityLabel("Priority")
            .accessibilityValue(propertyToolbarValue(field))
            .accessibilityIdentifier("document.property.control.priority")
        } else if field == .section {
            Menu {
                Button {
                    sectionBinding.wrappedValue = nil
                } label: {
                    if draft.section == nil { Label("No section", systemImage: "checkmark") }
                    else { Text("No section") }
                }
                .accessibilityIdentifier("document.section.none")
                if let selectedList {
                    ForEach(selectedList.sections.sorted(by: { $0.position < $1.position })) { section in
                        Button {
                            sectionBinding.wrappedValue = section.id.uuidString
                        } label: {
                            if draft.section == section.id.uuidString { Label(section.name, systemImage: "checkmark") }
                            else { Text(section.name) }
                        }
                        .accessibilityIdentifier("document.section.\(section.id.uuidString.lowercased())")
                    }
                }
            } label: { icon }
            .accessibilityLabel("Section")
            .accessibilityValue(propertyToolbarValue(field))
            .accessibilityIdentifier("document.property.control.section")
        } else {
            Button {
                focusBridge.endEditing()
                switch field {
                case .flag:
                    draft.flagged.toggle()
                    applyNow()
                case .date:
                    applyNow()
                    showingDateTimeEditor = true
                case .list:
                    applyNow()
                    showingListPicker = true
                case .tags:
                    revealTagField()
                default: editingProperty = field
                }
            } label: { icon }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(field.title))
            .accessibilityValue(propertyToolbarValue(field))
            .accessibilityIdentifier("document.property.control.\(field.rawValue.lowercased())")
            .popover(isPresented: Binding(get: { editingProperty == field }, set: { if !$0 { editingProperty = nil } })) {
                propertyEditor(field).presentationCompactAdaptation(.popover)
            }
        }
    }

    private func propertyToolbarIcon(_ field: DocumentPropertyKind) -> some View {
        Image(systemName: field == .flag && draft.flagged ? "flag.fill" : field.icon)
            .font(.body.weight(.medium))
            .foregroundStyle(field == .flag && draft.flagged ? ListsTokens.Semantic.warning :
                isPropertyActive(field) ? Color.accentColor : Color.secondary)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func saveCustomProperty(_ property: ItemCustomProperty) {
        guard property.hasValidName(among: draft.customProperties), !draft.hasCustomPropertyStorageConflict else { return }
        if let index = draft.customProperties.firstIndex(where: { $0.id == property.id }) {
            draft.customProperties[index] = property
        } else { draft.customProperties.append(property) }
        applyNow()
        customPropertyDraft = nil
    }

    private func propertyToolbarValue(_ field: DocumentPropertyKind) -> String {
        switch field {
        case .tags: draft.tags.isEmpty ? "No tags" : draft.tags.joined(separator: ", ")
        case .priority: draft.priority.displayName
        case .section: selectedList?.sections.first(where: { $0.id.uuidString == draft.section })?.name ?? "No section"
        case .list: selectedList?.name ?? "No list"
        case .date: draft.due?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
        default: isPropertyActive(field) ? "On" : "Off"
        }
    }

    private var eventDateEditor: some View {
        VStack(spacing: 8) {
            DocumentPropertyRow(title: "Starts", systemImage: "calendar") {
                DatePicker("Starts", selection: Binding(get: { dueBinding.wrappedValue }, set: { value in
                    let offset = value.timeIntervalSince(draft.due ?? value)
                    draft.end = (draft.end ?? draft.due ?? value).addingTimeInterval(offset)
                    draft.due = value
                    applyNow()
                }), displayedComponents: draft.dueAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier("document.due")
            }
            DocumentPropertyRow(title: "Ends", systemImage: "calendar.badge.checkmark") {
                DatePicker("Ends", selection: endBinding, in: dueBinding.wrappedValue...,
                           displayedComponents: draft.dueAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier("document.ends")
            }
        }
    }

    @ViewBuilder
    private func propertyEditor(_ field: DocumentPropertyKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if field == .date && draft.type == .event {
                eventDateEditor
            } else if field == .date {
                propertyControl(.date)
                if draft.due != nil { propertyControl(.time) }
            } else {
                propertyControl(field)
            }
            if field == .date && draft.due != nil {
                DisclosureGroup("Scheduling") {
                    propertyControl(.reminder)
                    propertyControl(.alarm)
                    propertyControl(.repeatRule)
                    propertyControl(.earlyReminder)
                    propertyControl(.timeZone)
                    if draft.type == .event { propertyControl(.allDay); propertyControl(.completable) }
                }.font(.subheadline).accessibilityIdentifier("document.schedule.disclosure")
            }
            if field == .tags {
                DocumentTagsRow(tags: tagsBinding, focusToken: tagFocusToken,
                                isVisible: true, alignsToLeadingControl: false)
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(idealWidth: 320, maxWidth: 360)
    }

    @ViewBuilder
    private func propertyControl(_ field: DocumentPropertyKind) -> some View {
        switch field {
        case .section:
            DocumentPropertyRow(title: "Section", systemImage: field.icon) {
                Button("Choose section") { editingProperty = nil; showSectionPicker = true }
                    .accessibilityIdentifier("document.section")
            }
        case .list:
            DocumentPropertyRow(title: "List", systemImage: field.icon) {
                Menu {
                    ForEach(activeLists) { list in
                        Button(list.name) {
                            if draft.listId != list.id { draft.listId = list.id; draft.section = nil; applyNow() }
                        }.accessibilityIdentifier("document.list.\(list.id.lowercased())")
                    }
                } label: { Text(selectedList?.name ?? "Choose list") }
                .accessibilityIdentifier("document.list")
            }
        case .flag:
            DocumentPropertyToggle(title: "Flag", systemImage: "flag", isOn: flaggedBinding, identifier: "document.flag")
        case .priority:
            DocumentPropertyRow(title: "Priority", systemImage: field.icon) {
                Menu {
                    ForEach(Item.Priority.allCases, id: \.self) { priority in
                        Button(priority.displayName) { priorityBinding.wrappedValue = priority }
                            .accessibilityIdentifier("document.priority.option.\(priority.rawValue)")
                    }
                } label: { Text(draft.priority == .none ? "Set priority" : draft.priority.displayName) }
                .accessibilityIdentifier("document.priority")
            }
        case .tags:
            DocumentPropertyRow(title: "Tags", systemImage: field.icon) {
                Button(draft.tags.isEmpty ? "Add tags" : draft.tags.joined(separator: ", ")) { revealTagField() }
                    .accessibilityIdentifier("document.tags.edit")
            }
        case .date:
            DocumentPropertyRow(title: "Date", systemImage: field.icon) {
                if draft.due != nil {
                    DatePicker("Date", selection: dueBinding, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier("document.due")
                } else {
                    Button("Set date") { hasDateBinding.wrappedValue = true }.accessibilityIdentifier("document.due")
                }
            }
        case .time:
            DocumentPropertyRow(title: "Time", systemImage: field.icon) {
                if hasTime {
                    DatePicker("Time", selection: dueBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier("document.time")
                } else {
                    Button("Set time") { hasTimeBinding.wrappedValue = true }.accessibilityIdentifier("document.time")
                }
            }
        case .reminder:
            DocumentPropertyToggle(title: "Reminder", systemImage: field.icon, isOn: reminderBinding, identifier: "document.reminder")
        case .alarm:
            DocumentPropertyToggle(title: "Alarm", systemImage: field.icon, isOn: alarmBinding, identifier: "document.alarm")
        case .repeatRule:
            DocumentPropertyRow(title: "Repeat", systemImage: field.icon) {
                Menu {
                    ForEach(RepeatPreset.taskOptions, id: \.self) { preset in
                        Button(preset.displayName) { setRepeatPreset(preset) }
                            .accessibilityIdentifier("document.repeat.\(preset.rawValue.lowercased())")
                    }
                } label: { Text(draft.due == nil ? "Add a date first" : parsedRepeat.preset == .never ? "Set repeat" : currentRepeatDisplay) }
                .disabled(draft.due == nil)
                .accessibilityIdentifier("document.repeat")
            }
            if parsedRepeat.preset != .never {
                if parsedRepeat.until != nil {
                    DocumentPropertyRow(title: "Until", systemImage: "calendar") {
                        DatePicker("End repeat", selection: endRepeatDateBinding, in: Date()..., displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier("document.repeat.enddate")
                    }
                }
                Button(parsedRepeat.until == nil ? "Add end date" : "Remove end date") { endRepeatBinding.wrappedValue.toggle() }
                    .font(.caption).frame(minHeight: 44).accessibilityIdentifier("document.repeat.end")
            }
        case .earlyReminder:
            DocumentPropertyRow(title: "Early reminder", systemImage: field.icon) {
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button(preset.displayName) {
                            if preset == .custom { showEarlyCustom = true } else { setEarlyReminder(preset.value) }
                        }
                        .accessibilityIdentifier("document.earlyreminder.\(preset.rawValue.lowercased())")
                    }
                } label: { Text(draft.reminder?.enabled == true ? currentEarlyDisplay : "Enable a reminder first") }
                .disabled(draft.reminder?.enabled != true)
                .accessibilityIdentifier("document.earlyreminder")
            }
        case .allDay:
            DocumentPropertyToggle(title: "All day", systemImage: field.icon, isOn: allDayBinding, identifier: "document.allday")
        case .completable:
            DocumentPropertyToggle(title: "Completable", systemImage: field.icon, isOn: completableBinding, identifier: "document.completable")
        case .timeZone:
            DocumentPropertyRow(title: "Time zone", systemImage: field.icon) {
                Button(hasTime ? TimeZoneLabel.display(for: draft.dueTimeZone) : "Set a time first") { showTimeZonePicker = true }
                    .disabled(!hasTime)
                    .accessibilityIdentifier("document.timezone")
            }
        case .history:
            DocumentPropertyRow(title: "History", systemImage: field.icon) {
                NavigationLink("Completion history") { RecurrenceHistoryView(itemId: draft.id, store: store) }
                    .accessibilityIdentifier("document.recurrence.history")
            }
        case .source:
            DocumentPropertyRow(title: "Source", systemImage: field.icon) {
                NavigationLink("Apple Calendar") { CalendarSourceView(store: store, itemID: draft.id) }
                    .accessibilityIdentifier("item.calendar.source")
            }
        }
    }

    private var organizationMenu: some View {
        Menu {
            Menu("Type", systemImage: "square.stack") {
                ForEach(Item.ItemType.compactMenuOrder, id: \.self) { type in
                    Button(type.documentDisplayName) { setType(type) }
                        .accessibilityIdentifier("document.type.\(type.rawValue)")
                }
            }.accessibilityIdentifier("document.type")
            Menu("List", systemImage: "tray") {
                ForEach(activeLists, id: \.id) { list in
                    Button(list.name) {
                        if draft.listId != list.id { draft.listId = list.id; draft.section = nil; applyNow() }
                    }.accessibilityIdentifier("document.list.\(list.id.lowercased())")
                }
            }.accessibilityIdentifier("document.list")
            Button("Section", systemImage: "square.dashed") { showSectionPicker = true }
                .accessibilityIdentifier("document.section")
            if showsHierarchyMoveControl {
                Button("Move / Parent", systemImage: "list.bullet.indent") { beginMoveFromDetails(currentDraftItem) }
                    .accessibilityIdentifier("document.parent")
            }
            if showsRecurrenceHistory {
                NavigationLink("Completion history") { RecurrenceHistoryView(itemId: draft.id, store: store) }
                    .accessibilityIdentifier("document.recurrence.history")
            }
            if draft.calendarImport != nil {
                NavigationLink("Calendar source") { CalendarSourceView(store: store, itemID: draft.id) }
                    .accessibilityIdentifier("item.calendar.source")
            }
        } label: {
            Label("Organization", systemImage: "tray")
        }
        .accessibilityIdentifier("document.organization")
    }

    private var navigatorSheet: some View {
        DocumentNavigatorSheet(
            currentItemId: draft.id,
            title: draft.title.isEmpty ? "Untitled" : draft.title,
            bodyText: draft.body,
            items: store.items,
            lists: store.lists,
            documentFileNames: store.documentFileNamesById,
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
                case .internalItem(let id, let heading):
                    if id != draft.id {
                        finalizeAndFlush()
                        path?.wrappedValue.append(BreadcrumbDestination(id: id, heading: heading))
                    }
                case .external(let url):
                    UIApplication.shared.open(url)
                case .unresolved:
                    break
                }
            },
            onOpenBacklink: { backlink in
                activeSheet = nil
                finalizeAndFlush()
                path?.wrappedValue.append(BreadcrumbDestination(id: backlink.sourceItemId))
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
            currentItemId: draft.id,
            items: store.items,
            onBrowseDocuments: onBeginDocumentLink == nil ? nil : {
                guard let selection = pendingLinkSelection else { return }
                activeSheet = nil
                linkSelectionToRestore = nil
                pendingLinkSelection = nil
                DispatchQueue.main.async {
                    onBeginDocumentLink?(DocumentLinkSource(itemId: draft.id, title: draft.title, selection: selection))
                }
            },
            onCancel: {
                pendingLinkSelection = nil
                activeSheet = nil
            },
            onDocument: { target, heading, selection in
                insertDocumentLink(target: target, heading: heading, selection: selection)
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
        guard let live = store.item(draft.id), live.deletedAt == nil else {
            pendingTextBaselines.removeAll()
            return
        }
        mergeLiveRecurrenceLedgerIfNeeded(from: live)
        var candidate = draft
        candidate.modifiedAt = live.modifiedAt
        guard candidate != live else {
            pendingTextBaselines.removeAll()
            return
        }
        guard store.applyUpdateWithSubtreeCascadesSync(draft) else {
            // This helper also flushes text before opening property pickers.
            // A rejected text-only flush must not imply a property was edited.
            var properties = candidate
            properties.title = live.title
            properties.body = live.body
            guard properties != live else { return }
            // Rejected metadata must not look saved. Restore live properties,
            // preserving editor text and its existing pending-field ownership.
            var restored = live
            restored.title = draft.title
            restored.body = draft.body
            draft = restored
            propertyUpdateRejected = true
            return
        }
        pendingTextBaselines.removeAll()
        if let updated = store.item(draft.id) {
            draft.modifiedAt = updated.modifiedAt
        }
    }

    private func editText(_ value: String, field: PendingTextField) {
        let previous = field == .title ? draft.title : draft.body
        guard value != previous else { return }
        if pendingTextBaselines[field] == nil { pendingTextBaselines[field] = previous }
        if field == .title { draft.title = value } else { draft.body = value }
        if value == pendingTextBaselines[field] { pendingTextBaselines.removeValue(forKey: field) }
        scheduleApply()
    }

    /// Debounce only local text intent. Other fields are read live at commit.
    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = nil
        guard !pendingTextBaselines.isEmpty else { return }
        if let live = store.item(draft.id), live.deletedAt == nil {
            mergeLiveRecurrenceLedgerIfNeeded(from: live)
        }
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            applyTask = nil
            promotePendingTextDraft()
        }
    }

    private func promotePendingTextDraft() {
        guard !pendingTextBaselines.isEmpty else { return }
        let title: String? = pendingTextBaselines[.title] != nil ? draft.title : nil
        let body: String? = pendingTextBaselines[.body] != nil ? draft.body : nil
        applyTask?.cancel()
        applyTask = nil
        guard var latest = store.item(draft.id), latest.deletedAt == nil else {
            pendingTextBaselines.removeAll()
            return
        }
        if let title { latest.title = title }
        if let body { latest.body = body }
        // A deletion conflict can reject this attempt. Keep local intent until
        // accepted/deferred, so a failed deletion followed by close can retry.
        guard store.applyDocumentTextSync(draft.id, title: title, body: body) else { return }
        pendingTextBaselines.removeAll()
        draft = latest
        if let live = store.item(draft.id) { draft.modifiedAt = live.modifiedAt }
    }

    /// Explicit property operations already apply immediately. Closing owns
    /// only still-pending text, so stale pages cannot replay unrelated fields.
    private func finalizeAndFlush() {
        promotePendingTextDraft()
    }

    /// Completion History mutates live store state while the document page
    /// keeps its own editing draft. Pull the ledger back into that draft before
    /// any unrelated page edit can persist a stale copy over the correction.
    private func mergeLiveRecurrenceLedgerIfNeeded(from live: Item) {
        guard draft.recurrenceOccurrences != live.recurrenceOccurrences else { return }
        draft.recurrenceOccurrences = live.recurrenceOccurrences
        draft.done = live.done
        draft.completedAt = live.completedAt
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
            set: { editText($0, field: .title) }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { draft.body },
            set: { editText($0, field: .body) }
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
                    } else {
                        draft.due = nil
                        draft.dueAllDay = false
                        draft.end = nil
                        draft.reminder = nil
                        draft.triggers = nil
                        draft.recurrence = nil
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
                    } else {
                        draft.dueAllDay = draft.due != nil
                        draft.triggers = nil
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

    private var showsRecurrenceHistory: Bool {
        guard draft.recurrence != nil, draft.due != nil else { return false }
        return draft.type == .task || (draft.type == .event && draft.completable)
    }

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

    private var typeDisplayName: String { Self.displayName(for: draft.type) }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == draft.listId }
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
    let currentItemId: UUID
    let items: [Item]
    let onBrowseDocuments: (() -> Void)?
    let onCancel: () -> Void
    let onDocument: (Item, DocumentOutlineEntry?, DocumentLinkEditorSelection) -> Void
    let onURL: (String, URL, DocumentLinkEditorSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsURLFields = false
    @State private var showsDocuments = false
    @State private var selectedDocument: Item?
    @State private var searchText = ""
    @State private var label: String
    @State private var urlText = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case label
        case url
    }

    init(selection: DocumentLinkEditorSelection,
         currentItemId: UUID,
         items: [Item],
         onBrowseDocuments: (() -> Void)? = nil,
         onCancel: @escaping () -> Void,
         onDocument: @escaping (Item, DocumentOutlineEntry?, DocumentLinkEditorSelection) -> Void,
         onURL: @escaping (String, URL, DocumentLinkEditorSelection) -> Void) {
        self.selection = selection
        self.currentItemId = currentItemId
        self.items = items
        self.onBrowseDocuments = onBrowseDocuments
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
                } else if let selectedDocument {
                    headingRows(for: selectedDocument)
                } else if showsDocuments {
                    documentRows
                } else {
                    choiceRows
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .background(ListsTokens.Background.base)
            .navigationTitle(navigationTitle)
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
        .presentationDetents(showsURLFields ? [.medium] : (showsDocuments || selectedDocument != nil ? [.large] : [.height(260)]))
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
                if let onBrowseDocuments { dismiss(); onBrowseDocuments() }
                else { withAnimation(.smooth(duration: 0.18)) { showsDocuments = true } }
            } label: {
                linkChoiceRow(title: "Internal Link",
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
                linkChoiceRow(title: "External Link",
                              subtitle: "Insert a web or email link",
                              systemImage: "link")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.linkPicker.url")
        }
    }

    private var navigationTitle: String {
        if showsURLFields { return "Add URL" }
        if selectedDocument != nil { return "Choose Heading" }
        if showsDocuments { return "Choose Document" }
        return "Add Link"
    }

    private var availableDocuments: [Item] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items
            .filter { item in
                item.deletedAt == nil
                    && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
            }
            .sorted {
                let lhs = $0.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
                let rhs = $1.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private var documentRows: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                TextField("Search documents", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("document.linkPicker.document.search")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color(.secondarySystemFill), in: Capsule())

            if availableDocuments.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(availableDocuments) { item in
                            Button {
                                withAnimation(.smooth(duration: 0.18)) {
                                    selectedDocument = item
                                }
                            } label: {
                                linkChoiceRow(
                                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
                                    subtitle: item.type.documentDisplayName,
                                    systemImage: "doc.text"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("document.linkPicker.document.\(item.id.uuidString)")
                        }
                    }
                }
            }
        }
    }

    private func headingRows(for item: Item) -> some View {
        let headings = DocumentMarkdownIndex.outline(title: item.title, body: item.body)
            .filter { if case .body = $0.target { return true }; return false }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.18)) { selectedDocument = nil }
                } label: {
                    Label("Back to documents", systemImage: "chevron.backward")
                        .font(ListsTypography.caption1.weight(.semibold))
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                    onDocument(item, nil, selection)
                } label: {
                    linkChoiceRow(
                        title: "Whole Document",
                        subtitle: item.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
                        systemImage: "doc.text"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("document.linkPicker.heading.wholeDocument")

                if headings.isEmpty == false {
                    Text("HEADINGS")
                        .font(ListsTypography.caption1.weight(.semibold))
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .padding(.top, 8)

                    ForEach(headings) { heading in
                        Button {
                            dismiss()
                            onDocument(item, heading, selection)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "number")
                                    .foregroundStyle(ListsTokens.accent)
                                    .frame(width: 24)
                                Text(heading.title)
                                    .font(ListsTypography.body)
                                    .foregroundStyle(ListsTokens.Foreground.primary)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.footnote)
                                    .foregroundStyle(ListsTokens.Foreground.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("document.linkPicker.heading.\(heading.id)")
                    }
                }
            }
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
