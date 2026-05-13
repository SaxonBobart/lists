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
                        movingForward: Bool) -> Int {
        let ns = source as NSString
        guard location >= 0 else { return 0 }
        guard location <= ns.length else { return ns.length }
        // `lineRange` requires a valid index; if location == length we
        // probe the last char instead.
        let probe = min(location, max(0, ns.length - 1))
        let lineRange = ns.lineRange(for: NSRange(location: probe, length: 0))
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
        if movingForward {
            return lineRange.location + marker.contentStart
        }
        // Backward: end of previous line content. First line clamps
        // forward (no prev to jump to).
        guard lineRange.location > 0 else {
            return lineRange.location + marker.contentStart
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
        let probe = min(caret, max(0, ns.length - 1))
        guard ns.length > 0 else { return (source, selection) }
        let currentLine = ns.lineRange(for: NSRange(location: probe, length: 0))

        let targetLineStart: Int
        if direction == .up {
            guard currentLine.location > 0 else { return (source, selection) }
            targetLineStart = currentLine.location - 1
        } else {
            let next = currentLine.location + currentLine.length
            guard next < ns.length else { return (source, selection) }
            targetLineStart = next
        }
        let targetLine = ns.lineRange(for: NSRange(location: targetLineStart, length: 0))

        let currentRaw = ns.substring(with: currentLine)
        let currentContent = currentRaw.hasSuffix("\n") ? String(currentRaw.dropLast()) : currentRaw
        let currentMarker = ListMarker.detect(in: currentContent)
        let currentMarkerLen = currentMarker?.contentStart ?? 0

        let targetRaw = ns.substring(with: targetLine)
        let targetContent = targetRaw.hasSuffix("\n") ? String(targetRaw.dropLast()) : targetRaw
        let targetMarker = ListMarker.detect(in: targetContent)
        let targetMarkerLen = targetMarker?.contentStart ?? 0
        let targetContentLength = (targetContent as NSString).length - targetMarkerLen

        let offsetInCurrent = caret - currentLine.location
        let currentContentLength = (currentContent as NSString).length - currentMarkerLen
        let currentContentCol = max(0, offsetInCurrent - currentMarkerLen)

        let targetContentCol: Int
        if currentContentCol >= currentContentLength {
            // At end-of-content on source — preserve to end-of-content on target.
            targetContentCol = targetContentLength
        } else {
            targetContentCol = min(currentContentCol, targetContentLength)
        }
        let newCaret = targetLine.location + targetMarkerLen + targetContentCol
        return (source, NSRange(location: newCaret, length: 0))
    }
}
