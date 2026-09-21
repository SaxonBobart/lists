import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Lists

@Suite("Markdown interaction overhaul", .serialized)
@MainActor
struct MarkdownInteractionOverhaulTests {
    @Test func attachmentsSkipHiddenSourceAndExpandCrossingSelections() throws {
        let source = "Before\n\n![Photo](Attachments/photo.png)\n\n[PDF](Attachments/report.pdf)\n\nAfter"
        let blocks = MarkdownAttachmentEditing.blocks(in: source)
        #expect(blocks.count == 2)
        for block in blocks {
            #expect(MarkdownAttachmentEditing.snappedCaret(block.range.location + 1, previous: block.range.location, in: source) == NSMaxRange(block.range))
            #expect(MarkdownAttachmentEditing.snappedCaret(NSMaxRange(block.range) - 1, previous: NSMaxRange(block.range), in: source) == block.range.location)
            #expect(MarkdownAttachmentEditing.expandedRange(NSRange(location: NSMaxRange(block.range) - 1, length: 1), in: source) == block.range)
            #expect(MarkdownAttachmentEditing.expandedRange(NSRange(location: block.range.location, length: 1), in: source) == block.range)
        }
        let partial = NSRange(location: blocks[0].range.location + 3, length: blocks[1].range.location - blocks[0].range.location)
        #expect(MarkdownAttachmentEditing.expandedRange(partial, in: source) == NSUnionRange(blocks[0].range, blocks[1].range))
        #expect(MarkdownAttachmentEditing.blocks(in: "See [PDF](Attachments/report.pdf) here").isEmpty)
        #expect(MarkdownAttachmentEditing.blocks(in: "    ![Photo](Attachments/photo.png)").isEmpty)
        #expect(MarkdownAttachmentEditing.blocks(in: "```md\n![Photo](Attachments/photo.png)\n```").isEmpty)
    }

    @Test func previewPreferenceDoesNotChangeSourceAndSurvivesDocumentMoves() throws {
        let suite = "editor-preview-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let preferences = MarkdownAttachmentPresentation(documentID: id, defaults: defaults)
        let source = "![Photo](../../Attachments/photo.png)"
        let photo = try #require(MarkdownMediaReference.references(in: source).first)
        let moved = try #require(MarkdownMediaReference.references(in: "![Photo](../Attachments/photo.png)").first)
        #expect(preferences.isExpanded(photo))
        preferences.setExpanded(false, for: photo)
        #expect(!MarkdownAttachmentPresentation(documentID: id, defaults: defaults).isExpanded(moved))
        #expect(MarkdownAttachmentPresentation(documentID: UUID(), defaults: defaults).isExpanded(photo))
        #expect(source == "![Photo](../../Attachments/photo.png)")
        let pdf = try #require(MarkdownMediaReference.references(in: "[Report](Attachments/report.pdf)").first)
        #expect(preferences.isExpanded(pdf))
        let linkedImage = try #require(MarkdownMediaReference.references(in: "[Photo](Attachments/other.png)").first)
        #expect(!preferences.isExpanded(linkedImage))
        #expect(linkedImage.canPreview)
    }

