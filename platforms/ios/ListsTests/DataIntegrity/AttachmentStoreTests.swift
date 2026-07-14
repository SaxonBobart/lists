import Foundation
import PaperKit
import PencilKit
import Testing
@testable import Lists

struct AttachmentStoreTests {
    @Test func importsResolveOnlyInsideAttachmentRootAndExportWithLibrary() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let payload = Data("image-payload".utf8)

        let attachment = try await store.importAttachment(
            data: payload,
            originalFileName: "Holiday Photo.PNG"
        )

        #expect(attachment.relativePath.hasPrefix("Attachments/"))
        #expect(attachment.relativePath.hasSuffix(".png"))
        #expect(attachment.byteCount == payload.count)
        let resolved = try await store.attachmentURL(for: attachment.relativePath)
        #expect(try Data(contentsOf: resolved) == payload)

        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: "Attachments/../secret.txt")
        }
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: "/tmp/secret.txt")
        }

        let archive = try LibraryExporter.exportLibrary(at: root)
        let archiveBytes = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
        #expect(archiveBytes.contains("Lists/\(attachment.relativePath)"))
        #expect(archiveBytes.contains("image-payload"))
    }

    @Test func markdownReferencesProtectFilesAndQuarantineIsRecoverable() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let kept = try await store.importAttachment(
            data: Data("kept".utf8),
            originalFileName: "kept.jpg"
        )
        let orphan = try await store.importAttachment(
            data: Data("orphan".utf8),
            originalFileName: "orphan.pdf"
        )
        let markdown = "Photo ![Alt](\(kept.relativePath)) and [file](\(kept.relativePath))"
        let references = MarkdownAttachmentIndex.referencedPaths(in: markdown)
        #expect(references == [kept.relativePath])

        let quarantined = try await store.quarantineUnreferencedAttachments(
            referencedPaths: references
        )
        #expect(quarantined == [orphan.relativePath])
        _ = try await store.attachmentURL(for: kept.relativePath)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: orphan.relativePath)
        }

        let restored = try await store.restoreQuarantinedAttachment(fileName: orphan.fileName)
        #expect(restored.relativePath == orphan.relativePath)
        let restoredURL = try await store.attachmentURL(for: orphan.relativePath)
        #expect(try Data(contentsOf: restoredURL) == Data("orphan".utf8))
    }

    @Test func drawingSourceAndPreviewShareIdentityAndStayProtectedTogether() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let drawing = try await store.importDrawing(
            sourceData: Data("editable-pencil-data".utf8),
            previewPNGData: Data("png-preview".utf8)
        )

        let sourceStem = (drawing.source.fileName as NSString).deletingPathExtension
        let previewStem = (drawing.preview.fileName as NSString).deletingPathExtension
        #expect(sourceStem == previewStem)
        #expect(drawing.source.relativePath.hasSuffix(".drawing"))
        #expect(drawing.preview.relativePath.hasSuffix(".png"))

        let references = MarkdownAttachmentIndex.referencedPaths(
            in: "![Drawing](\(drawing.preview.relativePath))"
        )
        #expect(references.contains(drawing.preview.relativePath))
        #expect(references.contains(drawing.source.relativePath))
        let quarantined = try await store.quarantineUnreferencedAttachments(
            referencedPaths: references
        )
        #expect(quarantined.isEmpty)
    }

    @Test func existingDrawingCanBeReplacedWithoutChangingItsMarkdownIdentity() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let drawing = try await store.importDrawing(
            sourceData: Data("first-drawing".utf8),
            previewPNGData: Data("first-preview".utf8)
        )

        let replacement = try await store.replaceDrawing(
            sourceRelativePath: drawing.source.relativePath,
            previewRelativePath: drawing.preview.relativePath,
            sourceData: Data("edited-drawing".utf8),
            previewPNGData: Data("edited-preview".utf8)
        )

        #expect(replacement.source.relativePath == drawing.source.relativePath)
        #expect(replacement.preview.relativePath == drawing.preview.relativePath)
        let sourceURL = try await store.attachmentURL(for: drawing.source.relativePath)
        let previewURL = try await store.attachmentURL(for: drawing.preview.relativePath)
        #expect(try Data(contentsOf: sourceURL) == Data("edited-drawing".utf8))
        #expect(try Data(contentsOf: previewURL) == Data("edited-preview".utf8))
    }

    @Test func nativePaperDocumentRoundTripsStructuredContentAndPaperStyle() async throws {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        markup.insertNewTextbox(
            attributedText: AttributedString("Editable text"),
            frame: CGRect(x: 40, y: 60, width: 240, height: 80)
        )
        let original = CanvasPaperDocument(markup: markup, paperStyle: .grid)

        let encoded = try await original.dataRepresentation()
        let restored = try CanvasPaperDocument(dataRepresentation: encoded)
        let indexedContent = await restored.markup.indexableContent
        let preview = try await restored.previewImage(darkMode: true)

        #expect(restored.paperStyle == .grid)
        #expect(restored.hasContent)
        #expect(restored.markup.bounds == original.markup.bounds)
        #expect(indexedContent?.contains("Editable text") == true)
        #expect(preview.size.width > 0)
        #expect(preview.pngData()?.isEmpty == false)
    }

    @Test func rawPencilKitDataImportsWithoutFlattening() async throws {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 24, y: 32),
                timeOffset: 0,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 180, y: 140),
                timeOffset: 0.2,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: path,
            transform: .identity,
            mask: nil
        )
        let pencilDrawing = PKDrawing(strokes: [stroke])
        let pencilData = pencilDrawing.dataRepresentation()

        let imported = try CanvasPaperDocument(dataRepresentation: pencilData)
        let encoded = try await imported.dataRepresentation()
        let reopened = try CanvasPaperDocument(dataRepresentation: encoded)

        #expect(imported.paperStyle == .plain)
        #expect(reopened.paperStyle == .plain)
        #expect(imported.hasContent)
        #expect(reopened.hasContent)
        #expect(reopened.markup.bounds == imported.markup.bounds)
        #expect(imported.markup.contentsRenderFrame.contains(pencilDrawing.bounds))
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsAttachments-\(UUID().uuidString)", isDirectory: true)
    }
}
