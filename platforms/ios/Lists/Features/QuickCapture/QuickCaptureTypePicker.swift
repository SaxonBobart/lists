import SwiftUI

struct QuickCaptureTypePicker: View {
    @Binding var selection: Item.ItemType

    var body: some View {
        Picker("Type", selection: $selection) {
            ForEach(Item.ItemType.allCases, id: \.self) { type in
                Text(type.documentDisplayName)
                    .tag(type)
                    .accessibilityIdentifier("quickcapture.type.\(type.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

}
