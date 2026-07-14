import SwiftUI
import UIKit

/// First-class Canvas editing surface. The Item owns shared Lists metadata;
/// PaperKit owns the native iOS authoring model; JSON Canvas owns the portable
/// document on disk.
struct CanvasItemView: View {
    let originalItem: Item
    let store: ItemStore
    let onSave: ((Item) -> Void)?
    let onCancel: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var document: CanvasPaperDocument?
    @State private var failureTitle = "Couldn’t Save Canvas"
    @State private var failureMessage: String?
    @State private var isShowingRecoveryNotice = false
    @State private var isSaving = false
    @State private var showingLinkPicker = false
    @State private var toolPickerSuspended = false
    @State private var linkToInsert: CanvasLinkInsertion?
    @State private var linkPickerResult = CanvasLinkPickerResult()
    @State private var linkedDestination: BreadcrumbDestination?
    @State private var imageDataByPath: [String: Data] = [:]
    @State private var newlyImportedImagePaths: Set<String> = []

    init(
        item: Item,
        store: ItemStore,
        onSave: ((Item) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        originalItem = item
        self.store = store
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: item.title)
    }

    var body: some View {
        Group {
            if let document {
                PaperCanvasEditor(
                    document: document,
                    isEditing: true,
                    navigationTitle: "Canvas",
                    allowsEmptyDocument: true,
                    editableTitle: $title,
                    linkToInsert: $linkToInsert,
                    onRequestLink: {
                        toolPickerSuspended = true
                        showingLinkPicker = true
                    },
                    onOpenLink: openLink,
                    imageDataByPath: imageDataByPath,
                    onImportCanvasImage: { data in
                        let path = try await store.importCanvasImageAsset(
                            data,
                            itemID: originalItem.id
                        )
                        newlyImportedImagePaths.insert(path)
                        return path
                    },
                    suspendsToolPicker: toolPickerSuspended,
                    accessibilityPrefix: "canvas"
                ) { result in
                    guard let result else {
                        cancel()
                        return
                    }
                    save(result)
                }
                .overlay {
                    if isSaving {
                        ProgressView("Saving…")
                            .padding(20)
                            .background(.regularMaterial, in: .rect(cornerRadius: 14))
                            .accessibilityIdentifier("canvas.saving")
                    }
                }
            } else {
                ProgressView("Opening Canvas…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ListsTokens.Background.base)
                    .accessibilityIdentifier("canvas.loading")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingLinkPicker, onDismiss: finishLinkPickerDismissal) {
            DocumentLinkPickerSheet(
                selection: DocumentLinkEditorSelection(
                    range: NSRange(location: 0, length: 0),
                    selectedText: ""
                ),
                currentItemId: originalItem.id,
                items: store.items,
                onCancel: {},
                onDocument: { item, heading, _ in
                    let headingTitle = heading?.title
                    linkPickerResult.insertion = CanvasLinkInsertion(
                        title: headingTitle.map { "\(item.title) — \($0)" } ?? item.title,
                        destination: DocumentMarkdownIndex.portableVaultDestination(
                            to: item,
                            heading: headingTitle,
                            lists: store.lists
                        )
                    )
                },
                onURL: { text, url, _ in
                    linkPickerResult.insertion = CanvasLinkInsertion(
                        title: text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? url.host
                            ?? url.absoluteString,
                        destination: url.absoluteString
                    )
                }
            )
        }
        .fullScreenCover(item: $linkedDestination) { destination in
            if let item = store.item(destination.id), item.deletedAt == nil {
                ItemDetailSheet(
                    item: item,
                    store: store,
                    initialHeading: destination.heading
                )
            }
        }
        .alert(
            failureTitle,
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if $0 == false { failureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("canvas.error.dismiss")
        } message: {
            Text(failureMessage ?? "The canvas could not be saved.")
        }
        .alert("Canvas Recovered", isPresented: $isShowingRecoveryNotice) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("canvas.recovery.dismiss")
        } message: {
            Text("The editable drawing layer was unavailable. Lists restored the drawing as one image and kept its canvas cards and groups editable.")
        }
    }

    private func load() async {
        guard document == nil else { return }
        guard let canvasPath = originalItem.canvasPath else {
            failureTitle = "Couldn’t Open Canvas"
            failureMessage = CanvasStorageError.invalidPath.localizedDescription
            document = .blank()
            return
        }
        do {
            let data = try await store.nativeCanvasData(at: canvasPath)
            var nativeDocument = try CanvasPaperDocument(dataRepresentation: data)
            // JSON Canvas owns semantic graph objects. Refreshing them on every
            // open lets compatible editors add, move, or remove cards without
            // requiring Lists' platform-specific PaperKit sidecar.
            if let portableDocument = try? await store.canvasDocument(at: canvasPath) {
                nativeDocument.groups = try await store.canvasGroups(at: canvasPath)
                nativeDocument.imageCards = try await store.canvasImageCards(at: canvasPath)
                nativeDocument.linkCards = try await store.canvasLinkCards(at: canvasPath)
                nativeDocument.textCards = try await store.canvasTextCards(at: canvasPath)
                nativeDocument.edges = portableDocument.edges
            }
            imageDataByPath = await imageData(for: nativeDocument.imageCards)
            document = nativeDocument
        } catch CanvasStorageError.missingNativeDocument {
            do {
                let recovery = try await store.canvasPortableRecovery(at: canvasPath)
                let recovered = try CanvasPaperDocument.recovering(recovery)
                imageDataByPath = await imageData(for: recovered.imageCards)
                document = recovered
                isShowingRecoveryNotice = true
            } catch {
                failureTitle = "Couldn’t Open Canvas"
                failureMessage = error.localizedDescription
                document = .blank()
            }
        } catch {
            failureTitle = "Couldn’t Open Canvas"
            failureMessage = error.localizedDescription
            document = .blank()
        }
    }

    private func finishLinkPickerDismissal() {
        let insertion = linkPickerResult.takeInsertion()
        // Keep picker dismissal, PaperKit adornment insertion, and responder
        // restoration in separate render passes. PaperKit's tool palette owns
        // a responder presentation hierarchy of its own; changing all three
        // at once can create an AttributeGraph cycle.
        Task { @MainActor in
            await Task.yield()
            if let insertion {
                linkToInsert = insertion
                await Task.yield()
            }
            toolPickerSuspended = false
        }
    }

    private func save(_ document: CanvasPaperDocument) {
        guard isSaving == false, originalItem.canvasPath != nil else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let imageData = await imageData(for: document.imageCards)
                let nativeData = try await document.dataRepresentation()
                let preview = try await document.previewImage(
                    darkMode: colorScheme == .dark,
                    fileDataByPath: imageData
                )
                guard let previewData = preview.pngData() else {
                    throw AttachmentStorageError.emptyData
                }
                let portablePreviewData: Data
                if document.groups.isEmpty
                    && document.imageCards.isEmpty
                    && document.linkCards.isEmpty
                    && document.textCards.isEmpty {
                    portablePreviewData = previewData
                } else {
                    let portablePreview = try await document.previewImage(
                        darkMode: colorScheme == .dark,
                        includingLinkCards: false
                    )
                    guard let data = portablePreview.pngData() else {
                        throw AttachmentStorageError.emptyData
                    }
                    portablePreviewData = data
                }
                let updated = try await store.saveCanvasItem(
                    originalItem.id,
                    title: title,
                    nativeData: nativeData,
                    previewPNGData: previewData,
                    portablePreviewPNGData: portablePreviewData,
                    groups: document.groups,
                    imageCards: document.imageCards,
                    linkCards: document.linkCards,
                    textCards: document.textCards,
                    edges: document.edges
                )
                try? await store.pruneCanvasImageAssets(
                    itemID: originalItem.id,
                    keeping: Set(document.imageCards.map(\.file))
                )
                newlyImportedImagePaths.removeAll()
                onSave?(updated)
                dismiss()
            } catch {
                failureTitle = "Couldn’t Save Canvas"
                failureMessage = error.localizedDescription
            }
        }
    }

