import SwiftUI

/// Picks what a single tap on a list's "+" creates inline. Long-press on
/// the "+" still opens the full capture sheet regardless of this choice.
struct DefaultNewItemTypeRow: View {
    @Binding var selection: Item.ItemType

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Item.ItemType.allCases, id: \.self) { type in
                Text(Self.label(type)).tag(type)
            }
        } label: {
            SettingsRowLabel(title: "Default Item Type", icon: "plus")
        }
        .pickerStyle(.menu)
        .tint(ListsTokens.Foreground.secondary)
        .accessibilityIdentifier("settings.defaultNewItemType.menu")
    }

    private static func label(_ type: Item.ItemType) -> String {
        switch type {
        case .task: "Task"
        case .note: "Note"
        case .event: "Event"
        }
    }

}
