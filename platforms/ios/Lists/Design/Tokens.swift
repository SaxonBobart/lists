import SwiftUI

/// Color tokens. Built on top of SwiftUI's semantic palette
/// (`.primary`, `.systemGroupedBackground`, `.accentColor`, etc.) so the
/// app feels native — no warm-neutral custom palette in v1.
enum ListsTokens {

    // MARK: - Per-list / per-smart-list accent

    /// User-pickable accent color for a list — mapped to a system color.
    static func listColor(_ c: ItemList.ListColor) -> Color {
        switch c {
        case .sage:   return .green
        case .blue:   return .blue
        case .teal:   return .teal
        case .green:  return .mint
        case .amber:  return .yellow
        case .orange: return .orange
        case .pink:   return .pink
        case .purple: return .purple
        case .grey:   return .gray
        }
    }

    /// Smart-list accent color — follows Claude Design hue intent in
    /// system equivalents.
    static func smartColor(_ s: SmartList) -> Color {
        switch s {
        case .today:     return .yellow
        case .scheduled: return .orange
        case .flagged:   return .pink
        case .urgent:    return .red
        case .completed: return .gray
        case .all:       return .green
        }
    }

    // MARK: - Foreground (system semantic labels)

    enum Foreground {
        static let primary: Color    = .primary
        static let secondary: Color  = .secondary
        static let tertiary: Color   = Color(.tertiaryLabel)
        static let quaternary: Color = Color(.quaternaryLabel)
    }

    // MARK: - Background / surface (system materials)

    enum Background {
        static let grouped: Color  = Color(.systemGroupedBackground)
        static let base: Color     = Color(.systemBackground)
        static let elevated: Color = Color(.secondarySystemGroupedBackground)
        static let surface2: Color = Color(.tertiarySystemFill)
        static let tinted: Color   = Color.accentColor.opacity(0.12)
    }

    enum Separator {
        static let opaque: Color      = Color(.separator)
        static let translucent: Color = Color(.separator).opacity(0.7)
    }

    // MARK: - Accent

    static let accent: Color        = .accentColor
    static let accentSoft: Color    = Color.accentColor.opacity(0.12)
    static let accentPress: Color   = Color.accentColor.opacity(0.8)
    static let accentTintBg: Color  = Color.accentColor.opacity(0.15)
    static let accentTintFg: Color  = .accentColor

    // MARK: - List icon hue palette (system colors)

    enum Hue {
        static let blue: Color   = .blue
        static let teal: Color   = .teal
        static let green: Color  = .mint
        static let amber: Color  = .yellow
        static let orange: Color = .orange
        static let pink: Color   = .pink
        static let purple: Color = .purple
        static let grey: Color   = .gray
    }

    // MARK: - Semantic

    enum Semantic {
        static let warning: Color = .orange
        static let danger: Color  = .red
        static let info: Color    = .blue
        static let success: Color = .green
    }

    // MARK: - Habit heatmap (accent progression)

    enum Heatmap {
        static let empty: Color  = Color(.tertiarySystemFill)
        static let level1: Color = Color.accentColor.opacity(0.25)
        static let level2: Color = Color.accentColor.opacity(0.50)
        static let level3: Color = Color.accentColor.opacity(0.75)
        static let level4: Color = .accentColor
    }
}
