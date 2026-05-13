import Foundation

/// Tap-to-toggle for task checkboxes. The gesture-recognition wiring
/// (`UITapGestureRecognizer` + delegate filter) lives in the
/// coordinator; this enum is the pure transform that figures out
/// which bracket character to flip given a source position.
///
/// A "valid" tap lands anywhere on the `[ ]` / `[x]` / `[X]` triplet
/// — bracket open, state char, or bracket close. Taps outside that
/// (or on a line whose marker isn't a task) are no-ops.
enum CheckboxToggler {
    static func toggle(at characterIndex: Int,
                       in source: String,
                       selection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        guard characterIndex >= 0, characterIndex < ns.length else {
            return (source, selection)
        }
        let lineRange = ns.lineRange(for: NSRange(location: characterIndex, length: 0))
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard let marker = ListMarker.detect(in: lineContent),
              case .task(let checked) = marker.kind else {
            return (source, selection)
        }
        // Bracket positions within the line:
        //   `[ ]` triplet starts at indent + 2, ends at indent + 4.
        let lineOffset = characterIndex - lineRange.location
        let bracketOpen = marker.indent + 2
        let bracketClose = marker.indent + 4
        guard lineOffset >= bracketOpen, lineOffset <= bracketClose else {
            return (source, selection)
        }
        let statePos = lineRange.location + marker.indent + 3
        let newState = checked ? " " : "x"
        let replaceRange = NSRange(location: statePos, length: 1)
        let newSource = ns.replacingCharacters(in: replaceRange, with: newState)
        return (newSource, selection)
    }
}
