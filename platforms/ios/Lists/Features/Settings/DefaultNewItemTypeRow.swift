import SwiftUI

/// Picks what a single tap on a list's "+" creates inline. Long-press on
/// the "+" still opens the full capture sheet regardless of this choice.
struct DefaultNewItemTypeRow: View {
    @Binding var selection: Item.ItemType

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "plus", hue: ListsTokens.Hue.green)
            Text("New Item from +")
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Menu {
                Picker("New Item from +", selection: $selection) {
                    ForEach([Item.ItemType.task, .note, .habit, .event], id: \.self) { type in
                        Label(Self.label(type), systemImage: Self.icon(type)).tag(type)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(Self.label(selection))
                        .font(ListsTypography.callout)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ListsTokens.Foreground.quaternary)
                }
            }
            .accessibilityIdentifier("settings.defaultNewItemType.menu")
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private static func label(_ type: Item.ItemType) -> String {
        switch type {
        case .task: "Task"
        case .note: "Note"
        case .habit: "Habit"
        case .event: "Event"
        }
    }

    private static func icon(_ type: Item.ItemType) -> String {
        switch type {
        case .task: "circle"
        case .note: "text.document"
        case .habit: "repeat"
        case .event: "calendar"
        }
    }
}
