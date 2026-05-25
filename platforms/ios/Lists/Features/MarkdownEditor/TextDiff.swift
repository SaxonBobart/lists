import Foundation

/// Smallest changed range between two strings, in UTF-16 / NSString space — the
/// space `NSRange` and `UITextView.replace(_:withText:)` operate in.
///
/// The editor's pure transforms return a whole new `source` string; applying
/// that as one minimal edit through the text input layer (rather than replacing
/// the entire `textStorage`) keeps UIKit's tracking and the system UndoManager
/// consistent (ED-1).
enum TextDiff {
    static func minimal(from old: String, to new: String) -> (range: NSRange, replacement: String) {
        let o = old as NSString, n = new as NSString
        let oLen = o.length, nLen = n.length

        var prefix = 0
        let maxPrefix = min(oLen, nLen)
        while prefix < maxPrefix, o.character(at: prefix) == n.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        let maxSuffix = min(oLen, nLen) - prefix
        while suffix < maxSuffix,
              o.character(at: oLen - 1 - suffix) == n.character(at: nLen - 1 - suffix) {
            suffix += 1
        }

        let range = NSRange(location: prefix, length: oLen - prefix - suffix)
        let replacement = n.substring(with: NSRange(location: prefix, length: nLen - prefix - suffix))
        return (range, replacement)
    }
}
