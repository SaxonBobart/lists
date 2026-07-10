import SwiftUI

/// Picks what a single tap on a list's "+" creates inline. Long-press on
/// the "+" still opens the full capture sheet regardless of this choice.
struct DefaultNewItemTypeRow: View {
    @Binding var selection: Item.ItemType
    let habitsPluginEnabled: Bool

    var body: some View {
        Picker(selection: $selection) {
            ForEach(availableTypes, id: \.self) { type in
                Text(Self.label(type)).tag(type)
            }
        } label: {
            SettingsRowLabel(title: "Default Item Type", icon: "plus")
        }
        .pickerStyle(.menu)
        .tint(ListsTokens.Foreground.secondary)
        .accessibilityIdentifier("settings.defaultNewItemType.menu")
        .onAppear(perform: normalizeSelection)
        .onChange(of: habitsPluginEnabled) { _, _ in
            normalizeSelection()
        }
    }

    private var availableTypes: [Item.ItemType] {
        itemTypePolicy.settingsDefaultTypes
    }

    private func normalizeSelection() {
        selection = itemTypePolicy.effectiveDefaultType(selection)
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    private static func label(_ type: Item.ItemType) -> String {
        switch type {
        case .task: "Task"
        case .note: "Note"
        case .habit: "Habit"
        case .event: "Event"
        }
    }

}
