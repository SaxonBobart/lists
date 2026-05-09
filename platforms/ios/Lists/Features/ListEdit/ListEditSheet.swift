import SwiftUI

/// Sheet for creating a new list OR editing an existing one. Mode is
/// inferred from `existing`: nil → create; non-nil → edit.
struct ListEditSheet: View {
    let existing: ItemList?
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    @State private var name: String
    @State private var icon: String
    @State private var color: ItemList.ListColor
    @State private var defaultItemType: Item.ItemType
    @State private var groceryMode: Bool
    @State private var showingDeleteConfirm = false

    init(existing: ItemList? = nil, store: ItemStore) {
        self.existing = existing
        self.store = store
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? "list.bullet")
        _color = State(initialValue: existing?.color ?? .sage)
        _defaultItemType = State(initialValue: existing?.defaultItemType ?? .task)
        _groceryMode = State(initialValue: existing?.groceryMode ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                    nameCard
                    iconCard
                    colorCard
                    typeCard
                    if existing != nil {
                        deleteButton
                    }
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
                    Text(existing == nil ? "New List" : "Edit List")
                        .font(ListsTypography.headline)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(existing == nil ? "Add" : "Save") { save() }
                        .foregroundStyle(ListsTokens.accent)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Delete this list?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteList() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\"\(name)\" and \(itemCountInList) item(s) will be removed.")
            }
            .onAppear {
                if existing == nil { nameFocused = true }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cards

    private var nameCard: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hueFor(color))
            TextField("List name", text: $name)
                .font(ListsTypography.title3)
                .foregroundStyle(ListsTokens.Foreground.primary)
                .focused($nameFocused)
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                ForEach(Self.iconChoices, id: \.self) { sym in
                    Button(action: { icon = sym }) {
                        Image(systemName: sym)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(icon == sym ? .white : ListsTokens.Foreground.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(icon == sym ? ListsTokens.accent : ListsTokens.Background.surface2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(ListsSpacing.s3)
            .background(card)
        }
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            HStack(spacing: 14) {
                ForEach(ItemList.ListColor.allCases, id: \.self) { c in
                    Button(action: { color = c }) {
                        Circle()
                            .fill(hueFor(c))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if color == c {
                                    Circle()
                                        .stroke(ListsTokens.Foreground.primary, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(ListsSpacing.s4)
            .background(card)
        }
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default Item Type")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Item.ItemType.allCases, id: \.self) { t in
                    Button(action: { defaultItemType = t }) {
                        HStack {
                            Text(displayName(for: t))
                                .font(ListsTypography.callout)
                                .foregroundStyle(ListsTokens.Foreground.primary)
                            Spacer()
                            if defaultItemType == t {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(ListsTokens.accent)
                            }
                        }
                        .padding(.horizontal, ListsSpacing.s4)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if t != Item.ItemType.allCases.last {
                        Divider()
                            .background(ListsTokens.Separator.translucent)
                            .padding(.leading, ListsSpacing.s4)
                    }
                }
            }
            .background(card)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete List")
            }
            .font(ListsTypography.body.weight(.medium))
            .foregroundStyle(ListsTokens.Semantic.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(card)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemCountInList: Int {
        guard let id = existing?.id else { return 0 }
        return store.items.filter { $0.listId == id }.count
    }

    private func hueFor(_ c: ItemList.ListColor) -> Color {
        switch c {
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

    private func displayName(for t: Item.ItemType) -> String {
        switch t {
        case .task:  return "Tasks"
        case .habit: return "Habits"
        case .note:  return "Notes"
        }
    }

    // MARK: - Actions

    private func save() {
        let now = Date()
        let nextPosition = (store.lists.map(\.position).max() ?? 0) + 1
        let updated = ItemList(
            id: existing?.id ?? Self.newListId(),
            name: trimmedName,
            icon: icon,
            color: color,
            defaultItemType: defaultItemType,
            groceryMode: groceryMode,
            createdAt: existing?.createdAt ?? now,
            modifiedAt: now,
            position: existing?.position ?? nextPosition,
            deletedAt: existing?.deletedAt,
            lamport: (existing?.lamport ?? 0) + 1
        )
        Task {
            if existing == nil {
                try? await store.addList(updated)
            } else {
                try? await store.updateList(updated)
            }
            dismiss()
        }
    }

    private func deleteList() {
        guard let existing else { return }
        Task {
            try? await store.softDeleteList(existing.id)
            dismiss()
        }
    }

    private static func newListId() -> String {
        // Lowercased UUID without dashes; OK as ULID-shaped placeholder for v1.
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - Icon choices

    private static let iconChoices: [String] = [
        "list.bullet", "tray", "checklist", "folder", "briefcase",
        "house", "cart", "fork.knife", "leaf", "book",
        "graduationcap", "gamecontroller", "music.note", "film", "camera",
        "dumbbell", "heart", "person", "person.2", "globe",
        "airplane", "car", "pawprint", "sparkles"
    ]
}
