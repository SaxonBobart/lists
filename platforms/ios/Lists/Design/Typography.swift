import SwiftUI

/// Type scale derived from `design/Claude Design/project/tokens.css`.
/// SF Pro Rounded for UI text, SF Mono for metadata (timestamps, tags).
enum ListsTypography {
    static let largeTitle  = Font.system(size: 34, weight: .bold,      design: .rounded)
    static let title1      = Font.system(size: 28, weight: .bold,      design: .rounded)
    static let title2      = Font.system(size: 22, weight: .bold,      design: .rounded)
    static let title3      = Font.system(size: 20, weight: .semibold,  design: .rounded)
    static let headline    = Font.system(size: 17, weight: .semibold,  design: .rounded)
    static let body        = Font.system(size: 17, weight: .regular,   design: .rounded)
    static let callout     = Font.system(size: 16, weight: .regular,   design: .rounded)
    static let subheadline = Font.system(size: 15, weight: .regular,   design: .rounded)
    static let footnote    = Font.system(size: 13, weight: .regular,   design: .rounded)
    static let caption1    = Font.system(size: 12, weight: .regular,   design: .rounded)
    static let caption2    = Font.system(size: 11, weight: .medium,    design: .rounded)

    /// Monospaced — for timestamps, tags, counts. Tabular figures.
    static let mono        = Font.system(size: 13, weight: .regular, design: .monospaced)
        .monospacedDigit()
    static let monoSmall   = Font.system(size: 11, weight: .regular, design: .monospaced)
        .monospacedDigit()
}
