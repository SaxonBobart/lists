import Foundation
import Testing
@testable import Lists

@Suite("EditorFixture parser & encoder")
struct EditorFixtureTests {

    @Test func parsesCaretAtStart() {
        let f = EditorFixture.parse("|hello")
        #expect(f.source == "hello")
        #expect(f.selection.location == 0)
        #expect(f.selection.length == 0)
    }

    @Test func parsesCaretInMiddle() {
        let f = EditorFixture.parse("hel|lo")
        #expect(f.source == "hello")
        #expect(f.selection.location == 3)
        #expect(f.selection.length == 0)
    }

    @Test func parsesCaretAtEnd() {
        let f = EditorFixture.parse("hello|")
        #expect(f.source == "hello")
        #expect(f.selection.location == 5)
        #expect(f.selection.length == 0)
    }

    @Test func parsesSelectionForwardAnchor() {
        let f = EditorFixture.parse("a«bc»d")
        #expect(f.source == "abcd")
        #expect(f.selection.location == 1)
        #expect(f.selection.length == 2)
        #expect(f.caretAtSelectionStart == false)
    }

    @Test func parsesSelectionReverseAnchor() {
        let f = EditorFixture.parse("a«!bc»d")
        #expect(f.source == "abcd")
        #expect(f.selection.location == 1)
        #expect(f.selection.length == 2)
        #expect(f.caretAtSelectionStart == true)
    }

    @Test func parsesEscapedPipe() {
        let f = EditorFixture.parse("a\\|b|c")
        #expect(f.source == "a|bc")
        #expect(f.selection.location == 3)
        #expect(f.selection.length == 0)
    }

    @Test func parsesEscapedSelectionDelimiters() {
        let f = EditorFixture.parse("a\\«b\\»c|")
        #expect(f.source == "a«b»c")
        #expect(f.selection.location == 5)
        #expect(f.selection.length == 0)
    }

    @Test func parsesMultilineWithMarkdown() {
        let f = EditorFixture.parse("- one\n- |two")
        #expect(f.source == "- one\n- two")
        #expect(f.selection.location == 8)
        #expect(f.selection.length == 0)
    }

    @Test func encodesCaret() {
        let s = EditorFixture.encode(source: "hello",
                                     selection: NSRange(location: 3, length: 0))
        #expect(s == "hel|lo")
    }

    @Test func encodesSelection() {
        let s = EditorFixture.encode(source: "abcd",
                                     selection: NSRange(location: 1, length: 2))
        #expect(s == "a«bc»d")
    }

    @Test func encodesReverseAnchorSelection() {
        let s = EditorFixture.encode(source: "abcd",
                                     selection: NSRange(location: 1, length: 2),
                                     caretAtSelectionStart: true)
        #expect(s == "a«!bc»d")
    }

    @Test func roundTripIsStableForCaret() {
        let input = "- one\n- |two"
        let f = EditorFixture.parse(input)
        let out = EditorFixture.encode(source: f.source, selection: f.selection)
        #expect(out == input)
    }

    @Test func roundTripIsStableForSelection() {
        let input = "a «bc» d"
        let f = EditorFixture.parse(input)
        let out = EditorFixture.encode(source: f.source,
                                       selection: f.selection,
                                       caretAtSelectionStart: f.caretAtSelectionStart)
        #expect(out == input)
    }
}
