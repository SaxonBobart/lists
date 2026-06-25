import SwiftUI

struct QuickCaptureTypePicker: View {
    @Binding var selection: Item.ItemType
    let habitsPluginEnabled: Bool

    var body: some View {
        Picker("Type", selection: $selection) {
            ForEach(itemTypePolicy.quickCaptureTypes, id: \.self) { type in
                Text(type.documentDisplayName)
                    .tag(type)
                    .accessibilityIdentifier("quickcapture.type.\(type.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }
}
