import SwiftUI

struct ItemPriorityPickerRow: View {
    @Binding var priority: Item.Priority
    var title = "Priority"

    var body: some View {
        Picker(selection: $priority) {
            Text(Item.Priority.none.displayName).tag(Item.Priority.none)
            Divider()
            ForEach([Item.Priority.low, .medium, .high], id: \.self) { priority in
                Text(priority.displayName).tag(priority)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: priority.glyph)
                    .imageScale(.small)
                    .foregroundStyle(priority.iconColor)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .pickerStyle(.menu)
        .tint(ListsTokens.Foreground.secondary)
    }
}
