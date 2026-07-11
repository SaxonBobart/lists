import SwiftUI

struct QuickCaptureTitleSection: View {
    let leadingDecorationIcon: String
    let placeholder: String
    @Binding var title: String
    let titleFocused: FocusState<Bool>.Binding

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: leadingDecorationIcon)
                    .font(.title3)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 6) {
                    TextField(placeholder, text: $title)
                        .font(.title3)
                        .focused(titleFocused)
                        .lineLimit(1)
                        .submitLabel(.done)
                        .onSubmit { titleFocused.wrappedValue = false }
                        .onChange(of: title) { _, newValue in
                            let singleLine = newValue
                                .replacingOccurrences(of: "\n", with: " ")
                                .replacingOccurrences(of: "\r", with: " ")
                            if singleLine != newValue {
                                title = singleLine
                            }
                        }
                        .accessibilityIdentifier("quickcapture.title")
                }
            }
            .frame(minHeight: 32, alignment: .center)
            .padding(.vertical, 2)
        }
    }
}
