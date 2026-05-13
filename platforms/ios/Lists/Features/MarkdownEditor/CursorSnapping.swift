import Foundation

/// Phantom marker zones: list / task / blockquote marker prefixes
/// (`- `, `- [ ] `, `> `) are not valid cursor positions. If the
/// caret lands inside one, snap past it in the direction of motion.
///
/// Also owns column-tracking for Up/Down arrow movement so the
/// caret-column maps to the *source* column (post-marker), not the
/// visual column (which is affected by glyph hiding).
///
/// Public API: `move(direction:modifiers:in:selection:)`. Pure
/// transform; the coordinator translates `UIKeyCommand` /
/// `UITextViewDelegate` selection-change callbacks into a call here.
enum CursorSnapping {
    static func move(direction: MoveDirection,
                     modifiers: MoveModifiers,
                     in source: String,
                     selection: NSRange) -> (source: String, selection: NSRange) {
        // Stub: passthrough. The coordinator currently lets UIKit
        // own arrow-key motion; the L3 + L1 corpora pin down where
        // we need to override.
        _ = direction
        _ = modifiers
        return (source, selection)
    }

    /// Snap a caret position that landed inside a marker-zone to a
    /// reachable position. Called from `textViewDidChangeSelection`
    /// in P3 onwards. Stub returns the location unchanged.
    static func snapped(_ location: Int,
                        in source: String,
                        movingForward: Bool) -> Int {
        _ = source
        _ = movingForward
        return location
    }
}
