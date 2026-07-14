import Foundation
import Testing
@testable import Lists

struct MarkdownAssetPreviewTests {
    @Test func detectsLargeCanvasEmbed() throws {
        let source = "![[../Canvases/Project%20Map.canvas]]"

        let reference = try #require(MarkdownAssetPreview.reference(
            in: source,
            selection: NSRange(location: 4, length: 0)
        ))

        #expect(reference.kind == .canvas)
        #expect(reference.style == .large)
        #expect(reference.label == "Project Map")
        #expect(reference.destination == "../Canvases/Project%20Map.canvas")
    }

    @Test func detectsLargeImageEmbed() throws {
        let source = "![Diagram](Attachments/Diagram.png)"

        let reference = try #require(MarkdownAssetPreview.reference(
            in: source,
            selection: NSRange(location: 8, length: 0)
        ))

        #expect(reference.kind == .image)
        #expect(reference.style == .large)
        #expect(reference.label == "Diagram")
    }

    @Test func detectsCompactCanvasInsideProse() throws {
        let source = "Open [Project Map](../Canvases/Project%20Map.canvas) beside this sentence."

        let reference = try #require(MarkdownAssetPreview.reference(
            in: source,
            selection: NSRange(location: 10, length: 0)
        ))

        #expect(reference.kind == .canvas)
        #expect(reference.style == .compact)
        #expect(reference.label == "Project Map")
    }

    @Test func ordinaryDocumentLinkIsNotAnAssetPreview() {
        let source = "Read [Project notes](../Notes/Project.md)."

        #expect(MarkdownAssetPreview.reference(
            in: source,
            selection: NSRange(location: 10, length: 0)
        ) == nil)
    }

    @Test func externalCanvasURLRemainsAnOrdinaryWebLink() {
        let source = "Download [Example](https://example.com/example.canvas)."

        #expect(MarkdownAssetPreview.reference(
            in: source,
            selection: NSRange(location: 12, length: 0)
        ) == nil)
    }

    @Test func largeCanvasBecomesCompactWithoutChangingDestination() {
        let source = "![[../Canvases/Sketch.canvas]]"

        let result = MarkdownAssetPreview.setting(
            .compact,
            in: source,
            selection: NSRange(location: 4, length: 0)
        )

        #expect(result.source == "[Sketch](../Canvases/Sketch.canvas)")
        #expect(result.selection.location == (result.source as NSString).length)
    }

    @Test func compactCanvasBecomesAnOwnLineLargePreview() {
        let source = "Before [Sketch](../Canvases/Sketch.canvas) after"

        let result = MarkdownAssetPreview.setting(
            .large,
            in: source,
            selection: NSRange(location: 10, length: 0)
        )

        #expect(result.source == "Before\n![[../Canvases/Sketch.canvas]]\nafter")
        #expect(result.selection.location == ("Before\n![[../Canvases/Sketch.canvas]]" as NSString).length)
    }

    @Test func compactImageBecomesLargePortableMarkdown() {
        let source = "See [Diagram](Attachments/Diagram.png) now"

        let result = MarkdownAssetPreview.setting(
            .large,
            in: source,
            selection: NSRange(location: 7, length: 0)
        )

        #expect(result.source == "See\n![Diagram](Attachments/Diagram.png)\nnow")
    }
}
