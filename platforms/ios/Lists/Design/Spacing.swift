import SwiftUI

/// 4pt-base spacing scale. Use Apple's HIG defaults wherever possible;
/// these constants are for cases where you need an explicit, consistent
/// value across screens.
enum ListsSpacing {
    static let s1: CGFloat =  4
    static let s2: CGFloat =  8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 40
    static let s9: CGFloat = 48
}

enum ListsRadius {
    static let sm:   CGFloat =   6
    static let md:   CGFloat =  10
    static let lg:   CGFloat =  14
    static let xl:   CGFloat =  20
    static let card: CGFloat =  16
    static let row:  CGFloat =   8
    static let pill: CGFloat = 999
}

/// Per-row density tokens — ported from the old app's `Design/Tokens/RowMetrics`.
/// Apple Reminders has a tight, baseline-aligned row; replicating it requires
/// removing SwiftUI's 44pt minimum row height and controlling vertical
/// spacing exclusively via `listRowInsets`.
enum RowMetrics {
    static let insets = EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
    static let leadingSpacing: CGFloat = 12
    static let iconBaselineOffset: CGFloat = 4
}

/// Comfortable density values (default). Compact / Cozy variants TBD when
/// density toggle ships.
enum ListsDensity {
    static let rowHeight:  CGFloat = 56
    static let rowPadY:    CGFloat = 10
    static let rowPadX:    CGFloat = 16
    static let rowGap:     CGFloat = 10
    static let sectionPad: CGFloat = 10
}

extension View {
    /// Tight reminder-row padding; no inter-row hairlines (Apple Reminders
    /// uses section breaks for visual structure, not row dividers).
    func reminderRowDensity() -> some View {
        self
            .listRowInsets(RowMetrics.insets)
            .listRowSeparator(.hidden)
    }

    /// Plain list, zero section spacing, no minimum row height. Apply to
    /// every `List` that displays reminder rows.
    func reminderListDensity() -> some View {
        self
            .listStyle(.plain)
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// Baseline-align a leading icon to the first line of text. Pair with
    /// `HStack(alignment: .firstTextBaseline)`.
    func reminderIconBaseline() -> some View {
        self.alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center] + RowMetrics.iconBaselineOffset
        }
    }
}
