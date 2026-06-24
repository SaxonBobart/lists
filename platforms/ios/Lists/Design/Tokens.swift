import SwiftUI

/// Color tokens. Built on top of SwiftUI's semantic palette
/// (`.primary`, `.systemGroupedBackground`, `.accentColor`, etc.) so the
/// app feels native — no warm-neutral custom palette in v1.
///
/// **Brand color:** `ListsTokens.brand` (#44D7A8) — a soft mint-teal used by
/// the default Inbox list and reserved as the app's signature hue. New
/// brand-marked surfaces (logo, splash, marketing) should pull from here.
enum ListsTokens {

    // MARK: - Brand

    /// Lists' signature mint-teal (#44D7A8). Default Inbox color.
    static let brand: Color = Color(red: 68 / 255, green: 215 / 255, blue: 168 / 255)

    // MARK: - Per-list / per-smart-list accent

    /// User-pickable accent color for a list — mapped to a system color.
    /// `.sage` resolves to the brand mint so the default Inbox carries the
    /// brand identity.
    static func listColor(_ c: ItemList.ListColor) -> Color {
        switch c {
        case .sage:   return brand
        case .blue:   return .blue
        case .teal:   return Color(red: 0.55, green: 0.78, blue: 0.94)   // soft sky
        case .green:  return .mint
        case .amber:  return .yellow
        case .orange: return .orange
        case .pink:   return .pink
        case .purple: return .purple
        case .grey:   return Color(red: 0.49, green: 0.55, blue: 0.62)   // slate
        case .red:    return .red
        case .indigo: return .indigo
        case .brown:  return Color(red: 0.78, green: 0.62, blue: 0.45)   // tan
        }
    }

    /// User-facing palette ordering for the list-color picker.
    /// 7 + 5 grid matching the New List sheet design.
    static let listColorPalette: [ItemList.ListColor] = [
        .red, .orange, .amber, .green, .teal, .blue, .indigo,
        .pink, .purple, .brown, .grey, .sage
    ]

    /// Auto-list accent color — Scheduled keeps Apple Reminders' system red;
    /// Urgent uses a softer dusty red so the two stay visually distinct.
    static func smartColor(_ s: SmartList) -> Color {
        switch s {
        case .today:     return .blue
        case .scheduled: return .red
        case .flagged:   return .orange
        case .urgent:    return Color(red: 0.93, green: 0.45, blue: 0.45)
        case .completed: return .gray
        case .all:       return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? .systemGray2 : .darkGray
        })
        case .tags:      return tagAccent
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
    //
    // Default app tint is system blue. Governs neutral controls (buttons,
    // links, plus icons, swipe-action tints). Colored smart-list tiles and
    // list icons keep their own hues.

    static let accent: Color        = .blue
    static let accentSoft: Color    = Color.blue.opacity(0.10)
    static let accentPress: Color   = Color.blue.opacity(0.6)
    static let accentTintBg: Color  = Color.blue.opacity(0.10)
    static let accentTintFg: Color  = .blue

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

    /// Dusty purple-blue used by the Tags pseudo-list icon in the sidebar
    /// (and the Edit Lists sheet). Same colour applied to inline `#tag`
    /// text in `ItemRow` so the tag glyph and text read as a unit.
    static let tagAccent: Color = Color(red: 0x6A / 255.0, green: 0x84 / 255.0, blue: 0xB8 / 255.0)

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
