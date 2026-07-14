import SwiftUI
import UIKit

/// First-class Canvas editing surface. The Item owns shared Lists metadata;
/// PaperKit owns the native iOS authoring model; JSON Canvas owns the portable
/// document on disk.
struct CanvasItemView: View {
    let originalItem: Item
    let store: ItemStore

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var document: CanvasPaperDocument?
    @State private var failureMessage: String?
    @State private var isSaving = false
    @State private var showingLinkPicker = false
    @State private var toolPickerSuspended = false
    @State private var linkToInsert: CanvasLinkInsertion?
    @State private var linkPickerResult = CanvasLinkPickerResult()
    @State private var linkedItem: Item?

    init(item: Item, store: ItemStore) {
        originalItem = item
        self.store = store
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
                    suspendsToolPicker: toolPickerSuspended,
                    accessibilityPrefix: "canvas"
                ) { result in
                    guard let result else {
                        dismiss()
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
        .fullScreenCover(item: $linkedItem) { item in
            ItemDetailSheet(item: item, store: store)
        }
        .alert(
            "Couldn’t Save Canvas",
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
    }

    private func load() async {
        guard document == nil else { return }
        guard let canvasPath = originalItem.canvasPath else {
            failureMessage = CanvasStorageError.invalidPath.localizedDescription
            document = .blank()
            return
        }
        do {
            let data = try await store.nativeCanvasData(at: canvasPath)
            document = try CanvasPaperDocument(dataRepresentation: data)
        } catch CanvasStorageError.missingNativeDocument {
            document = .blank()
        } catch {
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
        guard isSaving == false, let canvasPath = originalItem.canvasPath else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let nativeData = try await document.dataRepresentation()
                let preview = try await document.previewImage(darkMode: colorScheme == .dark)
                guard let previewData = preview.pngData() else {
                    throw AttachmentStorageError.emptyData
                }
                try await store.saveCanvas(
                    at: canvasPath,
                    nativeData: nativeData,
                    previewPNGData: previewData,
                    linkCards: document.linkCards
                )

                var updated = store.item(originalItem.id) ?? originalItem
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.title = trimmed.isEmpty ? "Untitled Canvas" : trimmed
                try await store.update(updated)
                dismiss()
            } catch {
                failureMessage = error.localizedDescription
            }
        }
    }

    private func openLink(_ destination: String) {
        if let resolved = DocumentMarkdownIndex.resolveInternalDestination(
            destination,
            from: originalItem,
            items: store.items,
            lists: store.lists
        ), let item = store.item(resolved.itemId), item.deletedAt == nil {
            linkedItem = item
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
