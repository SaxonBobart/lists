import SwiftUI

/// One row in a list of items. See design `ListRow` in screens-mobile.jsx.
struct ItemRow: View {
    let item: Item
    let isOverdue: Bool
    let store: ItemStore
    let onToggle: () -> Void
    var indent: Int = 0

    @State private var isShowingDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: ListsSpacing.s3) {
            checkbox

            Button(action: { isShowingDetail = true }) {
                rowContent
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.leading, ListsDensity.rowPadX + CGFloat(indent) * 24)
        .padding(.trailing, ListsDensity.rowPadX)
        .contentShape(Rectangle())
        .sheet(isPresented: $isShowingDetail) {
            if item.type == .habit {
                HabitDetailView(item: item, store: store)
            } else {
                ItemDetailSheet(item: item, store: store)
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: ListsSpacing.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(ListsTypography.body)
                    .foregroundStyle(item.done
                                     ? ListsTokens.Foreground.tertiary
                                     : ListsTokens.Foreground.primary)
                    .strikethrough(item.done, color: ListsTokens.Foreground.tertiary)
                    .lineLimit(2)

                if !item.body.isEmpty {
                    Text(item.body.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(ListsTypography.subheadline)
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                        .lineLimit(1)
                }

                if let metaText = metaLine {
                    Text(metaText)
                        .font(ListsTypography.footnote)
                        .foregroundStyle(isOverdue
                                         ? ListsTokens.Semantic.danger
                                         : ListsTokens.Foreground.secondary)
                }

                if !item.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(ListsTypography.caption2)
                                .foregroundStyle(ListsTokens.accentTintFg)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(ListsTokens.accentTintBg)
                                )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if subItemSummary != nil {
                Text(subItemSummary!)
                    .font(ListsTypography.caption2)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(ListsTokens.Background.surface2))
            }

            if item.flagged {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ListsTokens.Semantic.warning)
            }
        }
    }

    /// "3/5" summary if this item has any non-deleted sub-items, else nil.
    private var subItemSummary: String? {
        let children = store.items.filter { $0.parentId == item.id && $0.deletedAt == nil }
        guard !children.isEmpty else { return nil }
        let done = children.filter(\.done).count
        return "\(done)/\(children.count)"
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
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
    }

    private var metaLine: String? {
        guard let due = item.due else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if isOverdue {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Overdue · \(formatter.string(from: due))"
        }

        if item.dueAllDay {
            return "All day"
        }

        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: due)
    }
}
