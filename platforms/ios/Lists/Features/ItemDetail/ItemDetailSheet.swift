import SwiftUI

/// Modal sheet for viewing AND editing an item. Title + body inline,
/// metadata in cards, Save commits via `ItemStore.update`, Delete via
/// `ItemStore.delete`.
///
/// Layout follows design `ItemSheet` in `screens-detail.jsx` but adapts
/// the inline value rows into native SwiftUI controls.
struct ItemDetailSheet: View {
    let originalItem: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    @State private var draft: Item
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var reminderEnabled: Bool
    @State private var showingDeleteConfirm = false

    init(item: Item, store: ItemStore) {
        self.originalItem = item
        self.store = store
        _draft = State(initialValue: item)
        _hasDate = State(initialValue: item.due != nil)
        _hasTime = State(initialValue: item.due != nil && !item.dueAllDay)
        _reminderEnabled = State(initialValue: item.reminder?.enabled ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                    titleCard
                    dateAndReminderCard
                    organisationCard
                    deleteButton
                    Spacer().frame(height: ListsSpacing.s8)
                }
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.top, ListsSpacing.s4)
            }
            .background(ListsTokens.Background.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(typeTitle)
                        .font(ListsTypography.headline)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(ListsTokens.accent)
                        .fontWeight(.semibold)
                        .disabled(!isDirty)
                }
            }
            .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(draft.title) will be removed.")
            }
            .navigationDestination(for: ThreadDestination.self) { dest in
                if let root = store.items.first(where: { $0.id == dest.rootId }) {
                    ThreadView(root: root, store: store)
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
                TextField("Title", text: $draft.title, axis: .vertical)
                    .font(ListsTypography.title2)
                    .foregroundStyle(draft.done
                                     ? ListsTokens.Foreground.tertiary
                                     : ListsTokens.Foreground.primary)
                    .lineLimit(1...3)
                    .submitLabel(.done)
            }

            if !draft.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(draft.tags, id: \.self) { tag in
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

            Divider()
                .background(ListsTokens.Separator.translucent)

            TextField("Notes", text: $draft.body, axis: .vertical)
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .lineLimit(3...20)
                .padding(.leading, 36)
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var checkbox: some View {
        Button(action: {
            draft.done.toggle()
            draft.completedAt = draft.done ? .now : nil
        }) {
            Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26))
                .foregroundStyle(draft.done
                                 ? ListsTokens.accent
                                 : ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date + reminder card

    private var dateAndReminderCard: some View {
        section(title: "Date & Reminder") {
            editRow(icon: "calendar", hue: ListsTokens.Hue.orange, label: "Date") {
                Toggle("", isOn: $hasDate)
                    .labelsHidden()
                    .tint(ListsTokens.accent)
                    .onChange(of: hasDate) { _, newValue in
                        if newValue, draft.due == nil { draft.due = .now }
                        if !newValue { draft.due = nil; hasTime = false }
                    }
            }
            if hasDate {
                sectionSeparator
                HStack {
                    Text("When")
                        .font(ListsTypography.callout)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                    Spacer()
                    DatePicker("",
                               selection: Binding(
                                get: { draft.due ?? .now },
                                set: { draft.due = $0 }
                               ),
                               displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                }
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.vertical, 8)

                sectionSeparator
                editRow(icon: "clock", hue: ListsTokens.Hue.blue, label: "Include time") {
                    Toggle("", isOn: $hasTime)
                        .labelsHidden()
                        .tint(ListsTokens.accent)
                        .onChange(of: hasTime) { _, newValue in
                            draft.dueAllDay = !newValue
                        }
                }

                sectionSeparator
                editRow(icon: "bell", hue: ListsTokens.Hue.purple, label: "Remind me") {
                    Toggle("", isOn: $reminderEnabled)
                        .labelsHidden()
                        .tint(ListsTokens.accent)
                        .onChange(of: reminderEnabled) { _, newValue in
                            if newValue {
                                draft.reminder = Reminder(enabled: true, early: draft.reminder?.early)
                            } else {
                                draft.reminder = Reminder(enabled: false, early: draft.reminder?.early)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Organisation card

    private var organisationCard: some View {
        section(title: "Organisation") {
            editRow(icon: "flag.fill", hue: ListsTokens.Semantic.warning, label: "Flag") {
                Toggle("", isOn: $draft.flagged)
                    .labelsHidden()
                    .tint(ListsTokens.accent)
            }
            sectionSeparator
            editRow(icon: "exclamationmark", hue: priorityHue, label: "Priority") {
                Menu {
                    ForEach(Item.Priority.allCases, id: \.self) { p in
                        Button(displayName(for: p)) { draft.priority = p }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(displayName(for: draft.priority))
                            .font(ListsTypography.callout)
                            .foregroundStyle(draft.priority == .none
                                             ? ListsTokens.Foreground.tertiary
                                             : ListsTokens.Foreground.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                    }
                }
            }
            if subItemCount > 0 {
                sectionSeparator
                NavigationLink(value: ThreadDestination(rootId: draft.id)) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: "list.bullet.indent", hue: ListsTokens.Hue.blue)
                        Text("Thread view")
                            .font(ListsTypography.callout)
                            .foregroundStyle(ListsTokens.Foreground.primary)
                        Spacer()
                        Text(subitemsValue)
                            .font(ListsTypography.callout)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ListsTokens.Foreground.quaternary)
                    }
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            sectionSeparator
            editRow(icon: listIconName, hue: listHue, label: "List") {
                Menu {
                    ForEach(store.lists.filter { $0.deletedAt == nil }, id: \.id) { list in
                        Button(list.name) { draft.listId = list.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(listName)
                            .font(ListsTypography.callout)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Item")
            }
            .font(ListsTypography.body.weight(.medium))
            .foregroundStyle(ListsTokens.Semantic.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(card)
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private func editRow<Trailing: View>(
        icon: String, hue: Color, label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue)
            Text(label)
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    private var sectionSeparator: some View {
        Divider()
            .background(ListsTokens.Separator.translucent)
            .padding(.leading, 16 + 28 + 12)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    // MARK: - Computed

    private var typeTitle: String {
        switch draft.type {
        case .task: return "Task"
        case .habit: return "Habit"
        case .note: return "Note"
        }
    }

    private var isDirty: Bool {
        draft != originalItem
    }

    private var priorityHue: Color {
        switch draft.priority {
        case .none, .low: return ListsTokens.Hue.grey
        case .medium:     return ListsTokens.Hue.amber
        case .high:       return ListsTokens.Semantic.danger
        }
    }

    private var subItemCount: Int {
        store.items.filter { $0.parentId == draft.id && $0.deletedAt == nil }.count
    }

    private var subitemsValue: String {
        let count = subItemCount
        if count == 0 { return "None" }
        let done = store.items.filter { $0.parentId == draft.id && $0.done && $0.deletedAt == nil }.count
        return "\(done)/\(count)"
    }

    private func displayName(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    private var listName: String {
        store.lists.first(where: { $0.id == draft.listId })?.name ?? draft.listId
    }

    private var listIconName: String {
        store.lists.first(where: { $0.id == draft.listId })?.icon ?? "tray"
    }

    private var listHue: Color {
        let color = store.lists.first(where: { $0.id == draft.listId })?.color ?? .grey
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

    // MARK: - Actions

    private func save() {
        Task {
            try? await store.update(draft)
            dismiss()
        }
    }

    private func delete() {
        Task {
            try? await store.softDelete(draft.id)
            dismiss()
        }
    }
}
