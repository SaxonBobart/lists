import UIKit
import SnapshotTesting

/// Shared device + trait helpers for snapshot tests.
///
/// swift-snapshot-testing's built-in `ViewImageConfig` presets lag iOS
/// device releases. `.iPhone13Pro` and `.iPhoneSe` are the closest stable
/// presets to "modern iPhone" and "compact iPhone" layouts. Re-record
/// references when the simulator iOS version changes — see
/// SnapshotTests/README.md.
enum SnapshotEnvironment {
    /// Fixed-size view snapshots need explicit traits too; otherwise they can
    /// inherit simulator appearance and scale.
    @MainActor
    static var fixedLightTraits: UITraitCollection {
        UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = .light
            mutableTraits.displayScale = 3
        }
    }

    /// Standard portrait iPhone, light mode, default dynamic type.
    ///
    /// The interface style is forced to `.light` — the bare device presets
    /// inherit whatever appearance the simulator happens to be in, which made
    /// "Light" baselines drift between recording sessions. Explicit `traits:`
    /// passed at the call site (e.g. `darkTraits`) still win: the library
    /// merges `[config.traits, traits]` with the latter taking precedence.
    static let iPhone16Light = forcingLight(ViewImageConfig.iPhone13Pro)

    /// Compact iPhone, light mode, default dynamic type.
    static let iPhoneSeLight = forcingLight(ViewImageConfig.iPhoneSe)

    private static func forcingLight(_ config: ViewImageConfig) -> ViewImageConfig {
        var config = config
        config.traits = config.traits.modifyingTraits { mutableTraits in
            mutableTraits.userInterfaceStyle = .light
        }
        return config
    }

    /// Dark-mode trait collection — combine with a ViewImageConfig.
    static let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

    /// Accessibility-extra-large dynamic type. Catches layout breakage at
    /// real-world large-text settings.
    static let a11yLargeTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
}
