import SwiftUI

/// Sheet for creating a new list OR editing an existing one. Custom
/// scroll-based layout (not `Form`) so the cards, big icon preview, and
/// color/icon grids can match the design exactly.
struct ListEditSheet: View {
    let existing: ItemList?
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    @State private var name: String
    @State private var icon: String
    @State private var color: ItemList.ListColor
    @State private var listType: ListType
    @State private var parentId: String?
    @State private var showingDeleteConfirm = false
    @State private var showingParentPicker = false

    @State private var emojiInput: String = ""
    @State private var emojiFieldFocused: Bool = false

    /// Local two-state list type. Internally maps to
    /// `defaultItemType = .task` (+ `groceryMode` for shopping).
    private enum ListType: Hashable {
        case standard
        case shopping

        var iconName: String {
            switch self {
            case .standard: return "list.bullet"
            case .shopping: return "cart.fill"
            }
        }

        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .shopping: return "Shopping"
            }
        }
    }

    /// `initialParentId` only applies when creating a new list — it
    /// pre-fills the Parent picker so "+ New sub-list here" lands the new
    /// list under the right parent. Ignored when editing (`existing != nil`).
    init(existing: ItemList? = nil, store: ItemStore, initialParentId: String? = nil) {
        self.existing = existing
        self.store = store
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? "list.bullet")
        _color = State(initialValue: existing?.color ?? .blue)
        _listType = State(initialValue: (existing?.groceryMode ?? false) ? .shopping : .standard)
        _parentId = State(initialValue: existing?.parentId ?? initialParentId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    iconAndNameCard
                    listTypeCard
                    parentRowCard
                    colorGridCard
                    iconGridCard
                    if existing != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(existing == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel(existing == nil ? "Add" : "Save")
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Delete this list?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteList() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(deleteConfirmMessage)
            }
            .sheet(isPresented: $showingParentPicker) {
                ParentPickerSheet(
                    store: store,
                    movingListId: existing?.id,
                    initialSelection: parentId
                ) { picked in
                    parentId = picked
                }
            }
            .onAppear {
                if existing == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        nameFocused = true
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                // Inline emoji-keyboard bridge. Permanent in the hierarchy
                // (NOT in a sheet) so the keyboard pops up directly over
                // the New List sheet — no extra UI required.
                EmojiInputField(text: $emojiInput, isFocused: $emojiFieldFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if emojiFieldFocused {
                    Button {
                        emojiFieldFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .accessibilityLabel("Hide keyboard")
                }
            }
            .animation(.snappy(duration: 0.2), value: emojiFieldFocused)
            .onChange(of: emojiInput) { _, new in
                guard !new.isEmpty else { return }
                let candidate = String(new.prefix(1))
                if candidate.unicodeScalars.contains(where: {
                    $0.properties.isEmojiPresentation || $0.properties.isEmoji
                }) {
                    icon = candidate
                }
                emojiInput = ""
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Cards

    private var iconAndNameCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(ListsTokens.listColor(color))
                    .frame(width: 84, height: 84)
                ListIconGlyph(
                    icon: icon,
                    size: 38,
                    weight: .semibold,
                    color: .white
                )
            }
            .padding(.top, 4)

            TextField("List Name", text: $name)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var parentRowCard: some View {
        Button {
            showingParentPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.gray)
                    )

                Text("Parent")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(parentDisplayName)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var parentDisplayName: String {
        guard let id = parentId,
              let parent = store.lists.first(where: { $0.id == id })
        else { return "Root" }
        return parent.name
    }

    private var listTypeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: listType.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.blue)
                )

            Text("List Type")
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Menu {
                Picker("", selection: $listType) {
                    Label("Standard", systemImage: "list.bullet").tag(ListType.standard)
                    Label("Shopping", systemImage: "cart.fill").tag(ListType.shopping)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(listType.displayName)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var colorGridCard: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(ListsTokens.listColorPalette, id: \.self) { c in
                Button {
                    color = c
                } label: {
                    ZStack {
                        Circle()
                            .fill(ListsTokens.listColor(c))
                            .frame(width: 38, height: 38)
                        if color == c {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(c.rawValue.capitalized))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconGridCard: some View {
        let cells: [IconCell] = [.emoji] + Self.iconChoices.map { .symbol($0) }
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(cells, id: \.self) { cell in
                iconCell(cell)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private enum IconCell: Hashable {
        case emoji
        case symbol(String)
    }

    @ViewBuilder
    private func iconCell(_ cell: IconCell) -> some View {
        switch cell {
        case .emoji:
            let isSelected = !ListIconGlyph.isSFSymbol(icon)
            Button {
                nameFocused = false
                emojiFieldFocused = true
            } label: {
                ZStack {
                    // Two-tone: full circle in muted blue, with the smile
                    // glyph drawn in bright blue. The glyph's eye/mouth
                    // cutouts reveal the darker blue underneath. This
                    // appearance never changes — picking an emoji updates
                    // the big preview, not the button.
                    Circle()
                        .fill(Color.blue.opacity(0.30))
                        .frame(width: 38, height: 38)
                    Image(systemName: "face.smiling.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.blue)

                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pick emoji")

        case .symbol(let sym):
            let isSelected = (icon == sym)
            Button {
                icon = sym
            } label: {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)
                    Image(systemName: sym)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(sym))
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Text("Delete List")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 8)
    }

    // MARK: - Derived

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemCountInList: Int {
        guard let id = existing?.id else { return 0 }
        return store.items.filter { $0.listId == id }.count
    }

    // MARK: - Actions

    private func save() {
        let now = Date()
        let nextPosition = nextSiblingPosition(under: parentId)
        let updated = ItemList(
            id: existing?.id ?? Self.newListId(),
            name: trimmedName,
            icon: icon,
            color: color,
            defaultItemType: .task,
            groceryMode: listType == .shopping,
            createdAt: existing?.createdAt ?? now,
            modifiedAt: now,
            position: existing?.position ?? nextPosition,
            parentId: parentId,
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

    /// Next free `position` value among siblings under `parent`. Keeps
    /// new lists below existing peers and avoids cross-group renumbering.
    private func nextSiblingPosition(under parent: String?) -> Double {
        let siblings = store.lists.filter { $0.parentId == parent && $0.deletedAt == nil }
        return (siblings.map(\.position).max() ?? 0) + 1
    }

    private var deleteConfirmMessage: String {
        let descCount = existing.map { store.descendantIds(of: $0.id).count } ?? 0
        let itemPart = "\"\(name)\" and \(itemCountInList) item(s) will move to Recently Deleted."
        if descCount > 0 {
            return itemPart + " This will also delete \(descCount) sub-list(s)."
        }
        return itemPart
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

    // MARK: - Icon palette

    /// Minimal v1 palette. Emoji cell is prepended in `iconGridCard`.
    private static let iconChoices: [String] = [
        "list.bullet",
        "checklist",
        "calendar.badge.checkmark",
        "cart.fill"
    ]
}
