import XCTest
@testable import Lists

/// ED-1: the editor applies a transform's full new source as the *minimal*
/// changed range via the text input layer (so native Undo works). TextDiff.minimal
/// computes that range in UTF-16 / NSString space.
final class MinimalDiffTests: XCTestCase {

    func testIdenticalStringsAreNoOp() {
        let d = TextDiff.minimal(from: "hello", to: "hello")
        XCTAssertEqual(d.range.length, 0)
        XCTAssertEqual(d.replacement, "")
    }

    func testInsertInMiddle() {
        let d = TextDiff.minimal(from: "ac", to: "abc")
        XCTAssertEqual(d.range, NSRange(location: 1, length: 0))
        XCTAssertEqual(d.replacement, "b")
    }

    func testDeleteSingleChar() {
        let d = TextDiff.minimal(from: "abc", to: "ac")
        XCTAssertEqual(d.range, NSRange(location: 1, length: 1))
        XCTAssertEqual(d.replacement, "")
    }

    func testReplaceRun() {
        let d = TextDiff.minimal(from: "abXYZcd", to: "abPQcd")
        XCTAssertEqual(d.range, NSRange(location: 2, length: 3))
        XCTAssertEqual(d.replacement, "PQ")
    }

    func testAppendAtEnd() {
        let d = TextDiff.minimal(from: "ab", to: "abc")
        XCTAssertEqual(d.range, NSRange(location: 2, length: 0))
        XCTAssertEqual(d.replacement, "c")
    }

    func testEmojiInsertUsesUTF16Units() {
        // Inserting before a family emoji: the range must be in UTF-16 units.
        let emoji = "👨‍👩‍👧‍👦"
        let d = TextDiff.minimal(from: emoji, to: "X" + emoji)
        XCTAssertEqual(d.range, NSRange(location: 0, length: 0))
        XCTAssertEqual(d.replacement, "X")
    }

    func testEmojiAppendUsesUTF16Units() {
        let emoji = "👨‍👩‍👧‍👦"
        let d = TextDiff.minimal(from: emoji, to: emoji + "!")
        XCTAssertEqual(d.range, NSRange(location: (emoji as NSString).length, length: 0))
        XCTAssertEqual(d.replacement, "!")
    }
}