    @Test func nativeAttachmentDeletionIsAtomicUndoableAndDoesNotDeleteFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("editor-attachment-\(UUID()).png")
        let data = Data("retained attachment".utf8)
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let source = "Before\n\n![Photo](Attachments/\(file.lastPathComponent))\n\nAfter"
        let harness = Harness(source)
        let reference = try #require(MarkdownAttachmentEditing.blocks(in: source).first)
        harness.view.selectedRange = NSRange(location: NSMaxRange(reference.range), length: 0)
        harness.view.undoManager?.removeAllActions()
        harness.view.undoManager?.beginUndoGrouping()
        #expect(!harness.coordinator.textView(harness.view, shouldChangeTextIn: NSRange(location: NSMaxRange(reference.range) - 1, length: 1), replacementText: ""))
        harness.view.undoManager?.endUndoGrouping()
        #expect(harness.view.text == "Before\n\n\n\nAfter")
        #expect(harness.view.selectedRange.location == reference.range.location)
        harness.view.undoManager?.undo()
        #expect(harness.view.text == source)
        harness.view.undoManager?.redo()
        #expect(harness.view.text == "Before\n\n\n\nAfter")
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func forwardDeleteAndCrossingReplacementAreAtomicButRawEditsStayLiteral() throws {
        let source = "Before\n  ![Photo](Attachments/photo.png)\nAfter"
        let reference = try #require(MarkdownAttachmentEditing.blocks(in: source).first)
        let forward = Harness(source)
        #expect(forward.storage.mediaHeight(at: reference.range.location) != nil)
        forward.view.selectedRange = NSRange(location: reference.range.location, length: 0)
        #expect(!forward.coordinator.textView(forward.view, shouldChangeTextIn: NSRange(location: reference.range.location, length: 1), replacementText: ""))
        #expect(forward.view.text == "Before\n  \nAfter")
        let replacement = Harness(source)
        let crossing = NSRange(location: reference.range.location + 2, length: NSMaxRange(reference.range) + 2 - reference.range.location)
        let expanded = MarkdownAttachmentEditing.expandedRange(crossing, in: source)
        replacement.view.selectedRange = crossing
        #expect(!replacement.coordinator.textView(replacement.view, shouldChangeTextIn: crossing, replacementText: "Replacement"))
        #expect(replacement.view.text == (source as NSString).replacingCharacters(in: expanded, with: "Replacement"))
        let raw = Harness(source)
        raw.storage.mode = .raw
        #expect(raw.coordinator.textView(raw.view, shouldChangeTextIn: NSRange(location: reference.range.location, length: 1), replacementText: ""))
    }

    @Test func selectionsStartingInCodeStillConsumeCrossedAttachments() throws {
        let source = "```text\ncode\n```\n\n![Photo](Attachments/photo.png)\nAfter"
        let reference = try #require(MarkdownAttachmentEditing.blocks(in: source).first)
        let range = NSRange(location: 10, length: reference.range.location + 4 - 10)
        let harness = Harness(source)
        harness.view.selectedRange = range
        #expect(!harness.coordinator.textView(harness.view, shouldChangeTextIn: range, replacementText: "Replacement"))
        #expect(harness.view.text == (source as NSString).replacingCharacters(in: NSUnionRange(range, reference.range), with: "Replacement"))
    }

    @Test func attachmentBoundaryCaretsMatchCardHeightAndSourceStaysHidden() throws {
        let source = "[Report](Attachments/report.pdf)\n\nAfter"
        let harness = Harness(source)
        let ref = try #require(MarkdownAttachmentEditing.blocks(in: source).first)
        let rect = try #require(harness.view.attachmentRect(for: ref))
        for index in [ref.range.location, NSMaxRange(ref.range)] {
            harness.storage.cursorRange = NSRange(location: index, length: 0)
            let position = try #require(harness.view.position(from: harness.view.beginningOfDocument, offset: index))
            let caret = harness.view.caretRect(for: position)
            #expect(abs(caret.height - rect.height) < 1)
            #expect(harness.storage.mediaHeight(at: ref.range.location) != nil)
        }
        let after = try #require(harness.view.position(from: harness.view.beginningOfDocument, offset: NSMaxRange(ref.range) + 1))
        #expect(harness.view.caretRect(for: after).height < 60)
    }

    @Test func renderedContentRangesExcludeEveryDelimiter() throws {
        for source in ["$$\na^2+b^2=c^2\n$$", "```mermaid\nflowchart TD\nA --> B\n```", "~~~~mermaid\nflowchart TD\n~~~~"] {
            let span = try #require(MarkdownRenderedSource.spans(in: source).first)
            #expect((source as NSString).substring(with: span.contentRange) == span.source)
            #expect(span.contentRange.location > span.range.location)
            #expect(NSMaxRange(span.contentRange) < NSMaxRange(span.range))
        }
        let empty = try #require(MarkdownRenderedSource.spans(in: "$$\n\n$$").first)
        #expect(empty.contentRange.length == 0)
    }

