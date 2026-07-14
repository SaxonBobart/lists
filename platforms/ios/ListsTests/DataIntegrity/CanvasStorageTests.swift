import Foundation
import Testing
@testable import Lists

struct CanvasStorageTests {
    @Test func createsReadableJSONCanvasWithHumanFileName() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)

        let first = try await store.createCanvasResource(title: "Project/Plan")
        let second = try await store.createCanvasResource(title: "Project/Plan")

        #expect(first.canvasPath == "Canvases/Project-Plan.canvas")
        #expect(second.canvasPath == "Canvases/Project-Plan (2).canvas")
        #expect(try await store.readCanvasDocument(at: first.canvasPath) == CanvasDocument())
    }

    @Test func nativeSaveKeepsPortablePreviewNodeAndSidecarsTogether() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let resource = try await store.createCanvasResource(title: "Ideas")
        let native = Data("paperkit-data".utf8)
        let preview = Data("png-data".utf8)
        let documentLink = CanvasLinkCard(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Project notes",
            destination: "/Projects/Notes.md#Decisions",
            x: 300,
            y: 180
        )
        let webLink = CanvasLinkCard(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Apple",
            destination: "https://apple.com",
            x: 600,
            y: 420
        )

        try await store.writeCanvas(
            at: resource.canvasPath,
            nativeData: native,
            previewPNGData: preview,
            linkCards: [documentLink, webLink]
        )

        let document = try await store.readCanvasDocument(at: resource.canvasPath)
        let previewNode = try #require(document.nodes.first(where: {
            $0.id == "lists-native-canvas-preview"
        }))
        #expect(previewNode.type == .file)
        #expect(previewNode.file == "Ideas.png")
        let documentNode = try #require(document.nodes.first(where: {
            $0.id == "lists-link-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        }))
        #expect(documentNode.type == .file)
        #expect(documentNode.file == "Projects/Notes.md")
        #expect(documentNode.subpath == "#Decisions")
        #expect(documentNode.label == "Project notes")
        #expect(documentNode.x == 120)
        let webNode = try #require(document.nodes.first(where: {
            $0.id == "lists-link-11111111-2222-3333-4444-555555555555"
        }))
        #expect(webNode.type == .link)
        #expect(webNode.url == "https://apple.com")
        #expect(webNode.label == "Apple")
        #expect(try await store.readNativeCanvasData(at: resource.canvasPath) == native)
        let previewURL = try #require(try await store.canvasPreviewURL(at: resource.canvasPath))
        #expect(try Data(contentsOf: previewURL) == preview)
    }

    @Test func canvasPathsCannotEscapeTheirLibraryDirectory() async throws {
        let store = FileStore(root: freshRoot())
        await #expect(throws: CanvasStorageError.self) {
            _ = try await store.readCanvasDocument(at: "Canvases/../secret.canvas")
        }
        await #expect(throws: CanvasStorageError.self) {
            _ = try await store.readCanvasDocument(at: "/tmp/secret.canvas")
        }
    }

    @Test func canvasItemFrontmatterAndPortableLinkRoundTrip() throws {
        let list = ItemList.makeInbox()
        let source = Item(type: .note, title: "Source", listId: list.id)
        let canvas = Item(
            type: .canvas,
            title: "Ideas",
            canvasPath: "Canvases/Ideas.canvas",
            listId: list.id
        )

        let encoded = try FrontmatterCodec.encode(canvas)
        let decoded = try FrontmatterCodec.decode(encoded)
        #expect(decoded.type == .canvas)
        #expect(decoded.canvasPath == canvas.canvasPath)

        let destination = DocumentMarkdownIndex.portableDestination(
            from: source,
            to: canvas,
            lists: [list]
        )
        #expect(destination == "../Canvases/Ideas.canvas")
        #expect(DocumentMarkdownIndex.resolveInternalDestination(
            destination,
            from: source,
            items: [source, canvas],
            lists: [list]
        )?.itemId == canvas.id)
        #expect(DocumentMarkdownIndex.portableVaultDestination(
            to: canvas,
            heading: "Sketches",
            lists: [list]
        ) == "/Canvases/Ideas.canvas#Sketches")
    }

    @Test func nativeCanvasEnvelopeRetainsPaperAndSemanticLinks() async throws {
        let link = CanvasLinkCard(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Project notes",
            destination: "/Projects/Notes.md#Decisions",
            x: 320,
            y: 240,
            width: 420,
            height: 88
        )
        var document = CanvasPaperDocument.blank(paperStyle: .dotGrid)
        document.linkCards = [link]

        let data = try await document.dataRepresentation()
        let reopened = try CanvasPaperDocument(dataRepresentation: data)

        #expect(reopened.paperStyle == .dotGrid)
        #expect(reopened.linkCards == [link])
    }

    @MainActor
    @Test func canvasPreviewCompositesSemanticLinkCards() async throws {
        let blank = CanvasPaperDocument.blank()
        let blankPreview = try await blank.previewImage(darkMode: false).pngData()

        var linked = blank
        linked.linkCards = [CanvasLinkCard(
            title: "Project notes — Decisions",
            destination: "/Projects/Notes.md#Decisions",
            x: 512,
            y: 680
        )]
        let linkedPreview = try await linked.previewImage(darkMode: false).pngData()

        #expect(blankPreview != nil)
        #expect(linkedPreview != nil)
        #expect(linkedPreview != blankPreview)
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsCanvas-\(UUID().uuidString)", isDirectory: true)
    }
}
