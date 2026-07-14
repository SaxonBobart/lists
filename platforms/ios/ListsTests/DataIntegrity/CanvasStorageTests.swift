import Foundation
import Testing
@testable import Lists

struct CanvasStorageTests {
    @Test func fractionalDevelopmentGeometryLoadsButReencodesAsIntegerPixels() throws {
        let legacy = Data("""
        {
          "nodes": [{
            "id": "legacy-link",
            "type": "link",
            "x": 44.22,
            "y": 335,
            "width": 313.56,
            "height": 88,
            "url": "https://apple.com"
          }],
          "edges": []
        }
        """.utf8)

        let document = try JSONDecoder().decode(CanvasDocument.self, from: legacy)
        #expect(document.nodes.first?.x == 44.22)
        #expect(document.nodes.first?.width == 313.56)

        let encoded = try JSONEncoder().encode(document)
        let source = try #require(String(data: encoded, encoding: .utf8))
        #expect(source.contains("\"x\":44"))
        #expect(source.contains("\"width\":314"))
    }

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
        let portablePreview = Data("drawing-only-png-data".utf8)
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
            portablePreviewPNGData: portablePreview,
            linkCards: [documentLink, webLink]
        )

        let document = try await store.readCanvasDocument(at: resource.canvasPath)
        let previewNode = try #require(document.nodes.first(where: {
            $0.id == "lists-native-canvas-preview"
        }))
        #expect(previewNode.type == .file)
        #expect(previewNode.file == "Ideas.drawing.png")
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
        #expect(try await store.readCanvasPortablePreviewData(at: resource.canvasPath) == portablePreview)
    }

    @MainActor
    @Test func renamingCanvasMovesBundleAndRewritesInboundMarkdownLink() async throws {
        let root = freshRoot()
        let itemStore = ItemStore(store: FileStore(root: root))
        try await itemStore.bootstrap()

        let canvas = try await itemStore.createCanvas(
            title: "Untitled Canvas",
            listId: ItemList.inboxId
        )
        let oldPath = try #require(canvas.canvasPath)
        var source = Item(type: .note, title: "Source", listId: ItemList.inboxId)
        source.body = "[Open canvas](../\(oldPath))"
        try await itemStore.add(source)

        let saved = try await itemStore.saveCanvasItem(
            canvas.id,
            title: "Project Plan",
            nativeData: try await CanvasPaperDocument.blank().dataRepresentation(),
            previewPNGData: Data("png-data".utf8)
        )

        #expect(saved.title == "Project Plan")
        #expect(saved.canvasPath == "Canvases/Project Plan.canvas")
        #expect(itemStore.item(source.id)?.body == "[Open canvas](../Canvases/Project%20Plan.canvas)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(oldPath).path) == false)

        let newPath = try #require(saved.canvasPath)
        let document = try await itemStore.canvasDocument(at: newPath)
        #expect(document.nodes.first(where: {
            $0.id == "lists-native-canvas-preview"
        })?.file == "Project Plan.drawing.png")
        #expect(try await itemStore.nativeCanvasData(at: newPath).isEmpty == false)
        #expect(try await itemStore.canvasPreviewURL(at: newPath) != nil)
    }

    @MainActor
    @Test func renamingDocumentRewritesCanvasCardAndPortableNode() async throws {
        let root = freshRoot()
        let itemStore = ItemStore(store: FileStore(root: root))
        try await itemStore.bootstrap()

        var target = Item(type: .note, title: "Project Notes", listId: ItemList.inboxId)
        try await itemStore.add(target)
        let canvas = try await itemStore.createCanvas(
            title: "Map",
            listId: ItemList.inboxId
        )
        let card = CanvasLinkCard(
            title: "Project Notes — Decisions",
            destination: DocumentMarkdownIndex.portableVaultDestination(
                to: target,
                heading: "Decisions",
                lists: itemStore.lists,
                documentFileNames: itemStore.documentFileNamesById
            ),
            x: 320,
            y: 240
        )
        var nativeDocument = CanvasPaperDocument.blank()
        nativeDocument.linkCards = [card]
        let savedCanvas = try await itemStore.saveCanvasItem(
            canvas.id,
            title: "Map",
            nativeData: try await nativeDocument.dataRepresentation(),
            previewPNGData: Data("png-data".utf8),
            linkCards: [card]
        )

        target.title = "Renamed Notes"
        itemStore.applyUpdateWithSubtreeCascadesSync(target)
        try await itemStore.flushPendingWrites()

        let canvasPath = try #require(savedCanvas.canvasPath)
        let native = try await itemStore.nativeCanvasData(at: canvasPath)
        let reopened = try CanvasPaperDocument(dataRepresentation: native)
        #expect(reopened.linkCards.first?.destination == "/Inbox/Renamed%20Notes.md#Decisions")
        let portable = try await itemStore.canvasDocument(at: canvasPath)
        #expect(portable.nodes.first(where: {
            $0.id == "lists-link-\(card.id.uuidString.lowercased())"
        })?.file == "Inbox/Renamed Notes.md")
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

    @Test func nativeCanvasEnvelopeRetainsPaperAndSemanticCards() async throws {
        let link = CanvasLinkCard(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Project notes",
            destination: "/Projects/Notes.md#Decisions",
            color: "4",
            x: 320,
            y: 240,
            width: 420,
            height: 88
        )
        let text = CanvasTextCard(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            markdown: "## Decisions\n\nKeep the portable source.",
            color: "5",
            x: 640,
            y: 420,
            width: 360,
            height: 220
        )
        var document = CanvasPaperDocument.blank(paperStyle: .dotGrid)
        document.linkCards = [link]
        document.textCards = [text]
        document.edges = [CanvasEdge(
            id: "self-reference",
            fromNode: link.canvasNodeID,
            toNode: link.canvasNodeID
        )]

        let data = try await document.dataRepresentation()
        let reopened = try CanvasPaperDocument(dataRepresentation: data)

        #expect(reopened.paperStyle == .dotGrid)
        #expect(reopened.linkCards == [link])
        #expect(reopened.textCards == [text])
        #expect(reopened.edges == document.edges)
    }

    @Test func connectionGeometryMeetsCardBoundaries() {
        let source = CanvasLinkCard(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Source",
            destination: "https://example.com/source",
            x: 100,
            y: 100,
            width: 100,
            height: 50
        )
        let target = CanvasLinkCard(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Target",
            destination: "https://example.com/target",
            x: 300,
            y: 100,
            width: 100,
            height: 50
        )
        let automatic = CanvasEdge(
            id: "automatic",
            fromNode: source.canvasNodeID,
            toNode: target.canvasNodeID
        )
        let explicit = CanvasEdge(
            id: "explicit",
            fromNode: source.canvasNodeID,
            fromSide: .top,
            toNode: target.canvasNodeID,
            toSide: .bottom
        )

        let segments = CanvasConnectionGeometry.segments(
            cards: [source, target],
            edges: [automatic, explicit]
        )

        #expect(segments[0].start == CGPoint(x: 150, y: 100))
        #expect(segments[0].end == CGPoint(x: 250, y: 100))
        #expect(segments[1].start == CGPoint(x: 100, y: 75))
        #expect(segments[1].end == CGPoint(x: 300, y: 125))
    }

    @Test func canvasConnectionsUseAnySemanticCardFrame() {
        let edge = CanvasEdge(
            id: "mixed-cards",
            fromNode: "lists-text-source",
            toNode: "lists-link-target"
        )

        let segments = CanvasConnectionGeometry.segments(
            cardFramesByNodeID: [
                "lists-text-source": CGRect(x: 20, y: 20, width: 180, height: 120),
                "lists-link-target": CGRect(x: 300, y: 40, width: 160, height: 80),
            ],
            edges: [edge]
        )

        #expect(segments.count == 1)
        #expect(segments[0].start == CGPoint(x: 200, y: 80))
        #expect(segments[0].end == CGPoint(x: 300, y: 80))
    }

    @MainActor
    @Test func canvasPreviewCompositesSemanticCards() async throws {
        let blank = CanvasPaperDocument.blank()
        let blankPreview = try await blank.previewImage(darkMode: false).pngData()

        var composed = blank
        composed.linkCards = [CanvasLinkCard(
            title: "Project notes — Decisions",
            destination: "/Projects/Notes.md#Decisions",
            x: 512,
            y: 680
        )]
        composed.textCards = [CanvasTextCard(
            markdown: "## Project map\n\nPortable Markdown stays editable.",
            x: 512,
            y: 400
        )]
        let composedPreview = try await composed.previewImage(darkMode: false).pngData()
        let drawingOnlyPreview = try await composed.previewImage(
            darkMode: false,
            includingLinkCards: false
        ).pngData()

        #expect(blankPreview != nil)
        #expect(composedPreview != nil)
        #expect(composedPreview != blankPreview)
        #expect(drawingOnlyPreview == blankPreview)
    }

    @MainActor
    @Test func portableRecoveryRestoresFlattenedDrawingAndSemanticCards() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let resource = try await store.createCanvasResource(title: "Recovery")
        let source = CanvasPaperDocument.blank(paperStyle: .dotGrid)
        let native = try await source.dataRepresentation()
        let portablePreview = try #require(
            try await source.previewImage(darkMode: false).pngData()
        )
        let documentLink = CanvasLinkCard(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Project notes — Decisions",
            destination: "/Projects/Project%20Notes.md#Decisions",
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
        let text = CanvasTextCard(
            markdown: "# Plan\n\n- Keep Markdown\n- Keep drawing",
            x: 500,
            y: 680
        )

        try await store.writeCanvas(
            at: resource.canvasPath,
            nativeData: native,
            previewPNGData: portablePreview,
            portablePreviewPNGData: portablePreview,
            linkCards: [documentLink, webLink],
            textCards: [text]
        )
        try FileManager.default.removeItem(
            at: root.appendingPathComponent(resource.nativeMarkupPath)
        )

        let recovery = try await store.readCanvasPortableRecovery(at: resource.canvasPath)
        #expect(recovery.previewPNGData == portablePreview)
        #expect(recovery.linkCards == [documentLink, webLink])
        #expect(recovery.textCards == [text])

        let recovered = try CanvasPaperDocument.recovering(recovery)
        #expect(recovered.linkCards == [documentLink, webLink])
        #expect(recovered.textCards == [text])
        #expect(recovered.hasContent)
    }

    @MainActor
    @Test func portableRecoveryAdoptsExternalCardsWithoutDuplicatingNodes() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let resource = try await store.createCanvasResource(title: "Imported")
        let source = CanvasPaperDocument.blank()
        let native = try await source.dataRepresentation()
        let preview = try #require(try await source.previewImage(darkMode: false).pngData())
        try await store.writeCanvas(
            at: resource.canvasPath,
            nativeData: native,
            previewPNGData: preview,
            portablePreviewPNGData: preview
        )

        var external = try await store.readCanvasDocument(at: resource.canvasPath)
        external.nodes.append(contentsOf: [
            CanvasNode(
                id: "obsidian-url",
                type: .link,
                x: 80,
                y: 120,
                width: 360,
                height: 88,
                color: "6",
                url: "https://apple.com"
            ),
            CanvasNode(
                id: "obsidian-file",
                type: .file,
                x: 520,
                y: 120,
                width: 360,
                height: 88,
                file: "Inbox/Project Notes.md",
                subpath: "#Decisions"
            ),
            CanvasNode(
                id: "obsidian-text",
                type: .text,
                x: 80,
                y: 320,
                width: 420,
                height: 240,
                color: "3",
                text: "## Imported Markdown\n\nThis stays editable."
            )
        ])
        external.edges = [CanvasEdge(
            id: "obsidian-edge",
            fromNode: "obsidian-url",
            toNode: "obsidian-file"
        )]
        try JSONEncoder().encode(external).write(
            to: root.appendingPathComponent(resource.canvasPath),
            options: .atomic
        )

        let recovery = try await store.readCanvasPortableRecovery(at: resource.canvasPath)
        #expect(recovery.linkCards.map(\.portableNodeID) == [
            "obsidian-url",
            "obsidian-file"
        ])
        #expect(recovery.linkCards.first?.color == "6")
        #expect(recovery.linkCards.map(\.destination) == [
            "https://apple.com",
            "/Inbox/Project%20Notes.md#Decisions"
        ])
        #expect(recovery.edges == external.edges)
        #expect(recovery.textCards.count == 1)
        #expect(recovery.textCards[0].portableNodeID == "obsidian-text")
        #expect(recovery.textCards[0].markdown == "## Imported Markdown\n\nThis stays editable.")
        #expect(recovery.textCards[0].color == "3")
        #expect(try await store.readCanvasLinkCards(at: resource.canvasPath) == recovery.linkCards)
        #expect(try await store.readCanvasTextCards(at: resource.canvasPath) == recovery.textCards)

        try await store.writeCanvas(
            at: resource.canvasPath,
            nativeData: native,
            previewPNGData: preview,
            portablePreviewPNGData: preview,
            linkCards: recovery.linkCards,
            textCards: recovery.textCards,
            edges: recovery.edges
        )
        var rewritten = try await store.readCanvasDocument(at: resource.canvasPath)
        #expect(rewritten.nodes.count(where: { $0.id == "obsidian-url" }) == 1)
        #expect(rewritten.nodes.count(where: { $0.id == "obsidian-file" }) == 1)
        #expect(rewritten.nodes.count(where: { $0.id == "obsidian-text" }) == 1)
        #expect(rewritten.nodes.first(where: { $0.id == "obsidian-url" })?.color == "6")
        #expect(rewritten.edges.map(\.id) == ["obsidian-edge"])

        try await store.writeCanvas(
            at: resource.canvasPath,
            nativeData: native,
            previewPNGData: preview,
            portablePreviewPNGData: preview,
            linkCards: Array(recovery.linkCards.dropLast()),
            textCards: recovery.textCards,
            edges: recovery.edges
        )
        rewritten = try await store.readCanvasDocument(at: resource.canvasPath)
        #expect(rewritten.nodes.contains(where: { $0.id == "obsidian-file" }) == false)
        #expect(rewritten.nodes.contains(where: { $0.id == "obsidian-text" }))
        #expect(rewritten.edges.isEmpty)
    }

    @MainActor
    @Test func deletingNewCanvasRemovesItemAndEveryResourceSidecar() async throws {
        let root = freshRoot()
        let itemStore = ItemStore(store: FileStore(root: root))
        try await itemStore.bootstrap()

        let canvas = try await itemStore.createCanvas(
            title: "Temporary Canvas",
            listId: ItemList.inboxId
        )
        let canvasPath = try #require(canvas.canvasPath)
        let canvasURL = root.appendingPathComponent(canvasPath)
        let paperURL = canvasURL.deletingPathExtension().appendingPathExtension("paper")
        let previewURL = canvasURL.deletingPathExtension().appendingPathExtension("png")
        let portablePreviewURL = canvasURL
            .deletingPathExtension()
            .appendingPathExtension("drawing")
            .appendingPathExtension("png")

        try await itemStore.saveCanvas(
            at: canvasPath,
            nativeData: Data("native-canvas".utf8),
            previewPNGData: Data("canvas-preview".utf8)
        )

        #expect(FileManager.default.fileExists(atPath: canvasURL.path))
        #expect(FileManager.default.fileExists(atPath: paperURL.path))
        #expect(FileManager.default.fileExists(atPath: previewURL.path))
        #expect(FileManager.default.fileExists(atPath: portablePreviewURL.path))

        try await itemStore.delete(canvas.id)

        #expect(itemStore.item(canvas.id) == nil)
        #expect(FileManager.default.fileExists(atPath: canvasURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: paperURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: previewURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: portablePreviewURL.path) == false)
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsCanvas-\(UUID().uuidString)", isDirectory: true)
    }
}
