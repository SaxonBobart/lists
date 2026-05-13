import Foundation
import Testing
@testable import Lists

/// L2 corpus: drives the CommonMark + GFM spec fixtures against the
/// preserved-shape renderer and the in-scope subset against the
/// styler.
///
/// Smoke test for P1: just confirm the loader finds + decodes the
/// CommonMark spec.json. Per-fixture assertions land in P6.
@Suite("L2 — GFM spec conformance")
struct MarkdownGFMSpecConformanceTests {

    @Test func commonMarkSpecCorpusLoads() throws {
        let fixtures = try GFMSpecLoader.load("commonmark-0.31.2.json")
        // The official 0.31.2 spec has 649 examples.
        #expect(fixtures.count > 600,
                "Expected ~649 CommonMark fixtures, got \(fixtures.count)")
        #expect(fixtures.first?.markdown != nil)
    }
}
