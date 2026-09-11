import SwiftUI

struct ItemRowLeadingControl: View {
    let item: Item
    let currentCount: Int
    let goalPerCycle: Int
    let cycleProgress: Double
    let isAtGoal: Bool
    let onToggle: () -> Void
    let onShowDetail: () -> Void
    let onEditEventTime: () -> Void

    var body: some View {
        switch item.type {
        case .task:
            checkbox
        case .event where item.completable:
            checkbox
        case .event:
            eventIcon
        case .note:
            noteIcon
        case .habit:
            EmptyView()
        }
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            Group {
                if item.done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(ListsTokens.accent)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
            }
            .frame(width: 28, height: 28, alignment: .leading)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .padding(-8)
        .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).checkbox")
    }

    private var noteIcon: some View {
        Button { onShowDetail() } label: {
            Image(systemName: "text.document.fill")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .padding(-8)
        .accessibilityLabel("Open note")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).opennote")
    }

    private var eventIcon: some View {
        Button { onEditEventTime() } label: {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .padding(-8)
        .accessibilityLabel("Edit event time")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).eventtime")
    }


}
