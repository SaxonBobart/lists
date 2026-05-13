import Foundation
import Testing
@testable import Lists

/// Sentinel-encoded editor state used by the L1 behaviour corpus.
///
/// Notation:
///   * `|`        — caret (selection length 0). Escape `|` as `\|`.
///   * `«text»`   — selection spanning `text`. Caret is at the end
///                  of the selection.
///   * `«!text»`  — selection with caret at the *start* (reverse anchor).
///                  Stored as the same NSRange; the `caretAnchor`
///                  field records which end is the anchor for cursor-
///                  affinity tests that care.
///   * `\«` / `\»` — literal `«` / `»`.
///
/// Inspired by `prosemirror-test-builder` / VS Code's editor tests —
/// the goal is for a 150-case file to read in one sitting.
struct EditorFixture: Hashable {
    let source: String
    let selection: NSRange
    /// `true` if the caret is at the start of `selection` (i.e. parsed
    /// from `«!text»`). For length-0 selections this is always `false`.
    let caretAtSelectionStart: Bool

    init(source: String,
         selection: NSRange,
         caretAtSelectionStart: Bool = false) {
        self.source = source
        self.selection = selection
        self.caretAtSelectionStart = caretAtSelectionStart
    }
}

extension EditorFixture {
    /// Decode an encoded string into a source + selection. Stable for
    /// arbitrary unicode in the source (operates on UTF-16 code units
    /// to match `NSTextStorage` / `NSRange` semantics).
    static func parse(_ encoded: String) -> EditorFixture {
        let ns = encoded as NSString
        let sourceBuffer = NSMutableString()
        var caretLocation: Int? = nil
        var selectionRange: NSRange? = nil
        var pendingSelectionStart: Int? = nil
        var caretAtStart = false
        var i = 0

        let pipe = UInt16(UnicodeScalar("|").value)
        let backslash = UInt16(UnicodeScalar("\\").value)
        let bang = UInt16(UnicodeScalar("!").value)
        let laquo: UInt16 = 0x00AB   // «
        let raquo: UInt16 = 0x00BB   // »

        while i < ns.length {
            let c = ns.character(at: i)

            // Escape: \| / \« / \»
            if c == backslash && i + 1 < ns.length {
                let next = ns.character(at: i + 1)
                if next == pipe || next == laquo || next == raquo {
                    sourceBuffer.append(NSString(characters: [next], length: 1) as String)
                    i += 2
                    continue
                }
            }

            switch c {
            case pipe:
                caretLocation = sourceBuffer.length
                i += 1
            case laquo:
                pendingSelectionStart = sourceBuffer.length
                if i + 1 < ns.length, ns.character(at: i + 1) == bang {
                    caretAtStart = true
                    i += 2
                } else {
                    i += 1
                }
            case raquo:
                if let start = pendingSelectionStart {
                    let end = sourceBuffer.length
                    selectionRange = NSRange(location: start, length: end - start)
                    pendingSelectionStart = nil
                } else {
                    sourceBuffer.append(NSString(characters: [c], length: 1) as String)
                }
                i += 1
            default:
                sourceBuffer.append(NSString(characters: [c], length: 1) as String)
                i += 1
            }
        }

        let finalSelection: NSRange
        if let range = selectionRange {
            finalSelection = range
        } else if let caret = caretLocation {
            finalSelection = NSRange(location: caret, length: 0)
        } else {
            finalSelection = NSRange(location: sourceBuffer.length, length: 0)
        }
        return EditorFixture(source: sourceBuffer as String,
                             selection: finalSelection,
                             caretAtSelectionStart: caretAtStart)
    }

    /// Encode a (source, selection) pair back to sentinel form.
    static func encode(source: String,
                       selection: NSRange,
                       caretAtSelectionStart: Bool = false) -> String {
        let ns = source as NSString
        let pre = ns.substring(with: NSRange(location: 0, length: selection.location))
        if selection.length == 0 {
            let post = ns.substring(from: selection.location)
            return pre + "|" + post
        }
        let mid = ns.substring(with: selection)
        let postStart = selection.location + selection.length
        let post = ns.substring(from: postStart)
        let opener = caretAtSelectionStart ? "«!" : "«"
        return pre + opener + mid + "»" + post
    }
}

extension EditorFixture {
    /// Drive an `EditorIntent` against an encoded input and assert
    /// the resulting encoded form. The dispatch goes through
    /// `EditorIntent.apply(to:selection:)`, the same path the
    /// production coordinator uses.
    static func expect(_ intent: EditorIntent,
                       from input: String,
                       produces expected: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let start = parse(input)
        let result = intent.apply(to: start.source, selection: start.selection)
        let actual = encode(source: result.source,
                            selection: result.selection)
        #expect(actual == expected,
                "Intent \(intent) on \"\(input)\" produced \"\(actual)\" (expected \"\(expected)\")",
                sourceLocation: sourceLocation)
    }
}
