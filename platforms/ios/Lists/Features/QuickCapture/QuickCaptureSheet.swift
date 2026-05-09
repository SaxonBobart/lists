import SwiftUI

/// Bottom sheet for adding a new task quickly. Title field auto-focuses,
/// optional date toggle, list picker. "Add" button persists via
/// `ItemStore.add(...)`. See spec §2.1 + design `ItemSheet`.
struct QuickCaptureSheet: View {
    let store: ItemStore
    let defaultListId: String
    let defaultSection: String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var title: String = ""
    @State private var listId: String
    @State private var hasDate: Bool = false
    @State private var due: Date = .now
    @State private var hasTime: Bool = false
    @State private var flagged: Bool = false

    init(store: ItemStore, defaultListId: String = ItemList.inboxId, defaultSection: String? = nil) {
        self.store = store
        self.defaultListId = defaultListId
        self.defaultSection = defaultSection
        _listId = State(initialValue: defaultListId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                    titleCard
                    optionsCard
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
                    Text("New Task")
                        .font(ListsTypography.headline)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { add() }
                        .foregroundStyle(ListsTokens.accent)
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Title card

    private var titleCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .font(.system(size: 26))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28)

            TextField("New task", text: $title, axis: .vertical)
                .font(ListsTypography.title3)
                .foregroundStyle(ListsTokens.Foreground.primary)
                .focused($titleFocused)
                .lineLimit(1...4)
                .submitLabel(.done)
                .onSubmit { if !trimmedTitle.isEmpty { add() } }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    // MARK: - Options card

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            editRow(icon: "calendar", hue: ListsTokens.Hue.orange, label: "Date") {
                Toggle("", isOn: $hasDate)
                    .labelsHidden()
                    .tint(ListsTokens.accent)
            }
            if hasDate {
                separator
                HStack {
                    Text("When")
                        .font(ListsTypography.callout)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                    Spacer()
                    DatePicker("", selection: $due,
                               displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                }
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.vertical, 8)
                separator
                editRow(icon: "clock", hue: ListsTokens.Hue.blue, label: "Include time") {
                    Toggle("", isOn: $hasTime)
                        .labelsHidden()
                        .tint(ListsTokens.accent)
                }
            }
            separator
            editRow(icon: "flag.fill", hue: ListsTokens.Semantic.warning, label: "Flag") {
                Toggle("", isOn: $flagged)
                    .labelsHidden()
                    .tint(ListsTokens.accent)
            }
            separator
            editRow(icon: listIconName, hue: listHue, label: "List") {
                Menu {
                    ForEach(activeLists, id: \.id) { list in
                        Button(list.name) { listId = list.id }
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
        .background(card)
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

    private var separator: some View {
        Divider()
            .background(ListsTokens.Separator.translucent)
            .padding(.leading, 16 + 28 + 12)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    // MARK: - Computed

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var listName: String {
        store.lists.first(where: { $0.id == listId })?.name ?? listId
    }

    private var listIconName: String {
        store.lists.first(where: { $0.id == listId })?.icon ?? "tray"
    }

    private var listHue: Color {
        let color = store.lists.first(where: { $0.id == listId })?.color ?? .grey
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

    // MARK: - Action

    private func add() {
        let listType = store.lists.first(where: { $0.id == listId })?.defaultItemType ?? .task
        let item = Item(
            type: listType,
            title: trimmedTitle,
            listId: listId,
            section: defaultSection,
            due: hasDate ? due : nil,
            dueAllDay: hasDate && !hasTime,
            flagged: flagged,
            frequency: listType == .habit ? .daily : nil,
            goalPerCycle: listType == .habit ? 1 : 1,
            showStreak: listType == .habit
        )
        Task {
            try? await store.add(item)
            dismiss()
        }
    }
}
