import Foundation

/// Smallest changed range between two strings, in UTF-16 / NSString space — the
/// space `NSRange` and `UITextView.replace(_:withText:)` operate in.
///
/// The editor's pure transforms return a whole new `source` string; applying
/// that as one minimal edit through the text input layer (rather than replacing
/// the entire `textStorage`) keeps UIKit's tracking and the system UndoManager
/// consistent.
enum TextDiff {
    static func minimal(from old: String, to new: String) -> (range: NSRange, replacement: String) {
        // Compare complete grapheme clusters, while keeping their exact
        // UTF-16 spelling. Character equality alone treats canonically
        // equivalent accents as equal and could silently skip a source edit.
        var oldStart = old.startIndex
        var newStart = new.startIndex
        while oldStart < old.endIndex, newStart < new.endIndex,
              String(old[oldStart]).utf16.elementsEqual(String(new[newStart]).utf16) {
            old.formIndex(after: &oldStart)
            new.formIndex(after: &newStart)
        }

        var oldEnd = old.endIndex
        var newEnd = new.endIndex
        while oldEnd > oldStart, newEnd > newStart {
            let previousOld = old.index(before: oldEnd)
            let previousNew = new.index(before: newEnd)
            guard String(old[previousOld]).utf16.elementsEqual(String(new[previousNew]).utf16) else {
                break
            }
            oldEnd = previousOld
            newEnd = previousNew
        }

        return (
            NSRange(oldStart..<oldEnd, in: old),
            String(new[newStart..<newEnd])
        )
    }
}
