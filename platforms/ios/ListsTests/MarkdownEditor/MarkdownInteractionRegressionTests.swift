import SwiftUI
import Testing
import UIKit
@testable import Lists

@Suite("Markdown live interaction regressions")
struct MarkdownInteractionRegressionTests {
    struct Fixture: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let marker: String
        let content: String

        var testDescription: String { name }
    }

    private static let inlineFixtures = [
        Fixture(name: "bold", source: "Before **bold** after", marker: "**", content: "bold"),
        Fixture(name: "inline code", source: "Before `code` after", marker: "`", content: "code"),
        Fixture(name: "inline math", source: "Before $x + y$ after", marker: "$", content: "x + y"),
        Fixture(name: "link", source: "Before [Lists](https://example.com) after", marker: "[", content: "Lists"),
        Fixture(name: "wikilink", source: "Before [[Roadmap]] after", marker: "[[", content: "Roadmap"),
        Fixture(name: "footnote", source: "Before reference[^source] after", marker: "[^", content: "source")
    ]

    @Test("Inline syntax hides outside and reveals inside its own span", arguments: inlineFixtures)
    @MainActor
    func inlineSyntaxTracksCaretContext(_ fixture: Fixture) throws {
        let harness = makeHarness(source: fixture.source)
        let markerRange = try #require((fixture.source as NSString).range(of: fixture.marker).optional)
        let contentRange = try #require((fixture.source as NSString).range(of: fixture.content).optional)

        #expect(harness.styler.glyphProperty(at: markerRange.location) == .null)
        harness.styler.cursorRange = NSRange(location: contentRange.location, length: 0)
        #expect(harness.styler.glyphProperty(at: markerRange.location) == nil)

        harness.styler.cursorRange = NSRange(location: 0, length: 0)
        #expect(harness.styler.glyphProperty(at: markerRange.location) == .null)
        #expect(harness.styler.string == fixture.source)
    }

    @Test("Footnote definitions use the same caret-aware marker contract")
    @MainActor
    func footnoteDefinitionTracksCaretContext() throws {
        let source = "[^source]: Durable reference"
        let harness = makeHarness(source: source)
        let content = try #require((source as NSString).range(of: "source").optional)

        #expect(harness.styler.glyphProperty(at: 0) == .null)
        #expect(harness.styler.glyphProperty(at: NSMaxRange(content)) == .null)
        harness.styler.cursorRange = NSRange(location: content.location, length: 0)
        #expect(harness.styler.glyphProperty(at: 0) == nil)
        #expect(harness.styler.glyphProperty(at: NSMaxRange(content)) == nil)
    }

    @Test("Display math delimiters reveal from anywhere inside the block")
    @MainActor
    func displayMathUsesWholeBlockContext() throws {
        let source = "$$\nx + y\n$$"
        let harness = makeHarness(source: source)
        let body = try #require((source as NSString).range(of: "x + y").optional)

        #expect(harness.styler.glyphProperty(at: 0) == .null)
        #expect(harness.styler.glyphProperty(at: (source as NSString).length - 1) == .null)
        harness.styler.cursorRange = NSRange(location: body.location, length: 0)
        #expect(harness.styler.glyphProperty(at: 0) == nil)
        #expect(harness.styler.glyphProperty(at: (source as NSString).length - 1) == nil)
    }

    @Test("Supported block geometry keeps its line height across focus", arguments: [
        Fixture(name: "heading", source: "## Heading", marker: "##", content: "Heading"),
        Fixture(name: "bullet", source: "- Bullet", marker: "-", content: "Bullet"),
        Fixture(name: "quote", source: "> Quoted text", marker: ">", content: "Quoted text"),
        Fixture(name: "callout", source: "> [!NOTE] Heads up", marker: "[!", content: "Heads up"),
        Fixture(name: "fenced code", source: "```swift\nlet value = 1\n```", marker: "```", content: "let value = 1"),
        Fixture(name: "display math", source: "$$\nx + y\n$$", marker: "$$", content: "x + y")
    ])
    @MainActor
    func blockLineHeightIsStable(_ fixture: Fixture) throws {
        let harness = makeHarness(source: fixture.source)
        let content = try #require((fixture.source as NSString).range(of: fixture.content).optional)
        let inactiveHeight = lineHeight(containing: content.location, in: harness)

        harness.styler.cursorRange = NSRange(location: content.location, length: 0)
        let activeHeight = lineHeight(containing: content.location, in: harness)

        #expect(abs(activeHeight - inactiveHeight) < 0.5)
        #expect(harness.styler.string == fixture.source)
    }

    @Test("Table object editing keeps source hidden and row geometry fixed")
    @MainActor
    func tableGeometryDoesNotDependOnCaret() throws {
        let source = "| Name | Status |\n| --- | --- |\n| Lists | Ready |"
        let harness = makeHarness(source: source)
        let cell = try #require((source as NSString).range(of: "Lists").optional)
        let inactiveHeight = lineHeight(containing: cell.location, in: harness)

        #expect(color(at: cell.location, in: harness.styler) == .clear)
        harness.styler.cursorRange = NSRange(location: cell.location, length: 0)
        #expect(color(at: cell.location, in: harness.styler) == .clear)
        #expect(abs(lineHeight(containing: cell.location, in: harness) - inactiveHeight) < 0.5)
        #expect(harness.styler.string == source)
    }

    @Test("Raw mode never hides extension syntax")
    @MainActor
    func rawModeShowsEveryMarker() {
        let source = "[[Roadmap]] [^source] $x$"
        let harness = makeHarness(source: source)
        harness.styler.mode = .raw

        for location in 0..<(source as NSString).length {
            #expect(harness.styler.glyphProperty(at: location) == nil)
        }
        #expect(harness.layout.drawsMarkdownDecorations == false)
    }

    @Test("Raw mode disables every custom layout decoration")
    @MainActor
    func rawModeDisablesLayoutDecorations() {
        let source = "> Quote\n\n> [!NOTE]\n> Callout\n\n- [x] Task\n\n```swift\ncode\n```"
        let harness = makeHarness(source: source)
        #expect(harness.layout.drawsMarkdownDecorations)

        harness.styler.mode = .raw

        #expect(!harness.layout.drawsMarkdownDecorations)
        #expect(harness.styler.string == source)
    }

    @Test("Raw source caret and replacement never expand to a whole table")
    @MainActor
    func rawTableSyntaxStaysDirectlyEditable() {
        let source = "| Name | Status |\n| --- | --- |\n| Lists | Ready |"
        let (view, coordinator) = makeEditingHarness(source: source, raw: true)
        let name = (source as NSString).range(of: "Name")
        view.selectedRange = NSRange(location: name.location + 1, length: 0)
        coordinator.textViewDidChangeSelection(view)
        #expect(view.selectedRange == NSRange(location: name.location + 1, length: 0))
        #expect(coordinator.textView(view,
                                    shouldChangeTextIn: NSRange(location: name.location, length: 1),
                                    replacementText: "n"))
        view.selectedRange = NSRange(location: name.location, length: 1)
        coordinator.textViewDidChangeSelection(view)
        #expect(view.selectedRange == NSRange(location: name.location, length: 1))
        #expect(view.text == source)
    }

    @Test("Raw list markers remain editable and use native vertical navigation")
    @MainActor
    func rawListMarkersDoNotSnapOrRedirectTyping() {
        let source = "- [ ] task"
        let (view, coordinator) = makeEditingHarness(source: source, raw: true)
        view.selectedRange = NSRange(location: 3, length: 0)
        coordinator.textViewDidChangeSelection(view)
        #expect(view.selectedRange.location == 3)
        #expect(coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "x"))
        #expect(!((view.keyCommands ?? []).contains { $0.input == UIKeyCommand.inputDownArrow }))
        #expect(view.text == source)
    }

    @Test("Code examples do not trigger smart list editing", arguments: [
        "```yaml\n- [ ] code\n```",
        "~~~yaml\n- [ ] code\n~~~",
        "````markdown\n```\n- [ ] code\n````",
        "  ```yaml\n- [ ] code"
    ])
    @MainActor
    func fencedListExamplesRemainLiteral(source: String) {
        let (view, coordinator) = makeEditingHarness(source: source)
        let line = (source as NSString).range(of: "- [ ] code")
        view.selectedRange = NSRange(location: line.location + 3, length: 0)
        coordinator.textViewDidChangeSelection(view)
        #expect(view.selectedRange.location == line.location + 3)
        #expect(!((view.keyCommands ?? []).contains { $0.input == UIKeyCommand.inputDownArrow }))
        #expect(coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "x"))
        view.selectedRange = NSRange(location: NSMaxRange(line), length: 0)
        #expect(coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "\n"))
        view.selectedRange = NSRange(location: line.location + 6, length: 0)
        #expect(coordinator.textView(view,
                                    shouldChangeTextIn: NSRange(location: line.location + 5, length: 1),
                                    replacementText: ""))
        #expect(view.text == source)
    }

    @Test("Code prefixes remain literal during content-column navigation")
    func codeNavigationDoesNotTreatExamplesAsListMarkers() {
        let source = "```\n- [ ] first\n- [ ] second\n```"
        let first = (source as NSString).range(of: "- [ ] first").location
        let second = (source as NSString).range(of: "- [ ] second").location
        let down = CursorSnapping.move(direction: .down, modifiers: [], in: source,
                                       selection: NSRange(location: first + 1, length: 0))
        #expect(down.selection.location == second + 1)
        #expect(CursorSnapping.snapped(second + 1, in: source, movingForward: true) == second + 1)
    }

    @Test("Only a visible checkbox accepts a completion tap")
    @MainActor
    func checkboxHitTestingRejectsBlankSpaceRawAndCode() {
        let (view, coordinator) = makeEditingHarness(source: "- [ ] task")
        view.layoutManager.ensureLayout(for: view.textContainer)
        let firstLine = view.layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let point = CGPoint(x: view.textContainerInset.left + view.textContainer.lineFragmentPadding + 8,
                            y: view.textContainerInset.top + firstLine.midY)
        #expect(coordinator.checkboxStateIndex(at: point, in: view) == 3)
        #expect(coordinator.checkboxStateIndex(at: CGPoint(x: point.x, y: 400), in: view) == nil)
        #expect(coordinator.checkboxStateIndex(at: CGPoint(x: 250, y: point.y), in: view) == nil)
        (view.textStorage as? MarkdownStyler)?.mode = .raw
        #expect(coordinator.checkboxStateIndex(at: point, in: view) == nil)

        let (codeView, codeCoordinator) = makeEditingHarness(source: "```\n- [ ] example\n```")
        codeView.layoutManager.ensureLayout(for: codeView.textContainer)
        let glyph = codeView.layoutManager.glyphIndexForCharacter(at: 4)
        let codeLine = codeView.layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        #expect(codeCoordinator.checkboxStateIndex(at:
            CGPoint(x: point.x, y: codeView.textContainerInset.top + codeLine.midY), in: codeView) == nil)
    }

    @Test("Wrapped checklist continuation lines have no completion target")
    @MainActor
    func wrappedTaskOnlyTogglesOnItsFirstVisualLine() throws {
        let (view, coordinator) = makeEditingHarness(source: "- [ ] " + String(repeating: "Long task text ", count: 12))
        view.layoutManager.ensureLayout(for: view.textContainer)
        var lines: [CGRect] = []
        view.layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: view.layoutManager.numberOfGlyphs)
        ) { rect, _, _, _, _ in lines.append(rect) }
        #expect(lines.count > 1)
        let second = try #require(lines.dropFirst().first)
        let point = CGPoint(x: view.textContainerInset.left + view.textContainer.lineFragmentPadding + 8,
                            y: view.textContainerInset.top + second.midY)
        #expect(coordinator.checkboxStateIndex(at: point, in: view) == nil)
    }

    @Test("Inline attachment taps resolve the touched file and leave prose editable")
    @MainActor
    func inlineAttachmentHitTestingUsesVisibleLabelBounds() {
        let source = "Read [First](Attachments/a.pdf) or [Second](Attachments/b.pdf) now."
        let (view, coordinator) = makeEditingHarness(source: source)
        view.layoutManager.ensureLayout(for: view.textContainer)
        func point(on text: String) -> CGPoint {
            let range = (source as NSString).range(of: text)
            let glyphs = view.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = view.layoutManager.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
            return CGPoint(x: rect.midX + view.textContainerInset.left,
                           y: rect.midY + view.textContainerInset.top)
        }
        #expect(coordinator.attachmentPath(at: point(on: "First")) == "Attachments/a.pdf")
        #expect(coordinator.attachmentPath(at: point(on: "Second")) == "Attachments/b.pdf")
        #expect(coordinator.attachmentPath(at: point(on: "Read")) == nil)
        #expect(coordinator.attachmentPath(at: point(on: "now.")) == nil)
        (view.textStorage as? MarkdownStyler)?.mode = .raw
        #expect(coordinator.attachmentPath(at: point(on: "Second")) == nil)
    }

    @Test("Arrow commands preserve UIKit visual-line movement outside short marker transitions")
    @MainActor
    func wrappedProseAndListsUseNativeArrowMovement() throws {
        let longText = String(repeating: "Long paragraph words ", count: 12)
        for source in ["Plain first\nPlain second", longText + "\nEnd", "- " + longText + "\n- Short", "- Short\n- " + longText] {
            let (view, coordinator) = makeEditingHarness(source: source)
            withExtendedLifetime(coordinator) {
                view.selectedRange = NSRange(location: 3, length: 0)
                #expect(view.keyCommands?.contains(where: { $0.input == UIKeyCommand.inputDownArrow }) == false)
            }
        }
        let (view, coordinator) = makeEditingHarness(source: "- Short\n- Other")
        withExtendedLifetime(coordinator) {
            view.selectedRange = NSRange(location: 3, length: 0)
            #expect(view.keyCommands?.contains(where: { $0.input == UIKeyCommand.inputDownArrow }) == true)
            view.selectedRange = NSRange(location: 11, length: 0)
            #expect(view.keyCommands?.contains(where: { $0.input == UIKeyCommand.inputUpArrow }) == true)
        }
    }

    @Test("Attribute-only restyling refreshes cached sibling marker glyphs")
    @MainActor
    func selectionRestylingRegeneratesSiblingGlyphs() throws {
        let source = "- [ ] **first**\n- [ ] **second**"
        let (view, coordinator) = makeEditingHarness(source: source)
        let storage = try #require(view.textStorage as? MarkdownStyler)
        let first = (source as NSString).range(of: "**first").location
        let second = (source as NSString).range(of: "**second").location
        func hidden(_ location: Int) -> Bool {
            view.layoutManager.ensureLayout(for: view.textContainer)
            let glyph = view.layoutManager.glyphIndexForCharacter(at: location)
            return view.layoutManager.propertyForGlyph(at: glyph).contains(.null)
        }
        withExtendedLifetime(coordinator) {
            #expect(hidden(first))
            #expect(hidden(second))
            storage.cursorRange = NSRange(location: first + 3, length: 0)
            #expect(!hidden(first))
            #expect(hidden(second))
            storage.cursorRange = NSRange(location: second + 3, length: 0)
            #expect(hidden(first))
            #expect(!hidden(second))
            storage.invalidateLayoutDependentStyling()
            #expect(hidden(first))
            #expect(!hidden(second))
            #expect(storage.string == source)
        }
    }

    @Test("Mounted document prose keeps native Undo after binding and layout updates")
    @MainActor
    func mountedProseTypingPreservesNativeUndoAndRedo() async throws {
        let prefix = "# Notes\n\n- [ ] Keep me\n\n"
        let suffix = "\nLast paragraph.\n\n| Header | Other |\n| --- | --- |\n| Cell | Value |\n\n"
        let original = prefix + "First paragraph.\n" + suffix
        let state = NativeProseState(text: original)
        let bridge = DocumentFocusBridge()
        let controller = UIHostingController(rootView: NativeProseHarness(state: state, bridge: bridge))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 640)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { bridge.bodyView?.resignFirstResponder(); window.isHidden = true }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        controller.view.layoutIfNeeded()
        let view = try #require(bridge.bodyView)
        #expect(view.becomeFirstResponder())
        view.selectedRange = NSRange(location: (prefix + "First paragraph.\n").utf16.count, length: 0)
        for typed in ["Q", "\n", "Z"] {
            view.insertText(typed)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            controller.view.layoutIfNeeded()
            #expect(view.text == state.text)
            #expect(view.undoManager?.canUndo == true)
            // More reads this published flag; manually refreshing it here
            // would conceal callbacks that leave the menu disabled.
            #expect(bridge.canUndo)
        }
        let entered = prefix + "First paragraph.\nQ\nZ" + suffix
        #expect(state.text == entered)
        #expect(bridge.canUndo)
        bridge.undo()
        await Task.yield()
        #expect(state.text != entered)
        #expect(view.text == state.text)
        #expect(bridge.canRedo)
        bridge.redo()
        await Task.yield()
        #expect(state.text == entered)
        #expect(view.text == entered)
        for _ in 0..<4 where state.text != original {
            bridge.undo()
            await Task.yield()
        }
        #expect(state.text == original)
        #expect(view.text == original)
    }

    @MainActor
    private final class NativeProseState: ObservableObject {
        @Published var text: String
        init(text: String) { self.text = text }
    }

    @MainActor
    private struct NativeProseHarness: View {
        @ObservedObject var state: NativeProseState
        let bridge: DocumentFocusBridge
        var body: some View {
            ScrollView { DocumentBodyEditor(text: $state.text, bridge: bridge) }
        }
    }

    @MainActor
    private func makeEditingHarness(source: String, raw: Bool = false)
        -> (MarkdownInternalTextView, EditorCoordinator) {
        let harness = makeHarness(source: source)
        harness.styler.mode = raw ? .raw : .live
        let view = MarkdownInternalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 600),
                                            textContainer: harness.container)
        let coordinator = EditorCoordinator(text: .constant(source))
        coordinator.textViewRef = view
        coordinator.layoutDelegate.styler = harness.styler
        harness.layout.delegate = coordinator.layoutDelegate
        // Callbacks are driven explicitly so tests can inspect a proposed
        // UIKit selection before the coordinator normalizes it.
        return (view, coordinator)
    }

    private struct Harness {
        let styler: MarkdownStyler
        let layout: MarkdownLayoutManager
        let container: NSTextContainer
    }

    private func makeHarness(source: String) -> Harness {
        let styler = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate()
        let container = NSTextContainer(
            size: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        )
        delegate.styler = styler
        layout.delegate = delegate
        layout.addTextContainer(container)
        styler.addLayoutManager(layout)
        styler.glyphInvalidatable = layout
        styler.mode = .live
        styler.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        return Harness(styler: styler, layout: layout, container: container)
    }

    private func lineHeight(containing location: Int, in harness: Harness) -> CGFloat {
        harness.layout.ensureLayout(for: harness.container)
        let characterRange = (harness.styler.string as NSString).lineRange(
            for: NSRange(location: location, length: 0)
        )
        let glyphRange = harness.layout.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        return harness.layout.boundingRect(forGlyphRange: glyphRange, in: harness.container).height
    }

    private func color(at location: Int, in styler: MarkdownStyler) -> UIColor? {
        styler.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor
    }
}

private extension NSRange {
    var optional: NSRange? {
        location == NSNotFound ? nil : self
    }
}
