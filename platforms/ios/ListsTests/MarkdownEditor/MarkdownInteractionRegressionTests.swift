import SwiftUI
import Testing
import SnapshotTesting
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

    @Test @MainActor
    func queuedParentUpdateCannotRewindANewerNativeKeystroke() async {
        let (view, coordinator) = makeEditingHarness(source: "L")
        let state = NativeProseState(text: "An older parent render")
        let binding = Binding(get: { state.text }, set: { state.text = $0 })
        coordinator.synchronizeTextBinding(binding, with: view)
        view.delegate = coordinator
        view.selectedRange = NSRange(location: 1, length: 0)
        view.insertText("o")
        await nextMainTurn()
        #expect(state.text == "Lo")
        #expect(view.text == "Lo")
        #expect(view.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test @MainActor
    func queuedExternalUpdatesUseTheNewestBinding() async {
        let (view, coordinator) = makeEditingHarness(source: "Original")
        let first = NativeProseState(text: "Obsolete source")
        let latest = NativeProseState(text: "Current source")
        coordinator.synchronizeTextBinding(Binding(get: { first.text }, set: { first.text = $0 }), with: view)
        coordinator.synchronizeTextBinding(Binding(get: { latest.text }, set: { latest.text = $0 }), with: view)
        await nextMainTurn()
        #expect(view.text == "Current source")
        #expect(first.text == "Obsolete source")
        #expect(latest.text == "Current source")
    }

    @Test @MainActor
    func standaloneEditorAcceptsExternalUpdatesAfterNativeTyping() async throws {
        let state = NativeProseState(text: "Original")
        let controller = UIHostingController(rootView: NativeStandaloneHarness(state: state))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 640)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        await nextMainTurn()
        controller.view.layoutIfNeeded()
        func findEditor(_ view: UIView) -> MarkdownInternalTextView? {
            (view as? MarkdownInternalTextView) ?? view.subviews.lazy.compactMap(findEditor).first
        }
        let view = try #require(findEditor(controller.view))
        state.text = "Superseded parent text"
        state.text = "External"
        await nextMainTurn()
        await nextMainTurn()
        #expect(view.text == "External")
        #expect(view.becomeFirstResponder())
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        view.insertText("!")
        await nextMainTurn()
        #expect(state.text == "External!")
        #expect(view.text == "External!")
        state.text = "E"
        await nextMainTurn()
        await nextMainTurn()
        #expect(view.text == "E", "a genuine external edit must still apply while the editor is focused")
    }

    @MainActor
    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private struct NativeStandaloneHarness: View {
        @ObservedObject var state: NativeProseState
        var body: some View { MarkdownTextView(text: $state.text) }
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

/// Bounded input/persistence diagnosis. Real mounted document/editor, synthetic
/// file stores, and test-only traces; no production instrumentation.
@Suite(.serialized)
@MainActor
struct CaretInputDiagnosticTests {
    private let markdown = """
    A full-screen attachment browser without sub-items.

    [Project brief](../Attachments/c5614859-f759-4533-8ded-4d3b43dfe487.pdf)

    ## Restart checkpoint
    Before **bold** and [safe link](https://example.com).
    Audit background checkpoint.

    """

    @Test func mountedInputMatrixPreservesTextSelectionAndColdPersistence() async throws {
        for rich in [false, true] {
            for mode in ["rapid", "paced", "paste", "replacement"] {
                let source = rich ? markdown : "Restart checkpoint.\nBefore plain text.\nAudit background checkpoint.\n"
                try await check(name: "\(rich ? "markdown" : "plain")-\(mode)", source: source, mode: mode)
            }
        }
    }

    @Test func inactiveNotificationPromotesDraftBeforeStoreFlush() async throws {
        try await check(name: "inactive-before-debounce",
                        source: "Latest edit immediately before inactive.\n", mode: "inactive")
    }

    @Test func inactiveDoesNotReplaySettledDraftOverExternalUpdate() async throws {
        try await check(name: "settled-draft-external-update",
                        source: "Local edit before external update.\n", mode: "settled-external")
    }

    @Test func pendingTextPreservesConcurrentMetadataOnInactive() async throws {
        try await check(name: "pending-text-concurrent-fields",
                        source: "Local body edit.\n", mode: "concurrent-fields")
    }

    @Test func pendingBodyPreservesExternalTitleAndMetadataOnInactive() async throws {
        try await check(name: "pending-body-external-title",
                        source: "Local body edit.\n", mode: "concurrent-body")
    }

    @Test func pendingTitlePreservesExternalBodyAndMetadataOnInactive() async throws {
        try await check(name: "pending-title-external-body",
                        source: "Not locally edited.\n", mode: "concurrent-title")
    }

    @Test func externalDeletionIsNotReversedByPendingDraftOnInactive() async throws {
        try await check(name: "pending-draft-external-delete",
                        source: "Local edit before deletion.\n", mode: "deleted")
    }

    @MainActor private final class HostLifecycleProbe {
        var disappeared = false
    }

    @MainActor private final class DeletionProbeGate {
        enum ProbeError: Error { case forcedFailure }
        var reached = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pauseThenFail() async throws {
            reached = true
            await withCheckedContinuation { continuation = $0 }
            throw ProbeError.forcedFailure
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    @Test func pendingTextSurvivesInactiveDuringRejectedFailedDeletion() async throws {
        try await check(name: "pending-text-rejected-delete", source: "Retained text after failed deletion.\n", mode: "failed-delete")
    }

    @Test func propertyAttemptDoesNotDiscardPendingTextDuringFailedDeletion() async throws {
        try await check(name: "pending-text-property-rejected-delete", source: "Retained text and property attempt.\n", mode: "failed-delete-property")
    }

    @Test func rejectedTextOnlyFlushDoesNotClaimPropertyFailure() async throws {
        try await check(name: "pending-text-no-property-change", source: "Text without a new property.\n", mode: "failed-delete-same-property")
    }

    @Test func revertedTextDoesNotReplayOverNewerExternalText() async throws {
        try await check(name: "reverted-local-text", source: "Temporary local edit.\n", mode: "reverted")
    }

    @Test func pendingTextAndImmediateTagCommitBothPersistWithoutIdleReplay() async throws {
        try await check(name: "pending-text-immediate-tag", source: "Local text before tag commit.\n", mode: "property-tag")
    }

    @Test func nativeMarkedTextCompositionPreservesCommittedSource() async throws {
        try await check(name: "native-marked-text", source: "IME anchor.\n", mode: "composition")
    }

    private func check(name: String, source: String, mode: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CaretInput-\(UUID())")
        let deletionGate = DeletionProbeGate()
        var hooks = ItemStore.MaintenanceTestHooks()
        if mode.hasPrefix("failed-delete") {
            hooks.flagWriteWillCommit = { try await deletionGate.pauseThenFail() }
        }
        let store = ItemStore(store: FileStore(root: root), maintenanceTestHooks: hooks)
        try await store.bootstrap()
        let initial = mode == "replacement" || mode == "composition" ? source : "Original disposable text.\n"
        var item = Item(type: .note, title: "Caret diagnostic \(name)", listId: ItemList.inboxId)
        item.body = initial
        if mode == "property-tag" || mode == "failed-delete-property" || mode == "failed-delete-same-property" { item.tags = ["initial"] }
        try await store.add(item)
        var concurrentList: ItemList?
        var concurrentParent: Item?
        if mode.hasPrefix("concurrent") {
            let section = ListSection(name: "External section", position: 1)
            let list = ItemList(id: "concurrent-\(UUID())", name: "External destination",
                                icon: "folder", color: .blue, createdAt: .now,
                                modifiedAt: .now, position: 99, sections: [section])
            try await store.addList(list)
            let parent = Item(type: .note, title: "External parent", listId: list.id,
                              section: section.id.uuidString)
            try await store.add(parent)
            concurrentList = list
            concurrentParent = parent
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let lifecycle = HostLifecycleProbe()
        let host = UIHostingController(rootView: ItemDocumentView(item: item, store: store)
            .onDisappear { lifecycle.disappeared = true }
            .transaction { $0.disablesAnimations = true })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.overrideUserInterfaceStyle = .light
        window.traitOverrides.preferredContentSizeCategory = .large
        host.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        var trace: [[String: Any]] = []
        let previousClipboard = UIPasteboard.general.items
        defer {
            UIPasteboard.general.items = previousClipboard
            window.isHidden = true
            window.rootViewController = nil
            let path = ProcessInfo.processInfo.environment["LISTS_CARET_EVIDENCE_DIR"]
            let directory = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("CaretInputEvidence")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("\(name).json"))
            }
        }
        await nextTurn()
        host.view.layoutIfNeeded()
        func editor(in view: UIView) -> MarkdownInternalTextView? {
            if let result = view as? MarkdownInternalTextView { return result }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let view = try #require(editor(in: host.view))
        let coordinator = try #require(view.delegate as? EditorCoordinator)
        // Read the installed binding whose getter reads the real document
        // draft. Reflection stays in this diagnostic test; no app hooks.
        let draftBinding = try #require(
            Mirror(reflecting: coordinator).children.first { $0.label == "textBinding" }?.value as? Binding<String>
        )
        func titleInput(in view: UIView) -> UITextView? {
            if let input = view as? UITextView, input.accessibilityIdentifier == "document.title" { return input }
            return view.subviews.lazy.compactMap { titleInput(in: $0) }.first
        }
        let titleView = try #require(titleInput(in: host.view))
        let titleCoordinator = try #require(titleView.delegate as? DocumentTitleField.Coordinator)
        let titleBinding = try #require(
            Mirror(reflecting: titleCoordinator).children.first { $0.label == "text" }?.value as? Binding<String>
        )
        #expect(view.becomeFirstResponder())
        func capture(_ stage: String, expected: String? = nil) {
            var entry: [String: Any] = [
                "case": name, "stage": stage, "editorText": view.text ?? "",
                "selectedLocation": view.selectedRange.location,
                "selectedLength": view.selectedRange.length,
                "isFirstResponder": view.isFirstResponder,
                "hasMarkedText": view.markedTextRange != nil,
                "storeBody": store.item(item.id)?.body ?? "",
                "draftBody": draftBinding.wrappedValue,
                "editorTitle": titleView.text ?? "",
                "draftTitle": titleBinding.wrappedValue,
                "titleIsFirstResponder": titleView.isFirstResponder,
                "updateUIViewReplacementCondition": view.text != draftBinding.wrappedValue && view.markedTextRange == nil,
                "time": Date().timeIntervalSince1970
            ]
            if let expected { entry["expectedEditorText"] = expected }
            trace.append(entry)
        }
        capture("initial", expected: initial)
        var expected = source
        if mode == "concurrent-fields" || mode == "concurrent-title" {
            #expect(titleView.becomeFirstResponder())
            titleView.selectedRange = NSRange(location: 0, length: titleView.text.utf16.count)
            titleView.insertText("Local title edit")
            capture("local-title-edit")
            if mode == "concurrent-fields" { #expect(view.becomeFirstResponder()) }
        }
        if mode == "concurrent-title" {
            expected = initial
            capture("local-title-only", expected: initial)
        } else if mode == "replacement" {
            let range = try #require((source as NSString).range(of: "Restart").optional)
            view.selectedRange = range
            capture("selection-before-replacement")
            view.insertText("Replaced")
            expected = (source as NSString).replacingCharacters(in: range, with: "Replaced")
            capture("replacement-immediate", expected: expected)
        } else if mode == "composition" {
            view.selectedRange = NSRange(location: initial.utf16.count, length: 0)
            view.setMarkedText("ka", selectedRange: NSRange(location: 2, length: 0))
            capture("marked-latin")
            #expect(view.markedTextRange != nil)
            view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
            capture("marked-japanese")
            view.unmarkText()
            capture("composition-committed")
            view.insertText("\n")
            expected = initial + "かな\n"
            capture("composition-final", expected: expected)
        } else {
            view.selectedRange = NSRange(location: 0, length: view.text.utf16.count)
            capture("select-all-before-input")
            if mode == "paste" {
                UIPasteboard.general.string = source
                view.paste(nil)
                await nextTurn()
                capture("paste-immediate", expected: source)
            } else {
                var prefix = ""
                for (index, character) in source.enumerated() {
                    view.insertText(String(character))
                    prefix.append(character)
                    capture("input-\(index)-immediate", expected: prefix)
                    if mode == "paced" {
                        try await Task.sleep(for: .milliseconds(100))
                        await nextTurn()
                        host.view.layoutIfNeeded()
                    } else {
                        await Task.yield()
                    }
                    capture("input-\(index)-settled", expected: prefix)
                    if view.text != prefix {
                        Issue.record("Input changed in \(name) at character \(index); see stage trace")
                        break
                    }
                }
            }
        }
        await nextTurn()
        host.view.layoutIfNeeded()
        capture("before-editor-debounce", expected: expected)
        #expect(view.text == expected)
        #expect(draftBinding.wrappedValue == expected)
        #expect(view.markedTextRange == nil)
        let immediate = view.text ?? ""
        let inputFinishedAt = Date()
        if mode.hasPrefix("failed-delete") {
            let journal = root.appendingPathComponent(".deletion-journals.json")
            try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
            let blocker = Task { try await store.toggleFlagged(item.id) }
            for _ in 0..<100 where !deletionGate.reached { await Task.yield() }
            #expect(deletionGate.reached)
            let deletion = Task { try await store.softDelete(item.id) }
            func deletionInFlight() -> Bool {
                let roots = Mirror(reflecting: store).children.first { $0.label?.hasSuffix("itemDeletionRootsInFlight") == true }?.value as? Set<UUID>
                return roots?.contains(item.id) == true
            }
            for _ in 0..<100 where !deletionInFlight() { await Task.yield() }
            #expect(deletionInFlight(), "deletion must hold its conflict guard before inactive")
            if mode == "failed-delete-property" || mode == "failed-delete-same-property" {
                func tagInput(in view: UIView) -> UITextField? {
                    if let input = view as? UITextField { return input }
                    return view.subviews.lazy.compactMap { tagInput(in: $0) }.first
                }
                let input = try #require(tagInput(in: host.view))
                #expect(input.becomeFirstResponder())
                input.text = mode == "failed-delete-same-property" ? "initial" : "attempted"
                input.sendActions(for: .editingChanged)
                _ = input.delegate?.textFieldShouldReturn?(input)
                await nextTurn()
                host.view.layoutIfNeeded()
                #expect(input.window != nil, "reverting rejected metadata must keep the focused input mounted")
                #expect(input.isFirstResponder, "property rejection must preserve native input focus")
                #expect(draftBinding.wrappedValue == source, "property rejection must retain pending local text")
                #expect(store.item(item.id)?.tags == ["initial"], "rejected metadata must remain unchanged")

                // SwiftUI's virtual accessibility tree is supplied to the OS
                // automation consumer, not reliably to in-process UIKit
                // container traversal. Check actual mounted visibility here;
                // remote simulator automation separately verifies accessibility.
                // Hide only the blinking insertion caret while preserving focus.
                let tint = input.tintColor
                input.tintColor = .clear
                // Let keyboard avoidance and the focused-field scroll settle.
                try await Task.sleep(for: .milliseconds(500))
                await nextTurn()
                host.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                input.tintColor = tint
                #expect(input.isFirstResponder)
                let diagnostic = FileManager.default.temporaryDirectory.appendingPathComponent("CaretInputEvidence")
                try FileManager.default.createDirectory(at: diagnostic, withIntermediateDirectories: true)
                try rendered.pngData()?.write(to: diagnostic.appendingPathComponent("\(name).png"))
                if let failure = verifySnapshot(of: rendered, as: .image, record: .never, testName: name) {
                    Issue.record(Comment(rawValue: failure))
                }
                capture("property-rejection-visible-and-reverted")
                if mode == "failed-delete-property", let evidence = ProcessInfo.processInfo.environment["LISTS_CARET_EVIDENCE_DIR"] {
                    let directory = URL(fileURLWithPath: evidence, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    try screenshot.pngData()?.write(to: directory.appendingPathComponent("property-rejection.png"))
                }
            }
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            capture("inactive-during-deletion-conflict")
            #expect(store.item(item.id)?.body == initial, "conflict should reject unaccepted text")
            deletionGate.release()
            switch await blocker.result { case .success: Issue.record("gated flag must fail"); case .failure: break }
            switch await deletion.result { case .success: Issue.record("gated deletion must fail before tombstoning"); case .failure: break }
            #expect(store.item(item.id)?.deletedAt == nil)
            try FileManager.default.removeItem(at: journal)
            // This is the same retained page as Keep Open after the failure;
            // removing its host executes the actual close/onDisappear path.
            host.beginAppearanceTransition(false, animated: false)
            window.isHidden = true
            window.rootViewController = nil
            host.endAppearanceTransition()
            for _ in 0..<100 where !lifecycle.disappeared { await nextTurn() }
            #expect(lifecycle.disappeared, "host close must deliver disappearance before checking durability")
            await nextTurn()
            try? await store.flushPendingWrites() // unrelated operation failures stay sticky
            let loaded = try await FileStore(root: root).loadAll()
            let actual = try #require(loaded.lists.flatMap(\.items).first { $0.id == item.id })
            trace.append(["case": name, "stage": "failed-delete-close-cold", "diskBody": actual.body,
                          "expectedBody": source, "deleted": actual.deletedAt != nil])
            #expect(actual.deletedAt == nil)
            #expect(actual.body == source, "rejected local intent must retry when closing after deletion fails")
            if mode == "failed-delete-property" || mode == "failed-delete-same-property" {
                #expect(actual.tags == ["initial"], "visibly rejected tag must not later save silently")
            }
            return
        }
        if mode == "reverted" || mode == "property-tag" {
            if mode == "reverted" {
                view.selectedRange = NSRange(location: 0, length: view.text.utf16.count)
                view.insertText(initial)
                #expect(draftBinding.wrappedValue == initial)
                #expect(store.item(item.id)?.body == initial)
            } else {
                func tagInput(in view: UIView) -> UITextField? {
                    if let input = view as? UITextField { return input }
                    return view.subviews.lazy.compactMap { tagInput(in: $0) }.first
                }
                let input = try #require(tagInput(in: host.view))
                #expect(input.becomeFirstResponder())
                input.text = "committed"
                input.sendActions(for: .editingChanged)
                _ = input.delegate?.textFieldShouldReturn?(input)
                #expect(store.item(item.id)?.tags == ["initial", "committed"])
                #expect(store.item(item.id)?.body == source)
                try await store.flushPendingWrites()
                let early = try await FileStore(root: root).loadAll()
                let saved = try #require(early.lists.flatMap(\.items).first { $0.id == item.id })
                #expect(saved.body == source)
                #expect(saved.tags == ["initial", "committed"])
            }
            capture("after-revert-or-property-commit")
            var external = try #require(store.item(item.id))
            external.title = "New external title"
            external.body = "New external body after local intent ended.\n"
            external.flagged = true
            try await store.update(external)
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            try await store.flushPendingWrites()
            try await Task.sleep(for: .milliseconds(850))
            try await store.flushPendingWrites()
            capture("inactive-after-intent-ended")
            let loaded = try await FileStore(root: root).loadAll()
            let actual = try #require(loaded.lists.flatMap(\.items).first { $0.id == item.id })
            #expect(actual.title == external.title)
            #expect(actual.body == external.body)
            #expect(actual.tags == external.tags)
            #expect(actual.flagged)
            return
        }
        if mode.hasPrefix("concurrent") {
            let list = try #require(concurrentList)
            let parent = try #require(concurrentParent)
            var external = try #require(store.item(item.id))
            #expect(external.body == initial, "test must reach the external write before local debounce")
            if mode != "concurrent-body" { #expect(external.title == item.title) }
            external.tags = ["external"]
            external.flagged = true
            external.priority = .high
            external.listId = list.id
            external.section = list.sections[0].id.uuidString
            external.parentId = parent.id
            if mode == "concurrent-body" { external.title = "External title" }
            if mode == "concurrent-title" { external.body = "External body.\n" }
            try await store.update(external)
            capture("external-fields-before-inactive")
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            try await store.flushPendingWrites()
            capture("concurrent-fields-after-inactive")
            let actual = try #require(store.item(item.id))
            let wantedTitle = mode == "concurrent-body" ? external.title : "Local title edit"
            let wantedBody = mode == "concurrent-title" ? external.body : source
            #expect(actual.title == wantedTitle)
            #expect(actual.body == wantedBody)
            #expect(actual.tags == external.tags)
            #expect(actual.flagged == external.flagged)
            #expect(actual.priority == external.priority)
            #expect(actual.parentId == external.parentId)
            #expect(actual.listId == external.listId)
            #expect(actual.section == external.section)
            let disk = try await FileStore(root: root).loadAll()
            let persisted = try #require(disk.lists.flatMap(\.items).first { $0.id == item.id })
            #expect(persisted.title == wantedTitle)
            #expect(persisted.body == wantedBody)
            #expect(persisted.tags == external.tags)
            #expect(persisted.flagged == external.flagged)
            #expect(persisted.parentId == external.parentId)
            #expect(persisted.listId == external.listId)
            #expect(persisted.section == external.section)
            trace.append(["case": name, "stage": "concurrent-fields-cold",
                          "body": persisted.body, "title": persisted.title,
                          "tags": persisted.tags, "list": persisted.listId,
                          "section": persisted.section ?? "", "parent": persisted.parentId?.uuidString ?? "",
                          "flagged": persisted.flagged])
            return
        }
        if mode == "deleted" {
            try await store.softDelete(item.id)
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            try await store.flushPendingWrites()
            capture("deleted-item-after-inactive")
            #expect(store.item(item.id)?.deletedAt != nil)
            let disk = try await FileStore(root: root).loadAll()
            let persisted = try #require(disk.lists.flatMap(\.items).first { $0.id == item.id })
            #expect(persisted.deletedAt != nil)
            return
        }
        // The app's inactive handler invokes this store durability boundary.
        // This is a proxy for that call, not an actual OS scene transition.
        if mode == "inactive" {
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            capture("after-will-resign-active-notification", expected: immediate)
        }
        try await store.flushPendingWrites()
        capture("immediate-inactive-store-flush-proxy", expected: immediate)
        if mode == "inactive" {
            #expect(store.item(item.id)?.body == immediate,
                    "inactive must promote the local document draft before the app's store flush")
            let earlyLoad = try await FileStore(root: root).loadAll()
            let persisted = try #require(earlyLoad.lists.flatMap(\.items).first { $0.id == item.id })
            let encodedImmediate = immediate.hasSuffix("\n") ? immediate : immediate + "\n"
            trace.append(["case": name, "stage": "inactive-durable-before-debounce",
                          "diskBody": persisted.body, "expectedEncodedBody": encodedImmediate,
                          "elapsedMilliseconds": Date().timeIntervalSince(inputFinishedAt) * 1000])
            #expect(persisted.body == encodedImmediate)
        }
        trace.append(["case": name, "stage": "immediate-flush-timing",
                      "elapsedMilliseconds": Date().timeIntervalSince(inputFinishedAt) * 1000,
                      "actualOSBackgroundTransition": false])
        try await Task.sleep(for: .milliseconds(850))
        capture("after-700ms-editor-debounce", expected: immediate)
        #expect(view.text == immediate, "layout/debounce must not change editor source")
        #expect(store.item(item.id)?.body == immediate, "editor debounce must forward exact latest source")
        if mode == "settled-external" {
            let external = "Externally updated after this editor settled.\n"
            var changed = try #require(store.item(item.id))
            changed.body = external
            try await store.update(changed)
            capture("external-update-before-inactive")
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            try await store.flushPendingWrites()
            capture("external-update-after-inactive")
            #expect(store.item(item.id)?.body == external,
                    "inactive must not replay a settled page's stale body")
            let loaded = try await FileStore(root: root).loadAll()
            #expect(loaded.lists.flatMap(\.items).first { $0.id == item.id }?.body == external)
            // Align only this disposable view for teardown after checking the
            // inactive event; cleanup must not create a second stale edit.
            draftBinding.wrappedValue = external
            return
        }
        try await store.flushPendingWrites()
        capture("after-store-flush", expected: immediate)
        let cold = ItemStore(store: FileStore(root: root))
        try await cold.bootstrap()
        let diskBody = try #require(cold.item(item.id)).body
        let encoded = immediate.hasSuffix("\n") ? immediate : immediate + "\n"
        trace.append(["case": name, "stage": "cold-file-reload", "diskBody": diskBody, "expectedEncodedBody": encoded])
        #expect(diskBody == encoded)
        view.resignFirstResponder()
        window.isHidden = true
        window.rootViewController = nil
        await nextTurn()
        try await store.flushPendingWrites()
        let reloaded = ItemStore(store: FileStore(root: root))
        try await reloaded.bootstrap()
        #expect(reloaded.item(item.id)?.body == encoded)
        trace.append(["case": name, "stage": "after-host-disappear-cold-reload",
                      "diskBody": reloaded.item(item.id)?.body ?? ""])
    }

    private func nextTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
