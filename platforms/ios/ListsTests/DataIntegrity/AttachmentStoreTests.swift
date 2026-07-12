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

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsAttachments-\(UUID().uuidString)", isDirectory: true)
    }
}
