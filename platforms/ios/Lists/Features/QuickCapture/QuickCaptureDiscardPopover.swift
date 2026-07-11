import SwiftUI

/// Apple Reminders-style discard popover: title prompt and a single centered
/// destructive pill button. Tap-outside dismisses naturally because
/// `SheetDismissInterceptor` releases `isModalInPresentation` while this
/// popover is open.
struct QuickCaptureDiscardPopover: View {
    let title: String
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDiscard) {
                Text("Discard Changes")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickcapture.discard.confirm")
        }
        .padding(16)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }
}