    @Test func activePreviewFitsBetweenSourceAndNextParagraphWithNormalInteriorCaret() throws {
        for source in ["$$\na^2+b^2=c^2\n$$\n\nAfter", "```mermaid\nflowchart TD\nA --> B\n```\n\nAfter"] {
            let harness = Harness(source)
            let span = try #require(MarkdownRenderedSource.spans(in: source).first)
            let size = CGSize(width: 120, height: span.kind == "diagram" ? 180 : 44)
            let image = UIGraphicsImageRenderer(size: size).image { _ in UIColor.label.setFill(); UIRectFill(CGRect(origin: .zero, size: size)) }
            harness.storage.syntaxImages[span.kind + span.source] = MarkdownRenderedImage(image: image, kind: span.kind, source: span.source)
            harness.storage.cursorRange = span.contentRange
            harness.storage.invalidateLayoutDependentStyling()
            let preview = try #require(harness.view.syntaxPreviewRect(for: span))
            let afterRange = (source as NSString).range(of: "After")
            let afterGlyph = harness.view.layoutManager.glyphIndexForCharacter(at: afterRange.location)
            let afterLine = harness.view.layoutManager.lineFragmentRect(forGlyphAt: afterGlyph, effectiveRange: nil).offsetBy(dx: 0, dy: harness.view.textContainerInset.top)
            #expect(preview.maxY <= afterLine.minY)
            let interior = try #require(harness.view.position(from: harness.view.beginningOfDocument, offset: NSMaxRange(span.range) - 1))
            let edge = try #require(harness.view.position(from: harness.view.beginningOfDocument, offset: NSMaxRange(span.range)))
            #expect(harness.view.caretRect(for: interior).height < 50)
            #expect(abs(harness.view.caretRect(for: edge).height - size.height) < 1)
            #expect(harness.storage.string == source)
        }
    }

