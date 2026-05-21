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
    /// Standard portrait iPhone, light mode, default dynamic type.
    static let iPhone16Light = ViewImageConfig.iPhone13Pro

    /// Compact iPhone, light mode, default dynamic type.
    static let iPhoneSeLight = ViewImageConfig.iPhoneSe

    /// Dark-mode trait collection — combine with a ViewImageConfig.
    static let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

    /// Accessibility-extra-large dynamic type. Catches layout breakage at
    /// real-world large-text settings.
    static let a11yLargeTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
}