    private func imageData(for cards: [CanvasImageCard]) async -> [String: Data] {
        var result: [String: Data] = [:]
        for card in cards {
            if let data = try? await store.canvasFileData(at: card.file) {
                result[card.file] = data
            }
        }
        return result
    }

    private func cancel() {
        let paths = newlyImportedImagePaths
        newlyImportedImagePaths.removeAll()
        Task { @MainActor in
            for path in paths {
                try? await store.discardCanvasImageAsset(
                    at: path,
                    itemID: originalItem.id
                )
            }
            onCancel?()
            dismiss()
        }
    }

    private func openLink(_ destination: String) {
        if let resolved = DocumentMarkdownIndex.resolveInternalDestination(
            destination,
            from: originalItem,
            items: store.items,
            lists: store.lists
        ), let item = store.item(resolved.itemId), item.deletedAt == nil {
            linkedDestination = BreadcrumbDestination(
                id: item.id,
                heading: resolved.heading
            )
            return
        }
        guard let url = URL(string: destination),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }
}

/// A non-observable handoff box lets the picker record its result without
/// invalidating the Canvas view while the sheet is in the middle of dismissal.
@MainActor
private final class CanvasLinkPickerResult {
    var insertion: CanvasLinkInsertion?

    func takeInsertion() -> CanvasLinkInsertion? {
        defer { insertion = nil }
        return insertion
    }
}
