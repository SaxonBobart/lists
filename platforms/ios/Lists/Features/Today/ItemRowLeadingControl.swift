import SwiftUI

struct ItemRowLeadingControl: View {
    let item: Item
    let currentCount: Int
    let goalPerCycle: Int
    let cycleProgress: Double
    let isAtGoal: Bool
    let onToggle: () -> Void
    let onShowDetail: () -> Void
    let onIncrementHabit: () -> Void
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
            habitRing
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
        .accessibilityLabel("Edit event time")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).eventtime")
    }

    private var habitRing: some View {
        Button {
            if isAtGoal {
                onShowDetail()
            } else {
                onIncrementHabit()
            }
        } label: {
            Group {
                if isAtGoal {
                    Image("habit.completed")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(ListsTokens.Foreground.secondary, ListsTokens.accent)
                } else {
                    ZStack {
                        Image(systemName: "circle")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                        Circle()
                            .trim(from: 0, to: cycleProgress)
                            .stroke(
                                ListsTokens.accent,
                                style: StrokeStyle(lineWidth: 1.67, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                        Text("\(currentCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                    }
                }
            }
            .frame(width: 28, height: 28, alignment: .leading)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAtGoal ? "Review habit" : "Increment habit")
        .accessibilityValue("\(currentCount) of \(goalPerCycle)")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).habit")
    }
}
