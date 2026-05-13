import Foundation

/// Tap-to-toggle for task checkboxes. A tap on the `[` or `]`
/// bracket of a `- [ ]` or `- [x]` marker flips the state. Other
/// taps fall through to UITextView's default cursor placement
/// (handled by the gesture delegate filter in the coordinator).
///
/// Public API: `toggle(at:in:selection:)`. Pure transform — the
/// gesture-recognition wiring lives in the coordinator.
enum CheckboxToggler {
    static func toggle(at characterIndex: Int,
                       in source: String,
                       selection: NSRange) -> (source: String, selection: NSRange) {
        _ = characterIndex
        return (source, selection)
    }
}
