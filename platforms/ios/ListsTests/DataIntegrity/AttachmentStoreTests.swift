import Foundation
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

    @Test func escapedAttachmentLabelsUseTheSameIndexAsTheEditor() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(root: root)
        let attachment = try await store.importAttachment(data: Data("photo".utf8), originalFileName: "photo.png")
        let source = "Before 😀 ![Photo \\[version 2\\]](../../\(attachment.relativePath)) after"
        let references = MarkdownMediaReference.references(in: source)
        #expect(references.count == 1)
        #expect(references.first?.label == "Photo [version 2]")
        #expect(MarkdownAttachmentIndex.referencedPaths(in: source) == [attachment.relativePath])
        let quarantined = try await store.quarantineUnreferencedAttachments(
            referencedPaths: MarkdownAttachmentIndex.referencedPaths(in: source)
        )
        #expect(quarantined.isEmpty)
        _ = try await store.attachmentURL(for: attachment.relativePath)
    }

    @Test func attachmentDescriptionEscapesRoundTripWithoutAccumulatingBackslashes() throws {
        let label = #"Report [version 2] \ original"#
        let source = "[\(DocumentMarkdownLinkBuilder.escapedLabel(label))](Attachments/report.pdf)"
        let reference = try #require(MarkdownMediaReference.references(in: source).first)
        #expect(reference.label == label)
        #expect("[\(DocumentMarkdownLinkBuilder.escapedLabel(reference.label))](\(reference.path))" == source)
    }

    @Test func semanticAttachmentsUseTheSameEscapedLabelsAsLiveMarkdown() throws {
        let source = "![Photo \\[original\\]](../Attachments/photo.png)\n\n[PDF \\[original\\]](../Attachments/file.pdf)"
        let blocks = SemanticMarkdownBlockParser.blocks(from: source)
        #expect(blocks.count == 2)
        let image = try #require(blocks.first)
        guard case .image(let alt, let path) = image.kind else {
            Issue.record("Expected a semantic image for the escaped attachment label")
            return
        }
        #expect(alt == "Photo [original]")
        #expect(path == "../Attachments/photo.png")
        let file = try #require(blocks.last)
        guard case .linkCard(let label, let url) = file.kind else {
            Issue.record("Expected a semantic file card for the escaped attachment label")
            return
        }
        #expect(label == "PDF [original]")
        #expect(url.relativeString == "../Attachments/file.pdf")
    }

    @Test(arguments: [
        "~~~markdown\n[Example](https://example.com)\n~~~",
        "````markdown\n```\n[Example](https://example.com)\n````",
        "  ```markdown\n[Example](https://example.com)"
    ])
    func linksInCodeUseSharedFenceBoundaries(source: String) {
        #expect(MarkdownInlineLink.links(in: source).isEmpty)
        let withProse = source + "\n" + (source.hasSuffix("~~~") || source.hasSuffix("````") ? "Visit https://outside.example" : "")
        if withProse != source + "\n" {
            #expect(MarkdownInlineLink.links(in: withProse).map(\.destination) == ["https://outside.example"])
        }
    }

    @Test func selectedSymbolicLinksImportIndependentFileContents() async throws {
        let directory = freshRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("original.pdf")
        let link = directory.appendingPathComponent("selected.pdf")
        let bytes = Data("independent attachment".utf8)
        try bytes.write(to: source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let store = FileStore(root: directory.appendingPathComponent("Library"))
        let imported = try await store.importAttachment(fileURL: link)
        try FileManager.default.removeItem(at: source)
        let saved = try await store.attachmentURL(for: imported.relativePath)
        #expect(try Data(contentsOf: saved) == bytes)
        #expect(try saved.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
    }

    @Test func directoriesCannotBeImportedOrOpenedAsAttachments() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Attachments/folder.pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("contents".utf8).write(to: folder.appendingPathComponent("file.txt"))
        let store = FileStore(root: root)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.importAttachment(fileURL: folder)
        }
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: "Attachments/folder.pdf")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Attachments").path) == ["folder.pdf"])
    }

    @Test func quarantineCannotTraverseASymlinkedAttachmentDirectory() async throws {
        let directory = freshRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Library")
        let outside = directory.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let original = outside.appendingPathComponent("photo.png")
        try Data("untouched".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Attachments"), withDestinationURL: outside)
        let store = FileStore(root: root)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.quarantineUnreferencedAttachments(referencedPaths: [])
        }
        #expect(try Data(contentsOf: original) == Data("untouched".utf8))
    }

    @Test func attachmentRecoveryRejectsRedirectedTrashAndDestinationDirectories() async throws {
        for redirectedName in ["Attachments", ".attachments-trash"] {
            let directory = freshRoot()
            defer { try? FileManager.default.removeItem(at: directory) }
            let root = directory.appendingPathComponent("Library")
            let outside = directory.appendingPathComponent("Outside")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(redirectedName), withDestinationURL: outside)
            let trash = root.appendingPathComponent(".attachments-trash")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let original = trash.appendingPathComponent("photo.png")
            try Data("untouched".utf8).write(to: original)
            let store = FileStore(root: root)
            await #expect(throws: AttachmentStorageError.self) {
                _ = try await store.restoreQuarantinedAttachment(fileName: "photo.png")
            }
            #expect(try Data(contentsOf: original) == Data("untouched".utf8))
        }
    }

    @Test func attachmentRecoveryRejectsASymlinkedFile() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let trash = root.appendingPathComponent(".attachments-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.txt")
        try Data("untouched".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link.txt"), withDestinationURL: original)
        let store = FileStore(root: root)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.restoreQuarantinedAttachment(fileName: "link.txt")
        }
        #expect(try Data(contentsOf: original) == Data("untouched".utf8))
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsAttachments-\(UUID().uuidString)", isDirectory: true)
    }
}
