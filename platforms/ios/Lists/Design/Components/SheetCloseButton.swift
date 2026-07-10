import SwiftUI

struct SheetCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(accessibilityLabel: String = "Close", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .glassEffect(.regular, in: Circle())
                .contentShape(Circle())
                .accessibilityLabel(accessibilityLabel)
        }
        .buttonStyle(.plain)
    }
}
