import SwiftUI

struct ItemPriorityPickerRow: View {
    @Binding var priority: Item.Priority
    var title = "Priority"

    var body: some View {
        Picker(selection: $priority) {
            ForEach(Item.Priority.allCases, id: \.self) { priority in
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
                Text(priority.displayName)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }
}