    @Test func rendererReportsRealErrorsRecoversAndKeepsLatestRapidEdit() async throws {
        let renderer = MarkdownSyntaxRenderer()
        @MainActor func settled(_ span: MarkdownRenderedSource, lane: String? = nil) async throws -> MarkdownSyntaxRenderState {
            for _ in 0..<200 {
                let state = renderer.state(span, width: 320, fontSize: 17, dark: false, coalescingID: lane)
                if case .pending = state { try await Task.sleep(for: .milliseconds(50)) }
                else { return state }
            }
            Issue.record("Renderer did not settle")
            return .pending
        }
        for (kind, invalid, valid) in [("display", "a^", "a^2"), ("diagram", "flowchart TD\nA -->", "flowchart TD\nA --> B")] {
            let bad = MarkdownRenderedSource(range: NSRange(location: 0, length: invalid.utf16.count), source: invalid, kind: kind)
            let error = try await settled(bad)
            if case .diagnostic(let message) = error {
                #expect(!message.isEmpty)
                #expect(!message.hasPrefix("Preview unavailable."))
                #expect(kind != "display" || message.contains("^") || message.localizedCaseInsensitiveContains("superscript"))
            } else { Issue.record("Invalid source must expose its diagnostic") }
            let good = MarkdownRenderedSource(range: bad.range, source: valid, kind: kind)
            if case .success(let rendered) = try await settled(good) { #expect(rendered.source == valid) }
            else { Issue.record("Correcting the source must clear the diagnostic") }
        }
        for value in 1...8 {
            let span = MarkdownRenderedSource(range: NSRange(location: 0, length: 3), source: "x^{\(value)}", kind: "display")
            _ = renderer.state(span, width: 320, fontSize: 17, dark: false, coalescingID: "editing-block")
        }
        let final = MarkdownRenderedSource(range: NSRange(location: 0, length: 3), source: "x^{8}", kind: "display")
        if case .success(let result) = try await settled(final, lane: "editing-block") { #expect(result.source == "x^{8}") }
        else { Issue.record("Latest rapid edit must render") }
        // Distinct readers at identical offsets must not cancel one another.
        let other = MarkdownRenderedSource(range: final.range, source: "y^{9}", kind: "display")
        if case .success(let result) = try await settled(other) { #expect(result.source == "y^{9}") }
        else { Issue.record("Independent preview must render") }
    }

    @Test func typingOpeningFenceOneCharacterAtATimeKeepsCaretAfterSource() {
        let harness = Harness("")
        harness.view.delegate = harness.coordinator
        var expected = ""
        for character in "```sw" {
            harness.view.insertText(String(character))
            expected.append(character)
            #expect(harness.view.text == expected)
            #expect(harness.view.selectedRange == NSRange(location: expected.utf16.count, length: 0))
        }
        #expect(MarkdownCodeCompletion.at(harness.view.selectedRange, in: harness.view.text)?.query == "sw")
    }

    @Test func languageCompletionOnlyChangesTheOpeningIdentifier() throws {
        let source = "```py\nprint(1)\n```\nAfter"
        let completion = try #require(MarkdownCodeCompletion.at(NSRange(location: 5, length: 0), in: source))
        #expect(completion.query == "py")
        #expect((source as NSString).replacingCharacters(in: completion.range, with: "python") == "```python\nprint(1)\n```\nAfter")
        #expect(MarkdownCodeLanguage.matching("py").contains { $0.id == "python" })
        #expect(MarkdownCodeLanguage.matching("js").contains { $0.id == "javascript" })
        #expect(MarkdownCodeLanguage.matching("mer").contains { $0.id == "mermaid" })
        #expect(MarkdownCodeCompletion.at(NSRange(location: 9, length: 0), in: source) == nil)
        #expect(MarkdownCodeCompletion.at(NSRange(location: 20, length: 0), in: source) == nil)
        #expect(MarkdownCodeCompletion.at(NSRange(location: 4, length: 0), in: "```s")?.query == "s")
        #expect(MarkdownCodeLanguage.matching("unsupported-language").isEmpty)
    }

    @Test func highlightingRetainsUTF16OffsetsAndUnknownLanguagesStayPlain() async throws {
        let source = "let title = \"👩🏽‍💻 <&>\"\n// comment\nlet count = 42"
        let tokens = await MarkdownCodeHighlighter.shared.tokens(source: source, language: "swift")
        #expect(!tokens.isEmpty)
        #expect(tokens.contains { $0.scope.contains("comment") && (source as NSString).substring(with: NSRange(location: $0.location, length: $0.length)) == "// comment" })
        #expect(tokens.contains { $0.scope.contains("number") && (source as NSString).substring(with: NSRange(location: $0.location, length: $0.length)) == "42" })
        #expect(await MarkdownCodeHighlighter.shared.tokens(source: source, language: "unknown-language").isEmpty)
    }

    @Test func anchorsHandleFormattingDuplicatesLegacyTargetsAndCodeExamples() throws {
        let body = "# First *section*\n## Repeat\n## Repeat\n## Repeat-1\n```markdown\n# Not a heading\n```\n    # Also code\n\nSetext heading\n====\n## Café Θ"
        let headings = DocumentMarkdownIndex.outline(title: "Document", body: body).dropFirst()
        #expect(headings.map(\.anchor) == ["first-section", "repeat", "repeat-1", "repeat-1-1", "setext-heading", "café-θ"])
        #expect(DocumentMarkdownIndex.heading("repeat-1", title: "Document", body: body)?.title == "Repeat")
        #expect(DocumentMarkdownIndex.heading("First%20section", title: "Document", body: body)?.anchor == "first-section")
        #expect(DocumentMarkdownIndex.heading("First%20*section*", title: "Document", body: body)?.anchor == "first-section")
        #expect(DocumentMarkdownIndex.heading("missing", title: "Document", body: body) == nil)
    }

    @Test func parsedHeadingsExcludeHTMLAndIncludeNestedAndMultilineSections() {
        let body = "<pre>\n# Example\n</pre>\n\n> ## Quoted **heading**\n\n- ## Nested\n\nTwo line\nheading\n---\n\n## `under_score` &amp; more"
        let headings = DocumentMarkdownIndex.outline(title: "Note", body: body).dropFirst()
        #expect(headings.map(\.anchor) == ["quoted-heading", "nested", "two-line-heading", "under_score--more"])
    }

    @Test func inlineFileLinksUseNativeItemsAndKeepNativeSelectionActions() throws {
        let source = "Read [File](Attachments/example.txt) here"
        let storage = MarkdownStyler(scope: .inlineOnly)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        let label = (source as NSString).range(of: "File")
        #expect(storage.attribute(.link, at: label.location, effectiveRange: nil) as? URL == URL(string: "Attachments/example.txt"))
        storage.cursorRange = NSRange(location: label.location, length: 0)
        #expect(storage.attribute(.link, at: label.location, effectiveRange: nil) == nil)
        let harness = Harness(source)
        let copy = UIAction(title: "Copy") { _ in }
        let menu = try #require(harness.coordinator.textView(harness.view, editMenuForTextInRanges: [NSValue(range: label)], suggestedActions: [copy]))
        #expect(menu.children.compactMap { ($0 as? UIAction)?.title } == ["Open", "Copy"])
        #expect(harness.view.text == source)
    }

    @Test func sameDocumentHeadingLinksUsePortableFragment() {
        let item = Item(type: .note, title: "Note", body: "## Section", listId: "inbox")
        #expect(DocumentMarkdownIndex.portableDestination(from: item, to: item, heading: "section", lists: []) == "#section")
        #expect(DocumentMarkdownIndex.resolveInternalDestination("#section", from: item, items: [item], lists: [])?.itemId == item.id)
    }

    @Test func internalLinkCancellationRestoresCapturedBodyAndTableSelectionsOnce() {
        let selections = [
            DocumentLinkEditorSelection(range: NSRange(location: 3, length: 4), selectedText: "text"),
            DocumentLinkEditorSelection(tableLocation: 12, address: .init(row: 1, column: 0),
                                        range: NSRange(location: 2, length: 3), selectedText: "row")
        ]
        for selection in selections {
            let session = DocumentLinkSession()
            let id = UUID()
            session.begin(source: .init(itemId: id, title: "Source", selection: selection))
            session.cancel()
            #expect(session.isActive == false)
            let request = session.consumeReturnRequest()
            #expect(request?.itemId == id)
            #expect(request?.focus == selection.focusTarget)
            #expect(session.consumeReturnRequest() == nil)
        }
    }

    @Test func internalHeadingInsertionReturnsToSourceAfterInsertedLink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("link-return-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        let item = Item(type: .note, title: "Note", body: "text\n\n## Section\n\n## Section", listId: "inbox")
        try await store.add(item)
        let session = DocumentLinkSession()
        session.begin(source: .init(itemId: item.id, title: item.title,
                                   selection: .init(range: NSRange(location: 0, length: 4), selectedText: "text")))
        let heading = try #require(session.headingOptions(for: item).last)
        session.commit(to: item, heading: heading, store: store)
        let link = "[text](#section-1)"
        #expect(store.item(item.id)?.body == link + "\n\n## Section\n\n## Section")
        #expect(session.returnRequest?.focus == .body(NSRange(location: link.utf16.count, length: 0)))
        #expect(session.returnRequest?.itemId == item.id)
        #expect(session.isActive == false)
        try await store.flushPendingWrites()
    }

    @Test func smartListsAndUnicodeDeletionKeepCompleteSource() {
        let cases: [(String, Int, String, Int)] = [
            ("- alpha", 4, "- al\n- pha", 7),
            ("- ", 2, "", 0),
            ("    - ", 6, "- ", 2),
            ("- [x] done", 10, "- [x] done\n- [ ] ", 17),
            ("1. first", 8, "1. first\n2. ", 12)
        ]
        for (source, caret, expected, next) in cases {
            let result = ListContinuation.apply(to: source, selection: NSRange(location: caret, length: 0))
            #expect(result.source == expected)
            #expect(result.selection.location == next)
        }
        for grapheme in ["👩🏽‍💻", "e\u{301}", "🇦🇺"] {
            let source = "a" + grapheme
            #expect(BackspaceHandler.applyBackspace(to: source, selection: NSRange(location: source.utf16.count, length: 0)).source == "a")
            #expect(BackspaceHandler.applyForwardDelete(to: source, selection: NSRange(location: 1, length: 0)).source == "a")
        }
    }

    @MainActor private final class Harness {
        let storage = MarkdownStyler()
        let view: MarkdownInternalTextView
        let coordinator: EditorCoordinator
        init(_ source: String) {
            let layout = MarkdownLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            view = MarkdownInternalTextView(frame: CGRect(x: 0, y: 0, width: 340, height: 1600), textContainer: container)
            coordinator = EditorCoordinator(text: .constant(source))
            coordinator.textViewRef = view
            coordinator.layoutDelegate.styler = storage
            layout.delegate = coordinator.layoutDelegate
            storage.glyphInvalidatable = layout
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
            layout.ensureLayout(for: container)
        }
    }
}
