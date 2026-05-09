import SwiftUI
import UIKit

/// Color tokens derived from `design/Claude Design/project/tokens.css`.
/// Sage primary over warm-neutral surfaces. Light / dark variants per token.
enum ListsTokens {
    enum Foreground {
        static let primary   = Color(light: hex(0x2A2722), dark: hex(0xF6F5F1))
        static let secondary = Color(light: hex(0x686460), dark: hex(0xB8B6B2))
        static let tertiary  = Color(light: hex(0x989590), dark: hex(0x8E8C89))
        static let quaternary = Color(light: hex(0xC5C2BD), dark: hex(0x666461))
    }

    enum Background {
        static let grouped  = Color(light: hex(0xF5F3EE), dark: hex(0x1A1817))
        static let base     = Color(light: .white,         dark: hex(0x232120))
        static let elevated = Color(light: .white,         dark: hex(0x2A2826))
        static let surface2 = Color(light: hex(0xF3F1EC),  dark: hex(0x35332F))
        static let tinted   = Color(light: hex(0xF0F4EA),  dark: hex(0x293224))
    }

    enum Separator {
        static let opaque      = Color(light: hex(0xE2E0DC), dark: hex(0x464441))
        static let translucent = Color(light: Color.black.opacity(0.12),
                                       dark:  Color.white.opacity(0.18))
    }

    /// Sage accent — the "this app is X color" identity color.
    static let accent      = Color(light: hex(0x5B7553), dark: hex(0x91B189))
    static let accentSoft  = accent.opacity(0.12)
    static let accentPress = Color(light: hex(0x4A6643), dark: hex(0xA8C49E))
    static let accentTintBg = Color(light: hex(0xE8EFE0), dark: hex(0x3A4733))
    static let accentTintFg = Color(light: hex(0x3D5237), dark: hex(0xCDE2C2))

    enum Semantic {
        static let warning = Color(light: hex(0xC79024), dark: hex(0xE5B046))
        static let danger  = Color(light: hex(0xC2452D), dark: hex(0xE4644E))
        static let info    = Color(light: hex(0x4F77B6), dark: hex(0x82A4D6))
        static let success = Color(light: hex(0x5B8553), dark: hex(0x96C28C))
    }

    /// List icon hue palette (for sidebar list dots / tile fills).
    enum Hue {
        static let blue   = Color(light: hex(0x4F77B6), dark: hex(0x82A4D6))
        static let teal   = Color(light: hex(0x4F9DA8), dark: hex(0x83BFC6))
        static let green  = Color(light: hex(0x5B8553), dark: hex(0x96C28C))
        static let amber  = Color(light: hex(0xC79024), dark: hex(0xE5B046))
        static let orange = Color(light: hex(0xCB7233), dark: hex(0xE49452))
        static let pink   = Color(light: hex(0xCD6678), dark: hex(0xE08FA0))
        static let purple = Color(light: hex(0x8657A5), dark: hex(0xAE83C5))
        static let grey   = Color(light: hex(0x989590), dark: hex(0x9C9994))
    }

    /// Habit heatmap progression — sage from empty to full.
    enum Heatmap {
        static let empty   = Color(light: hex(0xEFEDE7), dark: hex(0x35332F))
        static let level1  = Color(light: hex(0xDCE6D2), dark: hex(0x40543A))
        static let level2  = Color(light: hex(0xB6C9A4), dark: hex(0x6B8C5F))
        static let level3  = Color(light: hex(0x8AAB7A), dark: hex(0x86A678))
        static let level4  = accent
    }
}

private func hex(_ rgb: UInt32) -> Color {
    let r = Double((rgb >> 16) & 0xFF) / 255.0
    let g = Double((rgb >>  8) & 0xFF) / 255.0
    let b = Double( rgb        & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

extension Color {
    /// Pick a different sRGB color per system color scheme (light vs dark).
    init(light: Color, dark: Color) {
        self = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
