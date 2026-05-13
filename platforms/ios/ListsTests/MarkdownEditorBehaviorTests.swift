import Foundation
import Testing
@testable import Lists

/// L1 corpus: drives each behaviour module via `EditorIntent` and
/// asserts the source + selection delta.
///
/// Cases land progressively as the modules they exercise are
/// implemented under TDD. Each `@Suite` corresponds to one module
/// so failures localise.
@Suite("L1 — Editor behaviour corpus")
struct MarkdownEditorBehaviorTests {

    // MARK: ListContinuation

    @Suite("Return / list continuation")
    struct ReturnTests {

        // Bullets (-, *, +)
        @Test func dashBulletContinues() {
            EditorFixture.expect(.enter,
                                 from: "- one|",
                                 produces: "- one\n- |")
        }
        @Test func asteriskBulletContinues() {
            EditorFixture.expect(.enter,
                                 from: "* one|",
                                 produces: "* one\n* |")
        }
        @Test func plusBulletContinues() {
            EditorFixture.expect(.enter,
                                 from: "+ one|",
                                 produces: "+ one\n+ |")
        }

        // Empty bullet exits the list (line becomes empty paragraph)
        @Test func emptyDashBulletExits() {
            EditorFixture.expect(.enter,
                                 from: "- |",
                                 produces: "|")
        }
        @Test func emptyAsteriskBulletExits() {
            EditorFixture.expect(.enter,
                                 from: "* |",
                                 produces: "|")
        }
        @Test func emptyPlusBulletExits() {
            EditorFixture.expect(.enter,
                                 from: "+ |",
                                 produces: "|")
        }

        // Numbered increments
        @Test func numberedBulletContinuesAndIncrements() {
            EditorFixture.expect(.enter,
                                 from: "1. one|",
                                 produces: "1. one\n2. |")
        }
        @Test func numberedBulletIncrementsAcrossDigits() {
            EditorFixture.expect(.enter,
                                 from: "9. nine|",
                                 produces: "9. nine\n10. |")
        }
        @Test func emptyNumberedBulletExits() {
            EditorFixture.expect(.enter,
                                 from: "1. |",
                                 produces: "|")
        }

        // Task lists — continue as UNCHECKED regardless of prior state
        @Test func uncheckedTaskContinues() {
            EditorFixture.expect(.enter,
                                 from: "- [ ] task|",
                                 produces: "- [ ] task\n- [ ] |")
        }
        @Test func checkedTaskContinuesAsUnchecked() {
            EditorFixture.expect(.enter,
                                 from: "- [x] done|",
                                 produces: "- [x] done\n- [ ] |")
        }
        @Test func capitalCheckedTaskContinuesAsUnchecked() {
            EditorFixture.expect(.enter,
                                 from: "- [X] DONE|",
                                 produces: "- [X] DONE\n- [ ] |")
        }
        @Test func emptyTaskExits() {
            EditorFixture.expect(.enter,
                                 from: "- [ ] |",
                                 produces: "|")
        }
        @Test func bareCheckboxMarkerNoTrailingSpaceExits() {
            // Existing UI test invariant — typing `- [ ]` with no
            // trailing space then Return should still exit the list.
            EditorFixture.expect(.enter,
                                 from: "- [ ]|",
                                 produces: "|")
        }

        // Blockquote
        @Test func blockquoteContinues() {
            EditorFixture.expect(.enter,
                                 from: "> quote|",
                                 produces: "> quote\n> |")
        }
        @Test func emptyBlockquoteExits() {
            EditorFixture.expect(.enter,
                                 from: "> |",
                                 produces: "|")
        }

        // Nested indent is preserved on continuation
        @Test func nestedBulletPreservesIndent() {
            EditorFixture.expect(.enter,
                                 from: "    - nested|",
                                 produces: "    - nested\n    - |")
        }
        @Test func deepNestedBulletPreservesIndent() {
            EditorFixture.expect(.enter,
                                 from: "        - deep|",
                                 produces: "        - deep\n        - |")
        }
        @Test func nestedNumberedPreservesIndentAndIncrements() {
            EditorFixture.expect(.enter,
                                 from: "    1. nested|",
                                 produces: "    1. nested\n    2. |")
        }
        @Test func nestedTaskPreservesIndent() {
            EditorFixture.expect(.enter,
                                 from: "    - [ ] nested task|",
                                 produces: "    - [ ] nested task\n    - [ ] |")
        }

