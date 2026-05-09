import SwiftUI

/// Sheet for creating a new list OR editing an existing one. Uses
/// SwiftUI `Form` so the chrome is iOS-native.
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
        _color = State(initialValue: existing?.color ?? .blue)
        _defaultItemType = State(initialValue: existing?.defaultItemType ?? .task)
        _groceryMode = State(initialValue: existing?.groceryMode ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(ListsTokens.listColor(color))
                            )
                        TextField("List name", text: $name)
                            .font(.title3)
                            .focused($nameFocused)
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(Self.iconChoices, id: \.self) { sym in
                            Button {
                                icon = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(icon == sym ? .white : .primary)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Circle().fill(icon == sym ? ListsTokens.listColor(color) : Color(.tertiarySystemFill))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    HStack(spacing: 14) {
                        ForEach(ItemList.ListColor.allCases, id: \.self) { c in
                            Button {
                                color = c
                            } label: {
                                Circle()
                                    .fill(ListsTokens.listColor(c))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if color == c {
                                            Circle()
                                                .strokeBorder(.primary, lineWidth: 2)
                                                .padding(-3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("Default Item Type") {
                    Picker(selection: $defaultItemType) {
                        ForEach(Item.ItemType.allCases, id: \.self) { t in
                            Text(displayName(for: t)).tag(t)
                        }
                    } label: {
                        Label("New items are", systemImage: "plus.square")
                    }
                    .pickerStyle(.menu)
                    Toggle(isOn: $groceryMode) {
                        Label("Grocery mode", systemImage: "cart.fill")
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete List", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(existing == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Delete this list?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteList() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\"\(name)\" and \(itemCountInList) item(s) will move to Recently Deleted.")
            }
            .onAppear {
                if existing == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        nameFocused = true
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemCountInList: Int {
        guard let id = existing?.id else { return 0 }
        return store.items.filter { $0.listId == id }.count
    }

    private func displayName(for t: Item.ItemType) -> String {
        switch t {
        case .task:  return "Tasks"
        case .habit: return "Habits"
        case .note:  return "Notes"
        }
    }

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
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static let iconChoices: [String] = [
        "list.bullet", "tray", "checklist", "folder", "briefcase", "house",
        "cart", "fork.knife", "leaf", "book", "graduationcap", "gamecontroller",
        "music.note", "film", "camera", "dumbbell", "heart", "person",
        "person.2", "globe", "airplane", "car", "pawprint", "sparkles"
    ]
}
