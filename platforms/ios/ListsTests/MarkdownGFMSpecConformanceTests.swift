import Foundation
import Testing
@testable import Lists

/// L2 corpus: every CommonMark + GFM spec example must:
///   1. Load and decode.
///   2. Feed through `MarkdownStyler` without crashing.
///   3. Round-trip byte-identical through the styler (source
///      preserved end-to-end).
///   4. Feed through `PasteHandler.normalize` and survive the
///      normaliser without source mutation (besides the documented
///      newline / tab / BOM conversions).
///
/// Per-fixture *renderer* output structural assertions (paragraphs,
/// heading levels, link tree) require accessing MarkdownUI's internal
/// AST, which the package doesn't expose. The renderer is well
/// covered by upstream tests; we treat it as a trusted dependency
/// and focus L2 on **our** styler + paste + source-preservation
/// invariants.
@Suite("L2 — GFM spec conformance")
@MainActor
struct MarkdownGFMSpecConformanceTests {

    @Test func commonMarkSpecCorpusLoads() throws {
        let fixtures = try GFMSpecLoader.load("commonmark-0.31.2.json")
        // The official 0.31.2 spec has 649 examples.
        #expect(fixtures.count > 600,
                "Expected ~649 CommonMark fixtures, got \(fixtures.count)")
        #expect(fixtures.first?.markdown != nil)
    }

    @Test func everyCommonMarkFixtureStylesWithoutCrashing() throws {
        let fixtures = try GFMSpecLoader.load("commonmark-0.31.2.json")
        for fixture in fixtures {
            let styler = MarkdownStyler()
            styler.replaceCharacters(in: NSRange(location: 0, length: 0),
                                     with: fixture.markdown)
            // Source must round-trip byte-identical.
            #expect(styler.string == fixture.markdown,
                    "Fixture #\(fixture.example) (\(fixture.section)) source mutated")
        }
    }

    @Test func everyCommonMarkFixtureSurvivesPasteNormalise() throws {
        let fixtures = try GFMSpecLoader.load("commonmark-0.31.2.json")
        for fixture in fixtures {
            let normalised = PasteHandler.normalize(fixture.markdown)
            // Re-normalising is a no-op (idempotent invariant).
            let twice = PasteHandler.normalize(normalised)
            #expect(twice == normalised,
                    "Fixture #\(fixture.example) (\(fixture.section)) is not idempotent under normalise")
            // Pastes don't introduce smart-typography. If the input
            // didn't have `\r` / `\t` / BOM, the normaliser must
            // produce the same string.
            if !fixture.markdown.contains("\r"),
               !fixture.markdown.contains("\t"),
               !fixture.markdown.hasPrefix("\u{FEFF}") {
                #expect(normalised == fixture.markdown,
                        "Fixture #\(fixture.example) (\(fixture.section)) was mutated by normalise")
            }
        }
    }

    @Test func everyCommonMarkFixtureSurvivesPasteApply() throws {
        let fixtures = try GFMSpecLoader.load("commonmark-0.31.2.json")
        for fixture in fixtures {
            let result = PasteHandler.apply(fixture.markdown,
                                            to: "",
                                            selection: NSRange(location: 0, length: 0))
            let expected = PasteHandler.normalize(fixture.markdown)
            #expect(result.source == expected,
                    "Fixture #\(fixture.example) (\(fixture.section)) source diverged from normalise")
        }
    }
}
