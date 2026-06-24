import SwiftUI

/// Right-side gray nav chevron used where the row owns navigation. Matches the
/// 30pt column used by expandable rows so edges line up.
struct DecorativeChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}