        // Plain paragraph — no continuation; default newline
        @Test func plainParagraphReturnInsertsNewline() {
            EditorFixture.expect(.enter,
                                 from: "Just text|",
                                 produces: "Just text\n|")
        }
        @Test func emptyLineReturnInsertsNewline() {
            EditorFixture.expect(.enter,
                                 from: "|",
                                 produces: "\n|")
        }

        // Caret in middle of bullet content — split and continue marker
        @Test func returnInMiddleOfContentSplitsLine() {
            EditorFixture.expect(.enter,
                                 from: "- on|e",
                                 produces: "- on\n- |e")
        }

        // Existing UI-test invariants
        @Test func taskContinuationFromExistingSmoke() {
            EditorFixture.expect(.enter,
                                 from: "- [ ] Follow up|",
                                 produces: "- [ ] Follow up\n- [ ] |")
        }
    }

    // MARK: BackspaceHandler — P3 (lands after Return is green)

    @Suite("Backspace")
    struct BackspaceTests {
        @Test func backspaceAtStartOfSecondBulletJoinsWithFirst() {
            EditorFixture.expect(.backspace,
                                 from: "- one\n- |two",
                                 produces: "- one|two")
        }
    }

    // MARK: IndentHandler

    @Suite("Tab / Shift-Tab")
    struct IndentTests {
        // Tab inserts 4 spaces at the START of the current line
        @Test func tabOnPlainLineIndentsByFourSpaces() {
            EditorFixture.expect(.tab,
                                 from: "Plain|",
                                 produces: "    Plain|")
        }
        @Test func tabOnBulletIndentsMarker() {
            EditorFixture.expect(.tab,
                                 from: "- one|",
                                 produces: "    - one|")
        }
        @Test func tabInsideMultiLineBulletDocIndentsCurrentLineOnly() {
            EditorFixture.expect(.tab,
                                 from: "- one\n- |two",
                                 produces: "- one\n    - |two")
        }
        @Test func tabOnNumberedIndents() {
            EditorFixture.expect(.tab,
                                 from: "1. one|",
                                 produces: "    1. one|")
        }
        @Test func tabOnTaskIndents() {
            EditorFixture.expect(.tab,
                                 from: "- [ ] task|",
                                 produces: "    - [ ] task|")
        }
        @Test func tabOnBlockquoteIndents() {
            EditorFixture.expect(.tab,
                                 from: "> quote|",
                                 produces: "    > quote|")
        }
        @Test func tabMidContentStillIndentsLine() {
            EditorFixture.expect(.tab,
                                 from: "- on|e",
                                 produces: "    - on|e")
        }

        // Shift-Tab removes up to 4 leading spaces
        @Test func shiftTabOnIndentedBulletOutdents() {
            EditorFixture.expect(.shiftTab,
                                 from: "    - one|",
                                 produces: "- one|")
        }
        @Test func shiftTabOnPlainLineOutdents() {
            EditorFixture.expect(.shiftTab,
                                 from: "    Plain|",
                                 produces: "Plain|")
        }
        @Test func shiftTabOnUnindentedLineIsNoop() {
            EditorFixture.expect(.shiftTab,
                                 from: "- one|",
                                 produces: "- one|")
        }
        @Test func shiftTabOnDoubleIndentReducesByFour() {
            EditorFixture.expect(.shiftTab,
                                 from: "        - deep|",
                                 produces: "    - deep|")
        }
        @Test func shiftTabPartialIndentRemovesAllAvailable() {
            // Only 2 leading spaces — outdent removes both, doesn't
            // wrap-around.
            EditorFixture.expect(.shiftTab,
                                 from: "  partial|",
                                 produces: "partial|")
        }
    }

    // MARK: CursorSnapping — P3

    @Suite("Cursor / arrow keys")
    struct CursorTests {
        @Test func upArrowKeepsSourceColumnNotVisualColumn() {
            EditorFixture.expect(.move(.up, .none),
                                 from: "- alpha\n- beta|",
                                 produces: "- alpha|\n- beta")
        }
    }

    // MARK: CheckboxToggler — P3

    @Suite("Checkbox tap")
    struct CheckboxTests {
        @Test func tapOnUncheckedCheckboxMarksDone() {
            let start = EditorFixture.parse("- [ ] task|")
            let result = EditorIntent.tapCheckbox(at: 3)
                .apply(to: start.source, selection: start.selection)
            let actual = EditorFixture.encode(source: result.source,
                                              selection: result.selection)
            #expect(actual == "- [x] task|")
        }
    }
}
