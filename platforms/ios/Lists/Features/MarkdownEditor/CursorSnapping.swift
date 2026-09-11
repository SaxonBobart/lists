import Foundation

/// Phantom marker zones + arrow-key column tracking.
///
/// Phantom zones: list / task / blockquote marker prefixes (`- `,
/// `- [ ] `, `> `) are not valid cursor positions. The coordinator
/// calls `snapped(_:in:movingForward:)` from
/// `textViewDidChangeSelection` to push the caret out of a zone in
/// the direction of motion.
///
/// Up / Down arrows use **content-column tracking**: the column is
/// measured relative to the line's content start (post-marker). If
/// the source caret was at end of content, the target also lands at
/// end of content (so `- alpha\n- beta|` + Up gives `- alpha|`).
/// All other columns map directly, clamping to the target line's
/// content length when the target is shorter.
enum CursorSnapping {
    static func move(direction: MoveDirection,
                     modifiers: MoveModifiers,
                     in source: String,
                     selection: NSRange) -> (source: String, selection: NSRange) {
        switch direction {
        case .up:   return verticalMove(.up, in: source, selection: selection)
        case .down: return verticalMove(.down, in: source, selection: selection)
        default:
            // Left / Right / Home / End fall through to UIKit's default
            // motion. CursorSnapping only adds smart behaviour where
            // markers cause visual / source column mismatch.
            _ = modifiers
            return (source, selection)
        }
    }

    static func snapped(_ location: Int,
                        in source: String,
                        movingForward: Bool,
                        sameLineMovement: Bool = true) -> Int {
        let ns = source as NSString
        guard location >= 0 else { return 0 }
        guard location <= ns.length else { return ns.length }
        if MarkdownFenceSyntax.blocks(in: source).contains(where: {
            NSLocationInRange(location, $0.fullRange)
                || (!$0.isClosed && location == NSMaxRange($0.fullRange))
        }) { return location }
        let lineRange = Self.lineRange(containingCaret: location, in: ns)
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard let marker = ListMarker.detect(in: lineContent) else {
            return location
        }
        let lineOffset = location - lineRange.location
        // In-zone if offset is before content-start (covers the marker
        // chars + the leading-whitespace bullet glyph at offset 0).
        guard lineOffset < marker.contentStart else {
            return location
        }
        // Tap-style selection change (caret jumped from another line):
        // always land at this line's content start. Direction inference
        // is only meaningful for in-line arrow movement.
        if !sameLineMovement {
            return lineRange.location + marker.contentStart
        }
        if movingForward {
            return lineRange.location + marker.contentStart
        }
        // Backward: end of previous line content. On the first line, expose
        // absolute source position zero so another Left can sit before the
        // marker and Return can insert a normal paragraph above the block.
        guard lineRange.location > 0 else {
            return 0
        }
        let prevLineRange = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        let prevRaw = ns.substring(with: prevLineRange)
        let prevContent = prevRaw.hasSuffix("\n") ? String(prevRaw.dropLast()) : prevRaw
        return prevLineRange.location + (prevContent as NSString).length
    }

    private static func verticalMove(_ direction: MoveDirection,
                                     in source: String,
                                     selection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let caret = selection.location
        guard ns.length > 0 else { return (source, selection) }
        let currentLine = Self.lineRange(containingCaret: caret, in: ns)

        let targetLineStart: Int
        if direction == .up {
            guard currentLine.location > 0 else { return (source, selection) }
            targetLineStart = currentLine.location - 1
        } else {
            guard currentLine.location < ns.length else { return (source, selection) }
            let next = currentLine.location + currentLine.length
            guard next < ns.length || Self.isTrailingEmptyLineStart(next, in: ns) else {
                return (source, selection)
            }
            targetLineStart = next
        }
        let targetLine = Self.lineRange(containingCaret: targetLineStart, in: ns)

        let currentRaw = ns.substring(with: currentLine)
        let currentContent = currentRaw.hasSuffix("\n") ? String(currentRaw.dropLast()) : currentRaw
        let literalRanges = MarkdownFenceSyntax.blocks(in: source).map(\.fullRange)
        let currentMarker = literalRanges.contains(where: { NSLocationInRange(currentLine.location, $0) })
            ? nil : ListMarker.detect(in: currentContent)
        let currentMarkerLen = currentMarker?.contentStart ?? 0

        let targetRaw = ns.substring(with: targetLine)
        let targetContent = targetRaw.hasSuffix("\n") ? String(targetRaw.dropLast()) : targetRaw
        let targetMarker = literalRanges.contains(where: { NSLocationInRange(targetLine.location, $0) })
            ? nil : ListMarker.detect(in: targetContent)
        let targetMarkerLen = targetMarker?.contentStart ?? 0
        let currentBoundaries = characterBoundaries(in: currentContent, after: currentMarkerLen)
        let targetBoundaries = characterBoundaries(in: targetContent, after: targetMarkerLen)
        let currentOffset = max(0, caret - currentLine.location - currentMarkerLen)
        let targetOffset: Int
        if currentOffset >= (currentBoundaries.last ?? 0) {
            // At end-of-content on source — preserve to end-of-content on target.
            targetOffset = targetBoundaries.last ?? 0
        } else {
            // Track visible characters rather than UTF-16 units. The latter
            // can put the next caret inside an emoji or combining sequence.
            let column = max(0, currentBoundaries.lastIndex(where: { $0 <= currentOffset }) ?? 0)
            targetOffset = targetBoundaries[min(column, targetBoundaries.count - 1)]
        }
        let newCaret = targetLine.location + targetMarkerLen + targetOffset
        return (source, NSRange(location: newCaret, length: 0))
    }

    private static func characterBoundaries(in line: String, after markerLength: Int) -> [Int] {
        let content = (line as NSString).substring(from: markerLength)
        var offsets = [0]
        var offset = 0
        for character in content {
            offset += String(character).utf16.count
            offsets.append(offset)
        }
        return offsets
    }

    private static func lineRange(containingCaret caret: Int, in ns: NSString) -> NSRange {
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let clampedCaret = min(max(0, caret), ns.length)
        if Self.isTrailingEmptyLineStart(clampedCaret, in: ns) {
            return NSRange(location: ns.length, length: 0)
        }
        let probe = min(clampedCaret, ns.length - 1)
        return ns.lineRange(for: NSRange(location: probe, length: 0))
    }

    private static func isTrailingEmptyLineStart(_ location: Int, in ns: NSString) -> Bool {
        location == ns.length &&
        ns.length > 0 &&
        ns.character(at: ns.length - 1) == 10
    }
}
