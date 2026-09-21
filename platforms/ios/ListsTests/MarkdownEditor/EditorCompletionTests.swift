import Foundation
import Testing
import UIKit
@testable import Lists

struct EditorCompletionTests {
    @Test func escapedEmphasisDelimitersStayLiteral() {
        for source in [#"\*literal\*"#, #"\**literal\**"#, #"\***literal\***"#] {
            #expect(MarkdownSyntax.inlineSpans(in: source).isEmpty)
        }
        #expect(MarkdownSyntax.inlineSpans(in: #"\\*italic*"#).contains { $0.kind == .italic })
    }

    @Test func codeSpansMatchCompleteBacktickRuns() {
        let source = "``a ` b **literal**``"
        let spans = MarkdownSyntax.inlineSpans(in: source)
        #expect(spans.count == 1)
        #expect(spans.first?.kind == .code)
        #expect(spans.first?.openRange.length == 2)
        #expect(spans.first?.closeRange.length == 2)
        #expect(spans.first?.contentRange == (source as NSString).range(of: "a ` b **literal**"))
    }

    @Test func proseAssistanceStaysDisabledInLongerCodeFences() {
        let source = "````\n```\nplain"
        #expect(!MarkdownProseAssistance.allowsAssistance(source: source, selection: NSRange(location: source.utf16.count, length: 0), raw: false))
        let after = source + "\n````\nprose"
        #expect(MarkdownProseAssistance.allowsAssistance(source: after, selection: NSRange(location: after.utf16.count, length: 0), raw: false))
    }

    @Test @MainActor func oversizedOrderedMarkersRemainPlainText() {
        for source in ["\(Int.max). item", "1000000000. item", "٠١. item"] {
            #expect(ListMarker.detect(in: source) == nil)
            let blocks = SemanticMarkdownBlockParser.blocks(from: source)
            for block in blocks {
                if case .ordered = block.kind { Issue.record("Invalid ordered marker rendered as a list") }
            }
            let ns = source as NSString
            #expect(MarkdownStyler.numberedListRegex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) == nil)
        }
        #expect(ListMarker.detect(in: "999999998. item")?.continuationPrefix == "999999999. ")
        #expect(ListMarker.detect(in: "999999999. item") != nil)
    }

    @Test func semanticCodePreservesCRLFLineStructure() {
        let blocks = SemanticMarkdownBlockParser.blocks(from: "```\r\nfirst\r\nsecond\r\n```")
        if case .codeBlock(let text) = blocks.first?.kind {
            #expect(text == "first\nsecond")
        } else { Issue.record("Expected code block") }
    }

    @Test func semanticFenceParsingKeepsNestedMarkersLiteral() {
        let source = "````markdown\n```mermaid\ngraph TD\n```\n````\nafter"
        let blocks = SemanticMarkdownBlockParser.blocks(from: source)
        #expect(blocks.count == 2)
        if case .codeBlock(let text) = blocks.first?.kind {
            #expect(text == "```mermaid\ngraph TD\n```")
        } else { Issue.record("Expected a literal code block") }
        #expect(MarkdownRenderedSource.spans(in: source).isEmpty)
    }

    @Test func tildeAndIndentedMermaidFencesRenderConsistently() {
        for marker in ["~~~", "   ````"] {
            let source = marker + "mermaid\ngraph TD\n" + marker
            let blocks = SemanticMarkdownBlockParser.blocks(from: source)
            if case .mermaid(let text) = blocks.first?.kind {
                #expect(text == "graph TD")
            } else { Issue.record("Expected a diagram block") }
            #expect(MarkdownRenderedSource.spans(in: source).map(\.source) == ["graph TD"])
        }
    }

    @Test func semanticParserRejectsMismatchedTableColumns() {
        let blocks = SemanticMarkdownBlockParser.blocks(from: "| A | B |\n| --- |\n")
        for block in blocks {
            if case .table = block.kind { Issue.record("Malformed table must stay literal") }
        }
    }

    @Test @MainActor func attachmentsRemainAtomicInLiveAndExposeSourceInRaw() {
        let source = "Before\n\n![Blue QA image](Attachments/photo.png)\n\nAfter"
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        let reference = MarkdownMediaReference.references(in: source)[0]
        for selection in [reference.range, NSRange(location: reference.range.location, length: 0), NSRange(location: NSMaxRange(reference.range), length: 0)] {
            storage.cursorRange = selection
            #expect(storage.mediaHeight(at: reference.range.location) != nil)
            #expect(storage.string == source)
        }
        storage.mode = .raw
        #expect(storage.mediaHeight(at: reference.range.location) == nil)
        for location in reference.range.location..<NSMaxRange(reference.range) {
            #expect(storage.glyphProperty(at: location) == nil)
        }
        #expect(storage.string == source)
    }

