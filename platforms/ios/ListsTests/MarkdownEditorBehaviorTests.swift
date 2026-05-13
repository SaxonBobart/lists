import Foundation
import Testing
@testable import Lists

/// L1 corpus: drives each behaviour module via `EditorIntent` and
/// asserts the source + selection delta. ~300 cases when complete.
///
/// Cases land progressively as the modules they exercise are
/// implemented under TDD. Each `@Suite` corresponds to one module so
/// failures are easy to localise.
///
/// Sentinel notation is documented in `EditorFixture`.
@Suite("L1 — Editor behaviour corpus")
struct MarkdownEditorBehaviorTests {

    // MARK: ListContinuation (P3)

    @Suite("Return / list continuation")
    struct ReturnTests {
        @Test func returnAtEndOfBulletContinuesMarker() {
            EditorFixture.expect(
                .enter,
                from: "- one|",
                produces: "- one\n- |"
            )
        }
    }

    // MARK: BackspaceHandler (P3)

    @Suite("Backspace")
    struct BackspaceTests {
        @Test func backspaceAtStartOfSecondBulletJoinsWithFirst() {
            EditorFixture.expect(
                .backspace,
                from: "- one\n- |two",
                produces: "- one|two"
            )
        }
    }

    // MARK: IndentHandler (P3)

    @Suite("Tab / Shift-Tab")
    struct IndentTests {
        @Test func tabInsideBulletItemIndentsByFourSpaces() {
            EditorFixture.expect(
                .tab,
                from: "- one\n- |two",
                produces: "- one\n    - |two"
            )
        }
    }

    // MARK: CursorSnapping (P3)

    @Suite("Cursor / arrow keys")
    struct CursorTests {
        @Test func upArrowKeepsSourceColumnNotVisualColumn() {
            EditorFixture.expect(
                .move(.up, .none),
                from: "- alpha\n- beta|",
                produces: "- alpha|\n- beta"
            )
        }
    }

    // MARK: CheckboxToggler (P3)

    @Suite("Checkbox tap")
    struct CheckboxTests {
        @Test func tapOnUncheckedCheckboxMarksDone() {
            // Tap at bracket index 3 (the `[`).
            let start = EditorFixture.parse("- [ ] task|")
            let result = EditorIntent.tapCheckbox(at: 3)
                .apply(to: start.source, selection: start.selection)
            let actual = EditorFixture.encode(source: result.source,
                                              selection: result.selection)
            #expect(actual == "- [x] task|")
        }
    }
}
