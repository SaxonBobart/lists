import SwiftUI

/// Type scale — pass-throughs to SwiftUI's built-in dynamic-type styles
/// so the app participates in system text-sizing automatically. Use these
/// or the SwiftUI styles directly (`.font(.body)`); both work.
enum ListsTypography {
    static let largeTitle  = Font.largeTitle
    static let title1      = Font.title
    static let title2      = Font.title2
    static let title3      = Font.title3
    static let headline    = Font.headline
    static let body        = Font.body
    static let callout     = Font.callout
    static let subheadline = Font.subheadline
    static let footnote    = Font.footnote
    static let caption1    = Font.caption
    static let caption2    = Font.caption2

    /// Tabular monospaced digits, for counts and timestamps.
    static let mono      = Font.system(.footnote, design: .monospaced).monospacedDigit()
    static let monoSmall = Font.system(.caption2, design: .monospaced).monospacedDigit()
}
