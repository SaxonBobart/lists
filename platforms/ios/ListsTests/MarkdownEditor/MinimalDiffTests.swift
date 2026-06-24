import Foundation
import Testing
@testable import Lists

/// The editor applies a transform's full new source as the *minimal* changed
/// range via the text input layer (so native Undo works). TextDiff.minimal
/// computes that range in UTF-16 / NSString space.
struct MinimalDiffTests {

    @Test func identicalStringsAreNoOp() {
        let diff = TextDiff.minimal(from: "hello", to: "hello")
        #expect(diff.range.length == 0)
        #expect(diff.replacement == "")
    }

    @Test func insertInMiddle() {
        let diff = TextDiff.minimal(from: "ac", to: "abc")
        #expect(diff.range == NSRange(location: 1, length: 0))
        #expect(diff.replacement == "b")
    }

    @Test func deleteSingleChar() {
        let diff = TextDiff.minimal(from: "abc", to: "ac")
        #expect(diff.range == NSRange(location: 1, length: 1))
        #expect(diff.replacement == "")
    }

    @Test func replaceRun() {
        let diff = TextDiff.minimal(from: "abXYZcd", to: "abPQcd")
        #expect(diff.range == NSRange(location: 2, length: 3))
        #expect(diff.replacement == "PQ")
    }

    @Test func appendAtEnd() {
        let diff = TextDiff.minimal(from: "ab", to: "abc")
        #expect(diff.range == NSRange(location: 2, length: 0))
        #expect(diff.replacement == "c")
    }

    @Test func emojiInsertUsesUTF16Units() {
        // Inserting before a family emoji: the range must be in UTF-16 units.
        let emoji = "👨‍👩‍👧‍👦"
        let diff = TextDiff.minimal(from: emoji, to: "X" + emoji)
        #expect(diff.range == NSRange(location: 0, length: 0))
        #expect(diff.replacement == "X")
    }

    @Test func emojiAppendUsesUTF16Units() {
        let emoji = "👨‍👩‍👧‍👦"
        let diff = TextDiff.minimal(from: emoji, to: emoji + "!")
        #expect(diff.range == NSRange(location: (emoji as NSString).length, length: 0))
        #expect(diff.replacement == "!")
    }
}
