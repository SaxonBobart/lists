import SwiftUI

/// 4pt-base spacing scale derived from `design/Claude Design/project/tokens.css`.
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

/// Comfortable density values (default). Compact / Cozy variants TBD when
/// density toggle ships.
enum ListsDensity {
    static let rowHeight:  CGFloat = 56
    static let rowPadY:    CGFloat = 10
    static let rowPadX:    CGFloat = 16
    static let rowGap:     CGFloat = 10
    static let sectionPad: CGFloat = 10
}
