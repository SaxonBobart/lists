import Foundation

/// Tab / Shift-Tab indent and outdent.
///
/// Both always operate on the current line (not the caret position
/// within the line). Tab inserts 4 spaces at line start; Shift-Tab
/// removes up to 4 leading spaces.
///
/// Multi-line selections indent every line touched by the selection
/// and the selection extends to cover the new boundaries.
///
/// Pure transform. `(source, selection) -> (source, selection)`.
enum IndentHandler {

    private static let indentWidth = 4
    private static let indentString = "    "

    static func indent(source: String,
                       selection: NSRange) -> (source: String, selection: NSRange) {
        let lines = linesTouched(by: selection, in: source)
        return apply(insertingFourSpacesAt: lines, source: source, selection: selection)
    }

    static func outdent(source: String,
                        selection: NSRange) -> (source: String, selection: NSRange) {
        let lines = linesTouched(by: selection, in: source)
        return apply(removingLeadingSpacesAt: lines, source: source, selection: selection)
    }

    // MARK: Implementation

    /// Returns the line start indices for every line touched by the
    /// selection. Single-caret returns one index; multi-line
    /// selection returns each line's start.
    private static func linesTouched(by selection: NSRange,
                                     in source: String) -> [Int] {
        let ns = source as NSString
        var lineStarts: [Int] = []
        let firstLine = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        lineStarts.append(firstLine.location)
        let end = max(selection.location, selection.location + selection.length - 1)
        var cursor = firstLine.location + firstLine.length
        while cursor <= end, cursor < ns.length {
            let lr = ns.lineRange(for: NSRange(location: cursor, length: 0))
            lineStarts.append(lr.location)
            cursor = lr.location + lr.length
        }
        return lineStarts
    }

    private static func apply(insertingFourSpacesAt lineStarts: [Int],
                              source: String,
                              selection: NSRange) -> (source: String, selection: NSRange) {
        var result = source as NSString
        // Process in ASCENDING order, tracking the cumulative shift so
        // the indices stay valid as we lengthen the string.
        var shift = 0
        for start in lineStarts.sorted() {
            let insertAt = start + shift
            result = result.replacingCharacters(in: NSRange(location: insertAt, length: 0),
                                                with: indentString) as NSString
            shift += indentWidth
        }
        let newLocation = selection.location + indentWidth   // first-line shift covers caret
        var newLength = selection.length
        // If the selection spans multiple lines, every additional line
        // contributes another `indentWidth` to the selection length.
        if lineStarts.count > 1 {
            newLength += indentWidth * (lineStarts.count - 1)
        }
        return (result as String, NSRange(location: newLocation, length: newLength))
    }

    private static func apply(removingLeadingSpacesAt lineStarts: [Int],
                              source: String,
                              selection: NSRange) -> (source: String, selection: NSRange) {
        var result = source as NSString
        var shift = 0
        var caretAdjustments: (firstLineRemoved: Int, totalRemoved: Int) = (0, 0)
        for (idx, start) in lineStarts.sorted().enumerated() {
            let lineStart = start - shift  // wait — we ADJUST for prior removals
            let adjustedStart = start - shift
            // Count up to 4 leading spaces on this line in the current `result`.
            var spaces = 0
            var i = adjustedStart
            while i < result.length, spaces < indentWidth,
                  result.character(at: i) == 0x20 {
                spaces += 1
                i += 1
            }
            if spaces > 0 {
                result = result.replacingCharacters(
                    in: NSRange(location: adjustedStart, length: spaces),
                    with: "") as NSString
                shift += spaces
                if idx == 0 {
                    caretAdjustments.firstLineRemoved = spaces
                }
                caretAdjustments.totalRemoved += spaces
            }
            _ = lineStart   // keep the local var visible if we ever debug
        }
        let firstLineStart = (lineStarts.min() ?? 0)
        // Caret: clamp to firstLineStart if it was inside the removed spaces,
        // otherwise shift left by firstLineRemoved.
        let originalCaret = selection.location
        let newCaretLoc: Int
        if originalCaret < firstLineStart + caretAdjustments.firstLineRemoved {
            newCaretLoc = firstLineStart
        } else {
            newCaretLoc = originalCaret - caretAdjustments.firstLineRemoved
        }
        let newLength = max(0, selection.length - (caretAdjustments.totalRemoved - caretAdjustments.firstLineRemoved))
        return (result as String, NSRange(location: newCaretLoc, length: newLength))
    }
}
