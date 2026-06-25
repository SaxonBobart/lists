import SwiftUI

struct QuickCaptureTypePicker: View {
    @Binding var selection: Item.ItemType
    let habitsPluginEnabled: Bool

    var body: some View {
        Picker("Type", selection: $selection) {
            Text("Task")
                .tag(Item.ItemType.task)
                .accessibilityIdentifier("quickcapture.type.task")
            Text("Note")
                .tag(Item.ItemType.note)
                .accessibilityIdentifier("quickcapture.type.note")
            Text("Event")
                .tag(Item.ItemType.event)
                .accessibilityIdentifier("quickcapture.type.event")
            if habitsPluginEnabled {
                Text("Habit")
                    .tag(Item.ItemType.habit)
                    .accessibilityIdentifier("quickcapture.type.habit")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