    @Test @MainActor func consecutiveAttachmentCardsDoNotCollapse() {
        let source = "[First](Attachments/a.m4a)\n\n[Second](Attachments/b.m4a)\n\n[PDF](Attachments/c.pdf)\n\n[Photo link](Attachments/photo.png)\n\n![Photo embed](Attachments/photo.png)\n\n[Video](Attachments/clip.mp4)"
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate(); delegate.styler = storage; layout.delegate = delegate
        let container = NSTextContainer(size: CGSize(width: 320, height: 2000))
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        storage.cursorRange = NSRange(location: NSNotFound, length: 0)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        layout.ensureLayout(for: container)
        let rectangles = MarkdownMediaReference.references(in: source).map {
            layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: $0.range.location), effectiveRange: nil)
        }
        for (rectangle, reference) in zip(rectangles, MarkdownMediaReference.references(in: source)) {
            #expect(rectangle.height >= (storage.mediaHeight(at: reference.range.location) ?? 0))
        }
        for (previous, next) in zip(rectangles, rectangles.dropFirst()) {
            #expect(next.minY >= previous.maxY)
            #expect(next.minY - previous.maxY < 60)
        }
        #expect(rectangles[3].height < rectangles[4].height)
        // TextKit includes surrounding paragraph spacing in fragment rectangles.
        // File kinds should all stay compact, without a reserved player/thumbnail.
        for index in [0, 1, 3, 5] {
            #expect(rectangles[index].height < 120)
        }
        #expect(storage.string == source)
    }
    @Test @MainActor func renderedBlocksKeepWritingLanesAndExcludeHiddenSourceFromHitTesting() throws {
        let source = "Before\n\n$$\nx^2\n$$\n\n```mermaid\ngraph TD\n A-->B\n```\n\nAfter"
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate(); delegate.styler = storage; layout.delegate = delegate
        let container = NSTextContainer(size: CGSize(width: 320, height: 2000))
        container.widthTracksTextView = false
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        storage.glyphInvalidatable = layout
        let view = MarkdownInternalTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 900), textContainer: container)
        MarkdownTypingStyle.apply(to: view)
        let spans = MarkdownRenderedSource.spans(in: source)
        for span in spans {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 90, height: span.kind == "diagram" ? 180 : 35)).image { _ in }
            storage.syntaxImages[span.kind + span.source] = MarkdownRenderedImage(image: image, kind: span.kind, source: span.source)
        }
        storage.cursorRange = NSRange(location: NSNotFound, length: 0)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        layout.ensureLayout(for: container)
        let blank = (source as NSString).range(of: "\n\n```mermaid").location + 1
        let position = try #require(view.position(from: view.beginningOfDocument, offset: blank))
        let caret = view.caretRect(for: position)
        #expect(caret.height >= UIFont.preferredFont(forTextStyle: .body).lineHeight)
        let diagram = try #require(spans.first { $0.kind == "diagram" })
        let rect = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: diagram.range.location), effectiveRange: nil)
        let right = try #require(view.closestPosition(to: CGPoint(x: 280, y: view.textContainerInset.top + rect.midY)))
        let location = view.offset(from: view.beginningOfDocument, to: right)
        #expect(location == diagram.range.location || location == NSMaxRange(diagram.range))
        #expect(caret.maxY <= rect.minY + view.textContainerInset.top + 4)
        #expect(storage.string == source)
    }

    @Test func fileImportsPreserveOriginalBytesAndProtectExistingFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("original.gif")
        let bytes = Data((0..<8192).map { UInt8($0 % 256) })
        try bytes.write(to: source)
        let root = directory.appendingPathComponent("Library")
        let store = FileStore(root: root)
        let attachment = try await store.importAttachment(fileURL: source, preferredFileName: "capture.gif")
        let saved = try await store.attachmentURL(for: "../../" + attachment.relativePath)
        #expect(try Data(contentsOf: saved) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.importAttachment(fileURL: source, preferredFileName: "capture.gif")
        }
        #expect(try Data(contentsOf: saved) == bytes)
    }

    @Test func movingDocumentsRebasesAttachmentsWithoutRewritingOnOpen() {
        let parent = ItemList(id: "parent", name: "Parent", icon: "folder", color: .blue, createdAt: .now, modifiedAt: .now, position: 0)
        let child = ItemList(id: "child", name: "Child", icon: "folder", color: .blue, createdAt: .now, modifiedAt: .now, position: 1, parentId: parent.id)
        let lists = [parent, child]
        let original = Item(type: .note, title: "Example", body: "![Photo](Attachments/a.png)\n[Sound](../Attachments/b.m4a)", listId: parent.id)
        #expect(DocumentMarkdownIndex.rewritingPortableDestinations(in: original, oldSource: original, oldItems: [original], oldLists: lists, newItems: [original], newLists: lists) == original.body)
        var moved = original; moved.listId = child.id
        let updated = DocumentMarkdownIndex.rewritingPortableDestinations(in: moved, oldSource: original, oldItems: [original], oldLists: lists, newItems: [moved], newLists: lists)
        #expect(updated == "![Photo](../../Attachments/a.png)\n[Sound](../../Attachments/b.m4a)")
    }
    @Test @MainActor func renderedBlocksReserveTheirFullHeight() throws {
        let source = "```mermaid\ngraph TD\n A-->B\n```\n\n![Photo](Attachments/a.png)"
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate()
        delegate.styler = storage; layout.delegate = delegate
        let container = NSTextContainer(size: CGSize(width: 320, height: 2000))
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        let span = try #require(MarkdownRenderedSource.spans(in: source).first)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 240))
        }
        storage.syntaxImages[span.kind + span.source] = MarkdownRenderedImage(image: image, kind: span.kind, source: span.source)
        storage.cursorRange = NSRange(location: NSNotFound, length: 0)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        layout.ensureLayout(for: container)
        let diagram = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let mediaLocation = (source as NSString).range(of: "![Photo]").location
        let media = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: mediaLocation), effectiveRange: nil)
        #expect(diagram.height >= 240)
        #expect(media.minY >= diagram.maxY)
        #expect(storage.string == source)
    }

    @Test @MainActor func tableCellEditsRemainUndoableAfterLeavingTheCell() {
        var source = "| Name |\n| --- |\n| Apple |"
        let original = source
        let coordinator = EditorCoordinator(text: .init(get: { source }, set: { source = $0 }))
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        layout.addTextContainer(NSTextContainer(size: CGSize(width: 320, height: 1000)))
        storage.addLayoutManager(layout)
        let view = UITextView(frame: .zero, textContainer: layout.textContainers[0])
        coordinator.textViewRef = view; view.delegate = coordinator
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        coordinator.applyExternalTableEdit((source.replacingOccurrences(of: "Apple", with: "Pear"), NSRange(location: 0, length: 0)), keepFirstResponder: UITextView())
        #expect(view.undoManager?.canUndo == true)
        view.undoManager?.undo()
        #expect(source == original)
        view.undoManager?.redo()
        #expect(source.contains("Pear"))
    }

    @Test func attachmentDirectorySymlinksCannotEscapeLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Attachments"), withDestinationURL: outside)
        #expect(MarkdownAttachmentIndex.fileURL("Attachments/photo.png", root: root) == nil)
    }
    @Test func attachmentDestinationsRemainConfined() {
        #expect(MarkdownAttachmentIndex.canonicalPath("../../Attachments/photo.png") == "Attachments/photo.png")
        #expect(MarkdownAttachmentIndex.canonicalPath("Attachments/../secret") == nil)
        #expect(MarkdownAttachmentIndex.canonicalPath("../Attachments/%2E%2E") == nil)
        #expect(MarkdownAttachmentIndex.canonicalPath("https://example.com/Attachments/a") == nil)
        #expect(MarkdownAttachmentIndex.canonicalPath("/Attachments/a") == nil)
    }
    @Test func attachmentsIndexIncludesRelativeImagesAndFiles() {
        let source = "![A](../../Attachments/a.png)\n[Recording](../Attachments/b.m4a)"
        #expect(MarkdownAttachmentIndex.referencedPaths(in: source) == ["Attachments/a.png", "Attachments/b.m4a"])
        #expect(MarkdownMediaReference.references(in: source).count == 2)
        #expect(MarkdownMediaReference.block(in: "Text [File](Attachments/a.pdf)") == nil)
    }
    @Test func replacementUsesOriginalUTF16Ranges() {
        #expect(DocumentReplacement.replaceAll("cat", with: "🐈 cat", in: "🐕 CAT cat") == "🐕 🐈 cat 🐈 cat")
        #expect(DocumentReplacement.replaceAll("", with: "x", in: "hello") == "hello")
    }
    @Test func proseAssistanceProtectsSyntax() {
        for source in ["Ordinary prose", "- Words in a list", "**Bold words"] {
            #expect(MarkdownProseAssistance.allowsAssistance(source: source, selection: NSRange(location: (source as NSString).length, length: 0), raw: false))
        }
        for source in ["`source", "$x^2", "[label](https://", "https://example", "```swift\nlet name", "$$\nx^2"] {
            #expect(!MarkdownProseAssistance.allowsAssistance(source: source, selection: NSRange(location: (source as NSString).length, length: 0), raw: false))
        }
        #expect(!MarkdownProseAssistance.allowsAssistance(source: "hello", selection: NSRange(location: 2, length: 0), raw: true))
    }
    @Test func renderingExcludesEquationsInsideCode() {
        let source = "Before $x^2$\n```swift\nlet price = \"$a$\"\n```\n```mermaid\ngraph TD\n A-->B\n```\n$$\nx+y\n$$"
        #expect(MarkdownRenderedSource.spans(in: source).map(\.kind) == ["inline", "diagram", "display"])
        #expect(MarkdownRenderedSource.spans(in: "~~~swift\n$a$\n~~~\n`$b$`\n```swift\n$c$").isEmpty)
    }
    @Test func inlineCodeDelimitersCannotCrossFencedBlockBoundaries() {
        let source = "~~~md\n```\n~~~\n[Real](https://example.com)\n![Photo](Attachments/real.png)\n```swift\nx\n```"
        #expect(MarkdownSyntax.inlineSpans(in: source).filter { $0.kind == .code }.isEmpty)
        #expect(MarkdownInlineLink.links(in: source).map(\.destination) == ["https://example.com"])
        #expect(MarkdownMediaReference.references(in: source).map(\.path) == ["Attachments/real.png"])
    }

    @Test func inlineCodeBeforeAndAfterFencesRetainsUTF16Ranges() {
        let source = "😀 `first\nline`\n~~~md\n`literal`\n~~~\n😁 ``second ` value``"
        let ns = source as NSString
        let spans = MarkdownSyntax.inlineSpans(in: source).filter { $0.kind == .code }
        #expect(spans.map { ns.substring(with: $0.contentRange) } == ["first\nline", "second ` value"])
        #expect(spans.map { ns.substring(with: $0.fullRange) } == ["`first\nline`", "``second ` value``"])
    }

    @Test func unmatchedInlineCodeCannotCloseBeyondAFence() {
        let source = "`before\n~~~md\ncode\n~~~\nafter`"
        #expect(MarkdownSyntax.inlineSpans(in: source).filter { $0.kind == .code }.isEmpty)
    }
    @Test @MainActor func documentReplacementParticipatesInNativeUndo() throws {
        var source = "Original"
        let coordinator = EditorCoordinator(text: .init(get: { source }, set: { source = $0 }))
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 320, height: 1000))
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), textContainer: container)
        view.delegate = coordinator; coordinator.textViewRef = view
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        coordinator.replaceDocument("Original\n![Photo](../Attachments/a.png)")
        #expect(source.contains("Photo"))
        #expect(view.undoManager?.canUndo == true)
        view.undoManager?.undo()
        #expect(view.text == "Original")
    }
    @Test @MainActor func bundledRendererProducesEquationAndDiagramImages() async throws {
        let renderer = MarkdownSyntaxRenderer.shared
        for (source, kind) in [("x^2 + y^2 = z^2", "inline"), ("graph TD\n A-->B", "diagram")] {
            let span = MarkdownRenderedSource(range: NSRange(location: 0, length: source.utf16.count), source: source, kind: kind)
            var result: MarkdownRenderedImage?
            for _ in 0..<150 {
                result = renderer.result(span, width: 320, fontSize: 17, dark: false)
                if result != nil || renderer.failed(span, width: 320, fontSize: 17, dark: false) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let rendered = try #require(result, "Offline renderer failed for \(kind)")
            #expect(rendered.image.size.width > 10)
            #expect(rendered.image.size.height > 10)
            if kind == "inline", let image = rendered.image.cgImage {
                let width = image.width, height = image.height
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                pixels.withUnsafeMutableBytes { buffer in
                    let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
                #expect((0..<height).allSatisfy { pixels[($0 * width + width - 1) * 4 + 3] == 0 }, "Equation is clipped against the snapshot edge")
            }
        }
    }

}
