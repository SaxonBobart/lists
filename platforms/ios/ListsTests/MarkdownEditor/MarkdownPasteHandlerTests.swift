import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Lists

@MainActor
struct MarkdownPasteHandlerTests {
    @Test func urlOverSelectionBecomesMarkdownLink() throws {
        let url = try #require(URL(string: "https://example.com/roadmap"))

        let result = PasteHandler.apply(
            .url(url),
            to: "Read the roadmap today",
            selection: NSRange(location: 9, length: 7)
        )

        #expect(result.source == "Read the [roadmap](https://example.com/roadmap) today")
        #expect(result.selection == NSRange(location: 47, length: 0))
    }

    @Test func bareURLPasteRemainsOrdinarySource() throws {
        let url = try #require(URL(string: "https://example.com/path"))

        let result = PasteHandler.apply(
            .url(url),
            to: "Visit ",
            selection: NSRange(location: 6, length: 0)
        )

        #expect(result.source == "Visit https://example.com/path")
        #expect(!result.source.contains("<https://"))
    }

    @Test func selectedBracketsAndDestinationParenthesesRemainValidMarkdown() throws {
        let url = try #require(URL(string: "https://example.com/a_(b)"))

        let result = PasteHandler.apply(
            .url(url),
            to: "See [draft]",
            selection: NSRange(location: 4, length: 7)
        )

        #expect(result.source == "See [&#91;draft&#93;](https://example.com/a_%28b%29)")
        #expect(MarkdownInlineLink.links(in: result.source).count == 1)
    }

    @Test func rectangularTSVBecomesGFMTable() {
        let result = PasteHandler.apply(
            "Name\tStatus\nLists\tActive\nNotes\tPlanned\n",
            to: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.source == """
        | Name | Status |
        | --- | --- |
        | Lists | Active |
        | Notes | Planned |

        """)
        #expect(MarkdownTableParser.tables(in: result.source).first?.columnCount == 2)
    }

    @Test func spreadsheetCellsEscapePipesQuotesAndEmbeddedNewlines() {
        let pasted = "Name\tNotes\nLists\t\"Left | right\"\nQuote\t\"Said \"\"hello\"\"\ntwice\""

        let result = PasteHandler.apply(
            pasted,
            to: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.source.contains("| Lists | Left \\| right |"))
        #expect(result.source.contains("| Quote | Said \"hello\"<br>twice |"))
        #expect(MarkdownTableParser.tables(in: result.source).first?.bodyRows.count == 2)
    }

    @Test func tablePasteBreaksCleanlyOutOfSurroundingProse() {
        let result = PasteHandler.apply(
            "A\tB\n1\t2",
            to: "Before selected after",
            selection: NSRange(location: 7, length: 8)
        )

        #expect(result.source == "Before \n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n after")
        #expect(MarkdownTableParser.tables(in: result.source).count == 1)
    }

    @Test func raggedOrMalformedTSVFallsBackToVerbatimTextRules() {
        let ragged = PasteHandler.apply(
            "A\tB\nOnly one cell",
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        let unclosedQuote = PasteHandler.apply(
            "A\tB\n1\t\"unfinished",
            to: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(ragged.source == "A    B\nOnly one cell")
        #expect(unclosedQuote.source == "A    B\n1    \"unfinished")
        #expect(MarkdownTableParser.tables(in: ragged.source).isEmpty)
        #expect(MarkdownTableParser.tables(in: unclosedQuote.source).isEmpty)
    }

    @Test func invalidSelectionIsClampedInsteadOfCrashing() {
        let result = PasteHandler.apply(
            "safe",
            to: "abc",
            selection: NSRange(location: 99, length: 50)
        )

        #expect(result.source == "abcsafe")
    }

    @Test func smartPasteIsOneNativeUndoStep() throws {
        var bindingText = "Roadmap"
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 320, height: 500))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let textView = MarkdownInternalTextView(frame: .zero, textContainer: container)
        let coordinator = EditorCoordinator(text: Binding(
            get: { bindingText },
            set: { bindingText = $0 }
        ))
        textView.delegate = coordinator
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: bindingText)
        textView.selectedRange = NSRange(location: 0, length: 7)

        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(textView)
        window.makeKeyAndVisible()
        #expect(textView.becomeFirstResponder())

        let url = try #require(URL(string: "https://example.com"))
        coordinator.applyPastePayload(.url(url), to: textView)
        #expect(bindingText == "[Roadmap](https://example.com)")
        #expect(textView.undoManager?.canUndo == true)

        textView.undoManager?.undo()
        #expect(textView.text == "Roadmap")
        #expect(bindingText == "Roadmap")
        #expect(textView.selectedRange == NSRange(location: 0, length: 7))
    }
}
