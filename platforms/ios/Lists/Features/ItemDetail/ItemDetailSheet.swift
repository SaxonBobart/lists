import SwiftUI

/// Modal sheet showing the full state of an item. Read-only for now;
/// editing lands in iter 4.
///
/// Layout follows design `ItemSheet` in `screens-detail.jsx`:
/// - Title card (checkbox + title + tags + body preview)
/// - "Date & Time" card (date / time / reminder / urgent / location)
/// - "Organization" card (flag / priority / section / sub-items / list)
struct ItemDetailSheet: View {
    let item: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                    titleCard
                    dateAndTimeCard
                    organisationCard
                    Spacer().frame(height: ListsSpacing.s8)
                }
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.top, ListsSpacing.s4)
            }
            .background(ListsTokens.Background.grouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(typeTitle)
                        .font(ListsTypography.headline)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ListsTokens.accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Title card

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            HStack(alignment: .top, spacing: 12) {
                checkbox
                Text(item.title)
                    .font(ListsTypography.title2)
                    .foregroundStyle(item.done
                                     ? ListsTokens.Foreground.tertiary
                                     : ListsTokens.Foreground.primary)
                    .strikethrough(item.done, color: ListsTokens.Foreground.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !item.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(ListsTypography.caption1)
                            .foregroundStyle(ListsTokens.accentTintFg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(ListsTokens.accentTintBg))
                    }
                }
                .padding(.leading, 36)
            }

            if !trimmedBody.isEmpty {
                Divider()
                    .background(ListsTokens.Separator.translucent)
                Text(trimmedBody)
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 36)
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var checkbox: some View {
        Button(action: {
            Task { try? await store.toggleDone(item.id) }
        }) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26))
                .foregroundStyle(item.done
                                 ? ListsTokens.accent
                                 : ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date & Time card

    private var dateAndTimeCard: some View {
        section(title: "Date & Time") {
            SheetRow(icon: "calendar", hue: ListsTokens.Hue.orange,
                     label: "Date", value: dateValue,
                     subtle: item.due == nil)
            sectionSeparator
            SheetRow(icon: "clock", hue: ListsTokens.Hue.blue,
                     label: "Time", value: timeValue,
                     subtle: item.due == nil || item.dueAllDay)
            sectionSeparator
            SheetRow(icon: "bell", hue: ListsTokens.Hue.purple,
                     label: "Reminder", value: reminderValue,
                     subtle: !(item.reminder?.enabled ?? false))
            sectionSeparator
            SheetRow(icon: "bolt.fill", hue: ListsTokens.Semantic.danger,
                     label: "Urgent",
                     value: (item.triggers?.urgent?.enabled ?? false) ? "On" : "Off",
                     subtle: !(item.triggers?.urgent?.enabled ?? false))
            sectionSeparator
            SheetRow(icon: "location", hue: ListsTokens.Hue.green,
                     label: "Location",
                     value: (item.triggers?.location?.enabled ?? false) ? "On" : "None",
                     subtle: !(item.triggers?.location?.enabled ?? false))
        }
    }

    // MARK: - Organisation card

    private var organisationCard: some View {
        section(title: "Organisation") {
            SheetRow(icon: "flag.fill", hue: ListsTokens.Semantic.warning,
                     label: "Flag", value: item.flagged ? "On" : "Off",
                     subtle: !item.flagged)
            sectionSeparator
            SheetRow(icon: "exclamationmark", hue: priorityHue,
                     label: "Priority", value: priorityValue,
                     subtle: item.priority == .none)
            sectionSeparator
            SheetRow(icon: "square.stack", hue: ListsTokens.Hue.purple,
                     label: "Section",
                     value: item.section ?? "None",
                     subtle: item.section == nil)
            sectionSeparator
            SheetRow(icon: "list.bullet.indent", hue: ListsTokens.Hue.blue,
                     label: "Sub-items",
                     value: subitemsValue,
                     subtle: subitemCount == 0)
            sectionSeparator
            SheetRow(icon: listIconName, hue: listHue,
                     label: "List", value: listName)
        }
    }

    // MARK: - Section helpers

    @ViewBuilder
    private func section<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(card)
        }
    }

    private var sectionSeparator: some View {
        Divider()
            .background(ListsTokens.Separator.translucent)
            .padding(.leading, 16 + 28 + 12) // padding + badge + gap
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    // MARK: - Computed values

    private var typeTitle: String {
        switch item.type {
        case .task: return "Task"
        case .habit: return "Habit"
        case .note: return "Note"
        }
    }

    private var trimmedBody: String {
        item.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dateValue: String {
        guard let due = item.due else { return "None" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: due)
    }

    private var timeValue: String {
        guard let due = item.due, !item.dueAllDay else {
            return item.dueAllDay ? "All-day" : "—"
        }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: due)
    }

    private var reminderValue: String {
        guard let reminder = item.reminder, reminder.enabled else { return "Off" }
        if let early = reminder.early {
            return "On · \(early.value) \(early.unit.rawValue) before"
        }
        return "On"
    }

    private var priorityValue: String {
        switch item.priority {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    private var priorityHue: Color {
        switch item.priority {
        case .none, .low: return ListsTokens.Hue.grey
        case .medium:     return ListsTokens.Hue.amber
        case .high:       return ListsTokens.Semantic.danger
        }
    }

    private var subitemCount: Int {
        store.items.filter { $0.parentId == item.id && $0.deletedAt == nil }.count
    }

    private var subitemsValue: String {
        let count = subitemCount
        if count == 0 { return "None" }
        let done = store.items.filter { $0.parentId == item.id && $0.done && $0.deletedAt == nil }.count
        return "\(done)/\(count)"
    }

    private var listName: String {
        store.lists.first(where: { $0.id == item.listId })?.name ?? item.listId
    }

    private var listIconName: String {
        store.lists.first(where: { $0.id == item.listId })?.icon ?? "tray"
    }

    private var listHue: Color {
        let color = store.lists.first(where: { $0.id == item.listId })?.color ?? .grey
        switch color {
        case .sage:   return ListsTokens.accent
        case .blue:   return ListsTokens.Hue.blue
        case .teal:   return ListsTokens.Hue.teal
        case .green:  return ListsTokens.Hue.green
        case .amber:  return ListsTokens.Hue.amber
        case .orange: return ListsTokens.Hue.orange
        case .pink:   return ListsTokens.Hue.pink
        case .purple: return ListsTokens.Hue.purple
        case .grey:   return ListsTokens.Hue.grey
        }
    }
}
