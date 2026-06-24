import SwiftUI

struct QuickCaptureTypePicker: View {
    @Binding var selection: Item.ItemType

    var body: some View {
        Picker("Type", selection: $selection) {
            Text("Task")
                .tag(Item.ItemType.task)
                .accessibilityIdentifier("quickcapture.type.task")
            Text("Note")
                .tag(Item.ItemType.note)
                .accessibilityIdentifier("quickcapture.type.note")
            Text("Habit")
                .tag(Item.ItemType.habit)
                .accessibilityIdentifier("quickcapture.type.habit")
            Text("Event")
                .tag(Item.ItemType.event)
                .accessibilityIdentifier("quickcapture.type.event")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
